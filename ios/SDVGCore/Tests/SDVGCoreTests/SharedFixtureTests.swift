import Foundation
import XCTest

@testable import SDVGCore

/// The same shared/ vectors and fixtures the backend and the web client run.
let sharedDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../../../shared").standardized

func loadShared(_ path: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: sharedDir.appendingPathComponent(path)))
}

func sharedFiles(_ dir: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: sharedDir.appendingPathComponent(dir).path)
        .filter { $0.hasSuffix(".json") }.sorted()
}

final class SharedFixtureTests: XCTestCase {
    func testHLCVectors() throws {
        let vectors = try loadShared("vectors/hlc.json")
        for c in vectors["cases"]!.array! {
            let pt = Box(0)
            let initial = c["initial"]?.object
            let clock = HybridClock(
                nodeID: c["node_id"]!.string!, nowMs: { Int64(pt.value) },
                ms: Int64(initial?["l"]?.int ?? 0), counter: initial?["c"]?.int ?? 0)
            for step in c["steps"]!.array! {
                pt.value = step["pt"]!.int!
                let got = step["op"] == "now" ? clock.now() : clock.receive(step["remote"]!.string!)
                XCTAssertEqual(got, step["expect"]!.string!, c["name"]!.string!)
            }
        }
        let ordering = vectors["ordering"]!.array!.map { $0.string! }
        XCTAssertEqual(ordering.sorted(), ordering)
    }

    func testClockResumesPastPersistedTimestamp() {
        let clock = HybridClock(nodeID: "0123456789abcdef", resumingFrom: "1790000005000-0003-0123456789abcdef", nowMs: { 1 })
        XCTAssertEqual(clock.now(), "1790000005000-0004-0123456789abcdef")
    }

    func testDeterministicIDs() throws {
        let vectors = try loadShared("vectors/ids.json")
        XCTAssertEqual(IDs.namespace.uuidString.lowercased(), vectors["namespace"]!.string!)
        for c in vectors["cases"]!.array! {
            let parts = c["name"]!.string!.split(separator: ":").map(String.init)
            let got = parts[0] == "routine_check" ? IDs.routineCheck(parts[1], parts[2]) : IDs.taskMove(parts[1], parts[2])
            XCTAssertEqual(got, c["expect"]!.string!)
        }
    }

    func testNewIDsAreV7AndOrdered() {
        let a = IDs.new(now: Date(timeIntervalSince1970: 1_790_000_000))
        let b = IDs.new(now: Date(timeIntervalSince1970: 1_790_000_001))
        XCTAssertEqual(Array(a)[14], "7")
        XCTAssertLessThan(a, b)
    }

    func testMergeFixtures() throws {
        for file in try sharedFiles("sync-fixtures") {
            for c in try loadShared("sync-fixtures/\(file)")["cases"]!.array! {
                let initial = try changes(c["initial"]!)
                let list = try changes(c["changes"]!)
                let expected = try changes(c["expected"]!)
                let orders = c["order_independent"] == true ? permutations(list) : [list]
                for order in orders {
                    XCTAssertEqual(apply(initial + order), expected, "\(file): \(c["name"]!.string!)")
                }
            }
        }
    }

    private func changes(_ v: JSONValue) throws -> [Change] {
        try JSONDecoder().decode([Change].self, from: JSONEncoder().encode(v))
    }

    private func apply(_ changes: [Change]) -> [Change] {
        var rows: [String: Change] = [:]
        for ch in changes {
            let key = "\(ch.entity)\u{1}\(ch.id)"
            var row = rows[key] ?? Change(entity: ch.entity, id: ch.id, fields: [:], clocks: [:])
            mergeFields(&row.fields, &row.clocks, ch.fields, ch.clocks)
            rows[key] = row
        }
        return rows.values.sorted { ($0.entity, $0.id) < ($1.entity, $1.id) }
    }

    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[T]] in
            var rest = items
            let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
