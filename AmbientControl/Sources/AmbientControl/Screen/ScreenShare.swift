import AppKit
import AVFoundation
import CoreAudio
import Observation
import ScreenCaptureKit

/// Captures one Mac display and its sound with ScreenCaptureKit, encodes them on the Mac's
/// hardware (`StreamEncoder`) and serves fragmented-MP4 segments (`SegmentHub`). The TV plays
/// them with its hardware decoder, so streaming barely touches its CPU.
///
/// Everything travels over the home Wi-Fi, never the internet. Auto quality watches how fast
/// the TV downloads each segment and keeps the bitrate within what the Wi-Fi carries.
@MainActor
@Observable
final class ScreenShare {
    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let width: Int
        let height: Int
        var thumbnail: NSImage?
        var isMain: Bool
    }

    enum Quality: String, CaseIterable, Identifiable {
        case smooth = "Smooth"
        case sharp = "Sharp"

        var id: String { rawValue }
        // Tuned on a 2017 LG (webOS 3.5): its decoder handles 720p60 without dropped frames,
        // and the Mac→TV Wi-Fi link measured ~13 Mbit/s, so both stay well below that.
        var width: Int { self == .smooth ? 1280 : 1920 }
        var fps: Int { self == .smooth ? 60 : 30 }
        /// The most Auto quality will use; it lowers this when the Wi-Fi is busy.
        var bitrate: Int { self == .smooth ? 6_000_000 : 8_000_000 }
        var detail: String { self == .smooth ? "720p · 60 fps, smoothest" : "1080p · 30 fps, crisp text" }
    }

    private(set) var displays: [Display] = []
    var selectedID: CGDirectDisplayID?
    var quality: Quality = .smooth
    var showCursor = true
    var hideThisApp = true
    var playSound = true { didSet { UserDefaults.standard.set(playSound, forKey: "shareSound") } }
    var muteMac = true { didSet { UserDefaults.standard.set(muteMac, forKey: "shareMuteMac") } }
    private(set) var isSharing = false
    private(set) var error: String?
    private(set) var permissionDenied = false
    private(set) var fps = 0
    private(set) var kbps = 0
    /// What the encoder is currently aiming for (Auto quality), and the Wi-Fi speed the TV measured.
    private(set) var targetKbps = 0
    private(set) var linkKbps = 0

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var encoder: StreamEncoder?
    @ObservationIgnored private var capture: CaptureOutput?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var macWasMuted: Bool?

    init() {
        let d = UserDefaults.standard
        playSound = d.object(forKey: "shareSound") as? Bool ?? true
        muteMac = d.object(forKey: "shareMuteMac") as? Bool ?? true
    }

    var selected: Display? { displays.first { $0.id == selectedID } }

    func refreshDisplays() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionDenied = false
            let names = Dictionary(NSScreen.screens.compactMap { s -> (CGDirectDisplayID, String)? in
                guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                return (CGDirectDisplayID(n.uint32Value), s.localizedName)
            }, uniquingKeysWith: { a, _ in a })
            let main = CGMainDisplayID()
            displays = content.displays.map { d in
                Display(id: d.displayID, name: names[d.displayID] ?? "Display \(d.displayID)",
                        width: d.width, height: d.height,
                        thumbnail: displays.first { $0.id == d.displayID }?.thumbnail,
                        isMain: d.displayID == main)
            }
            .sorted { $0.isMain && !$1.isMain }
            if selected == nil { selectedID = displays.first?.id }
            for d in content.displays { await loadThumbnail(d) }
        } catch {
            permissionDenied = true
            self.error = "Allow screen recording for Ambient Control in System Settings, then reopen the app."
        }
    }

    private func loadThumbnail(_ display: SCDisplay) async {
        let config = SCStreamConfiguration()
        config.width = 480
        config.height = max(1, Int(480.0 * Double(display.height) / Double(display.width)))
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              let i = displays.firstIndex(where: { $0.id == display.displayID }) else { return }
        displays[i].thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Shares the selected display, or only the main window of the app `windowOf` (a bundle id).
    func start(windowOf bundleID: String? = nil) async -> Bool {
        if isSharing { await stop() }
        error = nil
        var pending: StreamEncoder?
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let filter: SCContentFilter
            let aspect: Double
            if let bundleID {
                // the app's biggest normal window, captured even when other windows cover it
                guard let window = content.windows
                    .filter({ $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 && $0.frame.width > 200 })
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                    error = "Open the app's window first."
                    return false
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                aspect = Double(window.frame.height / window.frame.width)
            } else {
                guard let display = content.displays.first(where: { $0.displayID == selectedID }) ?? content.displays.first else {
                    error = "No display found."
                    return false
                }
                let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: hideThisApp ? mine : [], exceptingWindows: [])
                aspect = Double(display.height) / Double(display.width)
            }

            let width = quality.width
            let height = Int(Double(width) * aspect) & ~1
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(quality.fps))
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.showsCursor = showCursor
            config.queueDepth = 4
            config.capturesAudio = playSound
            config.sampleRate = StreamEncoder.sampleRate
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            SegmentHub.shared.start()
            let encoder = try StreamEncoder(width: width, height: height, fps: quality.fps, bitrate: quality.bitrate) { data, type in
                switch type {
                case .initialization: SegmentHub.shared.setInit(data)
                case .separable: SegmentHub.shared.add(data)
                @unknown default: break
                }
            }
            pending = encoder
            let capture = CaptureOutput(encoder: encoder)
            let s = SCStream(filter: filter, configuration: config, delegate: nil)
            try s.addStreamOutput(capture, type: .screen, sampleHandlerQueue: encoder.queue)
            if playSound {
                try s.addStreamOutput(capture, type: .audio, sampleHandlerQueue: encoder.queue)
            }
            encoder.begin()
            try await s.startCapture()
            stream = s
            self.encoder = encoder
            self.capture = capture
            isSharing = true
            // The sound now plays on the TV; silence the Mac so it isn't heard twice, 3 s apart.
            if playSound && muteMac { macWasMuted = MacSpeakers.setMuted(true) }
            startStats()
            return true
        } catch {
            pending?.end()
            SegmentHub.shared.stop()
            permissionDenied = (error as NSError).domain == SCStreamErrorDomain
            self.error = permissionDenied
                ? "Allow screen recording for Ambient Control in System Settings, then reopen the app."
                : error.localizedDescription
            return false
        }
    }

    func stop() async {
        statsTask?.cancel()
        if let s = stream { try? await s.stopCapture() }
        encoder?.end()
        stream = nil
        encoder = nil
        capture = nil
        SegmentHub.shared.stop()
        if let was = macWasMuted { _ = MacSpeakers.setMuted(was) }
        macWasMuted = nil
        isSharing = false
        fps = 0
        kbps = 0
        targetKbps = 0
        linkKbps = 0
    }

    /// Once a second: show what is being sent, and steer the bitrate (Auto quality).
    ///
    /// The TV reports how long each segment took to download. A segment should arrive in well
    /// under its own length, so the stream aims for about half the measured Wi-Fi speed, drops
    /// quickly when the TV had to skip ahead, and climbs back slowly once the Wi-Fi recovers.
    private func startStats() {
        statsTask?.cancel()
        let ceiling = quality.bitrate
        let floor = 1_500_000
        var target = ceiling
        var lastJumps = 0
        var calmSeconds = 0
        targetKbps = target / 1000
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let s = SegmentHub.shared.takeStats()
                fps = s.segments > 0 ? quality.fps : 0
                kbps = s.bytes * 8 / 1000
                let link = SegmentHub.shared.link
                linkKbps = link.bps / 1000
                var next = target
                if link.jumps > lastJumps {
                    next = Int(Double(target) * 0.6)
                    calmSeconds = 0
                } else if link.bps > 0, Double(target) > Double(link.bps) * 0.55 {
                    next = Int(Double(link.bps) * 0.5)
                    calmSeconds = 0
                } else {
                    calmSeconds += 1
                    if calmSeconds >= 6 { next = Int(Double(target) * 1.15); calmSeconds = 0 }
                }
                lastJumps = link.jumps
                next = min(ceiling, max(floor, next))
                if abs(next - target) * 20 > target {
                    target = next
                    encoder?.setBitrate(target)
                }
                targetKbps = target / 1000
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Hands ScreenCaptureKit's frames and sound to the encoder (on the encoder's queue).
private final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let encoder: StreamEncoder
    init(encoder: StreamEncoder) { self.encoder = encoder }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete,
                  let pixels = sampleBuffer.imageBuffer else { return }
            encoder.push(video: pixels)
        case .audio:
            encoder.push(audio: sampleBuffer)
        default:
            break
        }
    }
}

/// The mute switch of the Mac's current speakers. ScreenCaptureKit takes each app's sound before
/// it reaches the speakers, so muting them does not silence what is sent to the TV.
enum MacSpeakers {
    /// Sets mute and returns the previous state, or nil if the output device has no mute switch.
    static func setMuted(_ muted: Bool) -> Bool? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultOut = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOut, 0, nil, &size, &device) == noErr
        else { return nil }
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &mute) else { return nil }
        var old: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &old)
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &mute, 0, nil, size, &value)
        return old != 0
    }
}
