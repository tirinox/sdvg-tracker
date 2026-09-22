import CryptoKit
import Foundation

public enum IDs {
    static let urlNamespace = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!
    /// uuidv5(NAMESPACE_URL, "urn:sdvg-tracker:ids"), see shared/vectors/ids.json.
    public static let namespace = uuidv5("urn:sdvg-tracker:ids", namespace: urlNamespace)

    public static func routineCheck(_ routineID: String, _ date: LocalDate) -> String {
        uuidv5("routine_check:\(routineID):\(date)", namespace: namespace).uuidString.lowercased()
    }

    public static func taskMove(_ taskID: String, _ fromDate: LocalDate) -> String {
        uuidv5("task_move:\(taskID):\(fromDate)", namespace: namespace).uuidString.lowercased()
    }

    /// Time-ordered random id for new rows.
    public static func new(now: Date = Date()) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(now.timeIntervalSince1970 * 1000)
        for i in 0..<6 { bytes[i] = UInt8((ms >> (8 * (5 - UInt64(i)))) & 0xff) }
        for i in 6..<16 { bytes[i] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return uuid(bytes).uuidString.lowercased()
    }

    public static func uuidv5(_ name: String, namespace: UUID) -> UUID {
        let ns = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        var bytes = Array(Insecure.SHA1.hash(data: Data(ns + Array(name.utf8)))).prefix(16).map { $0 }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return uuid(bytes)
    }

    private static func uuid(_ b: [UInt8]) -> UUID {
        UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

extension UUID {
    var lowercased: String { uuidString.lowercased() }
}
