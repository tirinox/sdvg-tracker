import Foundation

/// Hybrid logical clock, see shared/README.md. Timestamps compare as plain strings.
public final class HybridClock: @unchecked Sendable {
    public static let maxCounter = 9999

    public let nodeID: String
    private let nowMs: @Sendable () -> Int64
    private var ms: Int64
    private var counter: Int
    private let lock = NSLock()

    public init(nodeID: String, nowMs: @escaping @Sendable () -> Int64 = HybridClock.wallMs, ms: Int64 = 0, counter: Int = 0) {
        precondition(nodeID.count == 16 && nodeID.allSatisfy(\.isHexDigit) && nodeID == nodeID.lowercased(), "Invalid node id")
        self.nodeID = nodeID
        self.nowMs = nowMs
        self.ms = ms
        self.counter = counter
    }

    /// Restores a clock that must never go below `last` (persisted across launches).
    public convenience init(nodeID: String, resumingFrom last: String?, nowMs: @escaping @Sendable () -> Int64 = HybridClock.wallMs) {
        if let last, let t = HLCTimestamp(last) {
            self.init(nodeID: nodeID, nowMs: nowMs, ms: t.ms, counter: t.counter)
        } else {
            self.init(nodeID: nodeID, nowMs: nowMs)
        }
    }

    @Sendable public static func wallMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    public static func randomNodeID() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Timestamp for a local event.
    public func now() -> String {
        lock.withLock {
            let pt = nowMs()
            if pt > ms {
                ms = pt
                counter = 0
            } else {
                counter += 1
            }
            return emit()
        }
    }

    /// Advance past a timestamp received from another node.
    @discardableResult
    public func receive(_ remote: String) -> String {
        guard let r = HLCTimestamp(remote) else { return now() }
        return lock.withLock {
            let pt = nowMs()
            let next = max(ms, r.ms, pt)
            if next == ms && next == r.ms { counter = max(counter, r.counter) + 1 }
            else if next == ms { counter += 1 }
            else if next == r.ms { counter = r.counter + 1 }
            else { counter = 0 }
            ms = next
            return emit()
        }
    }

    private func emit() -> String {
        if counter > Self.maxCounter {
            ms += 1
            counter = 0
        }
        return HLCTimestamp(ms: ms, counter: counter, nodeID: nodeID).description
    }
}

public struct HLCTimestamp: Hashable, Sendable, CustomStringConvertible {
    public var ms: Int64
    public var counter: Int
    public var nodeID: String

    public init(ms: Int64, counter: Int, nodeID: String) {
        self.ms = ms
        self.counter = counter
        self.nodeID = nodeID
    }

    public init?(_ value: String) {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 13, parts[1].count == 4, parts[2].count == 16,
              let ms = Int64(parts[0]), let counter = Int(parts[1]) else { return nil }
        self.init(ms: ms, counter: counter, nodeID: String(parts[2]))
    }

    public var description: String {
        String(format: "%013lld-%04d-", ms, counter) + nodeID
    }
}
