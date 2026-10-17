import Testing
@testable import AixCore

@Suite struct ShellWordsTests {
    @Test func extractsProgramsFromPipelinesAndLists() {
        #expect(Shell.programs(in: "du -sh * | sort -h | tail -5") == ["du", "sort", "tail"])
        #expect(Shell.programs(in: "cd src && FOO=1 make; echo done || true") == ["cd", "make", "echo", "true"])
    }

    @Test func ignoresQuotedOperatorsAndSubstitutions() {
        #expect(Shell.programs(in: "echo 'a | b' && grep \"x;y\" f") == ["echo", "grep"])
        #expect(Shell.programs(in: "$EDITOR file") == [])
    }

    @Test func arithmeticIsNotAProgram() {
        #expect(Shell.programs(in: "caffeinate -d -t $((45*60))") == ["caffeinate"])
        #expect(Shell.programs(in: "echo $((1+2)) && ls") == ["echo", "ls"])
        #expect(Shell.programs(in: "cd $(git rev-parse --show-toplevel) && ls") == ["cd", "ls"])
    }

    @Test func handlesSubshellsAndKeywords() {
        #expect(Shell.programs(in: "(cd x && ls)") == ["cd", "ls"])
        #expect(Shell.programs(in: "for f in *.txt; do wc -l \"$f\"; done") == ["wc"])
    }
}
