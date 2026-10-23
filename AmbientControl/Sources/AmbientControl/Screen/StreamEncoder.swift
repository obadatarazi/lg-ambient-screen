import AVFoundation
import UniformTypeIdentifiers
import VideoToolbox

/// Encodes the shared screen (hardware H.264 via VideoToolbox) and the Mac's sound (AAC) into
/// fragmented-MP4 segments for the TV.
///
/// - Frames are re-sent at a steady rate, because ScreenCaptureKit only delivers a frame when the
///   screen changes; segments keep flowing and the TV stays live.
/// - The bitrate can change while streaming (`setBitrate`), which is what Auto quality needs.
/// - The audio track never has gaps: silence fills in when nothing is playing, because the TV's
///   player stops at any hole in the audio.
final class StreamEncoder: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    static let sampleRate = 48_000

    let queue = DispatchQueue(label: "ambient.screen.encode", qos: .userInteractive)
    private let fps: Int
    private let onSegment: (Data, AVAssetSegmentType) -> Void
    private var session: VTCompressionSession?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var timer: DispatchSourceTimer?
    private var latest: CVPixelBuffer?
    private var lastPTS = CMTime.invalid
    private var needKeyFrame = true

    // Audio: interleaved stereo float samples waiting to be written, and how many frames the
    // track already holds (its timeline starts with the video).
    private var fifo: [Float] = []
    private var primed = false
    private var t0 = CMTime.invalid
    private var audioFrames = 0

    // AAC is encoded here rather than by the writer: it cannot mix its own audio encoding with
    // already-encoded video in an HLS file.
    private let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                                    channels: 2, interleaved: true)!
    private var aac: AVAudioConverter?
    private var aacFormat: CMAudioFormatDescription?
    private var aacPackets = 0

    init(width: Int, height: Int, fps: Int, bitrate: Int,
         onSegment: @escaping (Data, AVAssetSegmentType) -> Void) throws {
        self.fps = fps
        self.onSegment = onSegment
        super.init()
        var s: VTCompressionSession?
        let spec = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let s else { throw CocoaError(.featureUnsupported) }
        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            // A keyframe every half second: each segment starts with one, so the TV can join
            // or catch up at any segment.
            kVTCompressionPropertyKey_MaxKeyFrameInterval: max(1, fps / 2),
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 0.5,
            kVTCompressionPropertyKey_ExpectedFrameRate: fps,
        ]
        VTSessionSetProperties(s, propertyDictionary: props as CFDictionary)
        session = s
        applyBitrate(bitrate)
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    func begin() {
        queue.sync {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(fps), leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    func end() {
        queue.sync {
            timer?.cancel()
            timer = nil
            latest = nil
            if let session {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(session)
            }
            session = nil
            if let writer, writer.status == .writing {
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                writer.finishWriting {}
            }
            writer = nil
        }
    }

    /// Changes the video bitrate without restarting the stream.
    func setBitrate(_ bps: Int) {
        queue.async { self.applyBitrate(bps) }
    }

    private func applyBitrate(_ bps: Int) {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        // Caps short bursts (a full-screen change) so a segment never floods the Wi-Fi.
        let limits = [Double(bps) / 8 * 1.5, 1.0] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
    }

    // MARK: - Input (on `queue`)

    func push(video pixels: CVPixelBuffer) {
        latest = pixels
    }

    /// Adds captured sound (32-bit float PCM, interleaved or one buffer per channel).
    func push(audio sample: CMSampleBuffer) {
        guard t0.isValid,
              let fmt = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        let frames = sample.numSamples
        let channels = Int(asbd.mChannelsPerFrame)
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        try? sample.withAudioBufferList { list, _ in
            fifo.reserveCapacity(fifo.count + frames * 2)
            if interleaved, let p = list.first?.mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<frames {
                    let l = p[i * channels]
                    fifo.append(l)
                    fifo.append(channels > 1 ? p[i * channels + 1] : l)
                }
            } else if let l = list.first?.mData?.assumingMemoryBound(to: Float.self) {
                let r = list.count > 1 ? list[1].mData?.assumingMemoryBound(to: Float.self) ?? l : l
                for i in 0..<frames {
                    fifo.append(l[i])
                    fifo.append(r[i])
                }
            }
        }
    }

    // MARK: - Encoding

    private func tick() {
        guard let session, let pb = latest else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard !lastPTS.isValid || now > lastPTS else { return }
        lastPTS = now
        let opts: CFDictionary? = needKeyFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        needKeyFrame = false
        VTCompressionSessionEncodeFrame(session, imageBuffer: pb, presentationTimeStamp: now,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)), frameProperties: opts, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.queue.async { self.write(sample) }
        }
        pumpAudio(now: now)
    }

    private func write(_ sample: CMSampleBuffer) {
        if writer == nil { startWriter(with: sample) }
        guard let writer, writer.status == .writing, let videoInput else { return }
        if videoInput.isReadyForMoreMediaData, !waitingForKeyFrame || isKeyFrame(sample) {
            if isKeyFrame(sample), hasVideo { writer.flushSegment() }
            waitingForKeyFrame = !videoInput.append(sample)
            hasVideo = true
        } else {
            // A dropped frame breaks the frames after it until the next keyframe.
            waitingForKeyFrame = true
            needKeyFrame = true
        }
    }

    private var waitingForKeyFrame = false
    private var hasVideo = false

    private func isKeyFrame(_ sample: CMSampleBuffer) -> Bool {
        guard let a = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
              let first = a.first else { return true }
        return first[kCMSampleAttachmentKey_NotSync] as? Bool != true
    }

    /// The writer needs the encoder's output format, so it starts with the first frame.
    private func startWriter(with sample: CMSampleBuffer) {
        let w = AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue)!)
        w.outputFileTypeProfile = .mpeg4AppleHLS
        // Segments are cut by hand at each keyframe (every half second, see `write`): the TV
        // starts sooner and stays a little closer to live.
        w.preferredOutputSegmentInterval = .indefinite
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: sample.formatDescription)
        v.expectsMediaDataInRealTime = true
        guard let aacOut = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                    AVSampleRateKey: Self.sampleRate,
                                                    AVNumberOfChannelsKey: 2]),
              let converter = AVAudioConverter(from: pcm, to: aacOut) else { return }
        converter.bitRate = 160_000
        var asbd = aacOut.streamDescription.pointee
        asbd.mFramesPerPacket = 1024  // gives each packet its duration
        var desc: CMAudioFormatDescription?
        let cookie = converter.magicCookie
        cookie?.withUnsafeBytes { raw in
            _ = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                               magicCookieSize: raw.count, magicCookie: raw.baseAddress,
                                               extensions: nil, formatDescriptionOut: &desc)
        }
        guard let desc else { return }
        aac = converter
        aacFormat = desc
        aacPackets = 0
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: desc)
        a.expectsMediaDataInRealTime = true
        guard w.canAdd(v), w.canAdd(a) else { return }
        w.add(v)
        w.add(a)
        w.delegate = self
        let start = sample.presentationTimeStamp
        w.initialSegmentStartTime = start
        w.startWriting()
        w.startSession(atSourceTime: start)
        writer = w
        videoInput = v
        audioInput = a
        t0 = start
        fifo.removeAll()
    }

    /// Writes sound up to just behind "now", in 1024-frame AAC packets. Missing sound becomes
    /// silence; a backlog (the Mac's audio clock running slightly fast) is trimmed so picture
    /// and sound stay together.
    private func pumpAudio(now: CMTime) {
        guard t0.isValid, let audioInput, writer?.status == .writing else { return }
        let rate = Self.sampleRate
        let packet = 1024
        let due = (Int((now - t0).seconds * Double(rate)) - rate / 25 - audioFrames) / packet * packet
        guard due > 0 else { return }
        var have = fifo.count / 2
        if have > due + rate / 5 {
            fifo.removeFirst((have - due - rate / 20) * 2)
            have = fifo.count / 2
        }
        // Wait for ~50 ms of sound before playing it, so small capture hiccups don't click.
        if !primed { primed = have >= rate / 20 }
        guard audioInput.isReadyForMoreMediaData else { return }
        let take = primed ? min(due, have) : 0
        var chunk = Array(fifo.prefix(take * 2))
        fifo.removeFirst(take * 2)
        if take < due {
            chunk.append(contentsOf: repeatElement(0, count: (due - take) * 2))
            primed = false
        }
        for start in stride(from: 0, to: due, by: packet) {
            encodePacket(chunk[(start * 2)..<((start + packet) * 2)], into: audioInput)
        }
        audioFrames += due
    }

    private func encodePacket(_ samples: ArraySlice<Float>, into input: AVAssetWriterInput) {
        guard let aac, let aacFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 1024) else { return }
        buffer.frameLength = 1024
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: src.count)
        }
        let out = AVAudioCompressedBuffer(format: aac.outputFormat, packetCapacity: 4,
                                          maximumPacketSize: max(aac.maximumOutputPacketSize, 1536))
        var fed = false
        var error: NSError?
        _ = aac.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard let descs = out.packetDescriptions else { return }
        for i in 0..<Int(out.packetCount) {
            let d = descs[i]
            let index = aacPackets
            aacPackets += 1
            // The encoder's output lags its input by 2112 frames (priming). Shift it back so
            // sound lines up with the picture; the first packets are only that priming.
            let frame = index * 1024 - 2112
            guard frame >= 0 else { continue }
            let bytes = Int(d.mDataByteSize)
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block) == noErr, let block else { continue }
            CMBlockBufferReplaceDataBytes(with: out.data + Int(d.mStartOffset), blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: bytes)
            var desc = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: d.mDataByteSize)
            var sample: CMSampleBuffer?
            let pts = t0 + CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Self.sampleRate))
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: aacFormat, sampleCount: 1,
                presentationTimeStamp: pts, packetDescriptions: &desc, sampleBufferOut: &sample)
            if let sample { input.append(sample) }
        }
    }

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
                     segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        onSegment(segmentData, segmentType)
    }
}
