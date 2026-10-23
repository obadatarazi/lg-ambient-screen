import Foundation

/// Fragmented-MP4 pieces of the live screen share: one init segment plus a short rolling
/// window of media segments. The TV long-polls for the next segment and feeds it to its
/// hardware decoder (Media Source Extensions).
final class SegmentHub: @unchecked Sendable {
    static let shared = SegmentHub()

    private let lock = NSLock()
    private var open = false
    private var initSegment: Data?
    private var segments: [(seq: Int, data: Data)] = []
    private var seq = 0
    private var waiters: [Int: (after: Int, cb: (Data?, Int) -> Void)] = [:]
    private var nextWaiter = 0
    private var sentSegments = 0
    private var sentBytes = 0
    private var linkBps = 0.0
    private var linkJumps = 0

    func start() {
        lock.lock()
        open = true
        initSegment = nil
        segments = []
        linkBps = 0
        linkJumps = 0
        lock.unlock()
    }

    func stop() {
        lock.lock()
        open = false
        initSegment = nil
        segments = []
        let w = waiters.values
        waiters = [:]
        lock.unlock()
        w.forEach { $0.cb(nil, 0) }
    }

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
    var initData: Data? { lock.lock(); defer { lock.unlock() }; return initSegment }

    func setInit(_ data: Data) {
        lock.lock()
        initSegment = data
        lock.unlock()
    }

    func add(_ data: Data) {
        lock.lock()
        guard open else { lock.unlock(); return }
        seq += 1
        segments.append((seq, data))
        if segments.count > 12 { segments.removeFirst(segments.count - 12) }
        let ready = waiters
        waiters = [:]
        lock.unlock()
        for (_, w) in ready { deliver(after: w.after, w.cb) }
    }

    /// Calls back with the segment after `after`. A new viewer, or one more than ~3 s behind,
    /// jumps to the newest segment so it stays live; otherwise every segment is delivered in
    /// order, because a skipped one leaves a hole that makes the TV pause and refill.
    /// Calls back with nil data after `timeout` seconds if nothing new arrives (the viewer
    /// simply asks again).
    func next(after: Int, timeout: TimeInterval, _ cb: @escaping (Data?, Int) -> Void) {
        lock.lock()
        guard open else { lock.unlock(); cb(nil, -1); return }
        if let newest = segments.last, newest.seq > after {
            lock.unlock()
            deliver(after: after, cb)
            return
        }
        nextWaiter += 1
        let id = nextWaiter
        waiters[id] = (after, cb)
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let w = self.waiters.removeValue(forKey: id)
            self.lock.unlock()
            w?.cb(nil, 0)
        }
    }

    private func deliver(after: Int, _ cb: (Data?, Int) -> Void) {
        lock.lock()
        let pick: (seq: Int, data: Data)?
        if after > 0, let i = segments.firstIndex(where: { $0.seq == after + 1 }), segments.count - i <= 6 {
            pick = segments[i]
        } else {
            pick = segments.last
        }
        if let pick {
            sentSegments += 1
            sentBytes += pick.data.count
        }
        lock.unlock()
        cb(pick?.data, pick?.seq ?? 0)
    }

    /// What the TV reported with its last request: how long the previous segment took to
    /// download (from its first byte, so the long-poll wait is not counted) and how many times
    /// playback had to jump ahead. The speed is smoothed over the last few segments.
    func report(downloadMs: Int, bytes: Int, jumps: Int) {
        lock.lock()
        defer { lock.unlock() }
        linkJumps = max(linkJumps, jumps)
        // Tiny segments (a still screen) arrive in one burst and say nothing about the Wi-Fi.
        guard downloadMs > 0, bytes > 40_000 else { return }
        let bps = Double(bytes * 8) / (Double(downloadMs) / 1000)
        linkBps = linkBps == 0 ? bps : linkBps * 0.7 + bps * 0.3
    }

    var link: (bps: Int, jumps: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (Int(linkBps), linkJumps)
    }

    /// Segments and bytes delivered to viewers since the last call.
    func takeStats() -> (segments: Int, bytes: Int) {
        lock.lock()
        defer { sentSegments = 0; sentBytes = 0; lock.unlock() }
        return (sentSegments, sentBytes)
    }
}
