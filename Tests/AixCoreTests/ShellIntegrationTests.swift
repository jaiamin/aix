import Foundation
import Testing
@testable import AixCore

@Suite struct ShellIntegrationTests {
    @Test func zshScriptParses() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("aix-\(UUID().uuidString).zsh")
        try ShellIntegration.zsh.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(capture(["/bin/zsh", "-n", file.path]).status == 0)
    }
}
