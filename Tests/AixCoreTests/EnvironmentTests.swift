import Foundation
import Testing
@testable import AixCore

@Suite struct EnvironmentTests {
    @Test func listsTwoLevelsAndSkipsHeavyFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aix-tree-\(UUID().uuidString)").path
        for dir in ["a/b/c", ".git/objects", "node_modules/x"] {
            try FileManager.default.createDirectory(atPath: root + "/" + dir, withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: root + "/a/file.txt", contents: nil)
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(Environment.tree(root, depth: 2) == [".git/", "a/", "a/b/", "a/file.txt", "node_modules/"])
        #expect(Environment.tree(root, depth: 1) == [".git/", "a/", "node_modules/"])
    }

    @Test func unsupportedShellsFallBackToZsh() {
        #expect(Environment.runnableShell(from: "/opt/homebrew/bin/fish") == "/bin/zsh")
        #expect(Environment.runnableShell(from: "/bin/bash") == "/bin/bash")
        #expect(Environment.runnableShell(from: nil) == "/bin/zsh")
    }
}
