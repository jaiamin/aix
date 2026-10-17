import Testing
@testable import AixCore

/// Guards the example library, since the model copies examples closely.
@Suite struct ExampleLibraryTests {
    @Test func everyExampleParses() {
        for example in library where !example.commands.isEmpty {
            let script = example.commands.joined(separator: "\n")
            #expect(capture(["/bin/zsh", "-n", "-c", script]).status == 0, "\(example.request): \(script)")
        }
    }

    @Test func examplesOnlyUseProgramsFromMacOS() {
        let programs = Set(library.flatMap { $0.commands.flatMap(Shell.programs(in:)) })
        let optional = Set(Environment.knownTools)  // the prompt only offers these when installed
        let missing = programs.subtracting(installed(Array(programs), shell: "/bin/zsh")).subtracting(optional)
        #expect(missing.isEmpty, "not on macOS: \(missing.sorted())")
    }

    @Test func examplesHaveNoBackslashes() {
        // The model must escape them in its JSON output and often derails.
        for example in library { #expect(!example.commands.joined().contains("\\"), "\(example.request)") }
    }
}
