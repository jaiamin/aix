import Testing
@testable import AixCore

@Suite struct ProcessTests {
    @Test func findsInstalledProgramsAndBuiltins() {
        #expect(installed(["ls", "cd", "definitely-not-a-program-aix"], shell: "/bin/zsh") == ["ls", "cd"])
    }

    @Test func passesInput() {
        #expect(capture(["/usr/bin/wc", "-l"], input: "a\nb\n").stdout.trimmingCharacters(in: .whitespaces) == "2\n")
    }
}
