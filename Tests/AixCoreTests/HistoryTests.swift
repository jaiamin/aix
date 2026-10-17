import Foundation
import Testing
@testable import AixCore

@Suite struct HistoryTests {
    @Test func keepsNewestAndReplacesRepeats() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aix-history-\(UUID().uuidString)/h.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = History(url: url)
        #expect(h.load().isEmpty)
        h.record(.init(request: "list files", commands: ["ls"]))
        h.record(.init(request: "disk space", commands: ["df -h /"]))
        h.record(.init(request: "List files", commands: ["ls -la"]))
        #expect(h.load() == [.init(request: "disk space", commands: ["df -h /"]), .init(request: "List files", commands: ["ls -la"])])
    }
}
