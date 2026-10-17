import Testing
@testable import AixCore

@Suite struct PromptTests {
    let env = Environment(osVersion: "27.0", shell: "/bin/zsh", cwd: "/Users/me/proj", home: "/Users/me",
                          entries: (1...70).map { "f\($0)" }, gitBranch: "main", tools: ["git", "jq"])

    @Test func instructionsCarryTheEnvironment() {
        let s = Prompt.instructions(for: env)
        #expect(s.contains("named proj"))
        #expect(!s.contains("/Users/me"))  // absolute paths tempt the model to invent more
        #expect(s.contains("Shell: zsh"))
        #expect(s.contains("on branch main"))
        #expect(s.contains("installed: git, jq"))
        #expect(s.contains("f60") && !s.contains("f61") && s.contains("(+10 more)"))
    }

    @Test func quotesNamesWithSpaces() {
        var e = env
        e.entries = ["My File.txt", "docs/"]
        #expect(Prompt.instructions(for: e).contains("Files here: \"My File.txt\"  docs/"))
    }

    @Test func cleansMarkdownAroundCommands() {
        #expect(Prompt.clean("`ls -la`") == "ls -la")
        #expect(Prompt.clean("$ ls") == "ls")
        #expect(Prompt.clean("```sh\nls\n```") == "ls")
        #expect(Prompt.clean("  echo `date`  ") == "echo `date`")
    }

    @Test func stripsJSONResidueButKeepsRealBrackets() {
        // The model sometimes "closes" a command with the code token '] and derails the JSON.
        #expect(Prompt.clean("find . -type f -name '*.py']], ") == "find . -type f -name '*.py'")
        #expect(Prompt.clean("ls'], \"") == "ls'")
        #expect(Prompt.clean("[[ -f x ]] && echo y") == "[[ -f x ]] && echo y")
        #expect(Prompt.clean("grep -oE '[[:alpha:]]+' f") == "grep -oE '[[:alpha:]]+' f")
        #expect(Prompt.clean("ls [abc]") == "ls [abc]")
    }
}

@Suite struct ExampleSelectionTests {
    @Test func picksRelatedExamplesFirst() {
        let text = Prompt.examples(for: "show the last commits in git", count: 3)
        #expect(text.contains("last 10 commits"))
        #expect(text.components(separatedBy: "Request:").count - 1 == 4)  // 3 picked + the refusal
        #expect(text.contains("wipe my disk"))
    }

    @Test func includesQuestionsWithAnswers() {
        let text = Prompt.examples(for: "what does chmod 755 mean", count: 2)
        #expect(text.contains("Explanation: The owner can read"))
    }

    @Test func prefersRelatedPersonalHistory() {
        let mine = [History.Entry(request: "deploy the site", commands: ["make deploy"]),
                    History.Entry(request: "battery level", commands: ["pmset -g batt | tail -1"])]
        let text = Prompt.examples(for: "show battery level", personal: mine, count: 1)
        #expect(text.contains("pmset -g batt | tail -1"))
        #expect(!text.contains("make deploy"))
    }

    @Test func pluralsMatchSingulars() {
        #expect(Prompt.words("Commits processes") == Prompt.words("commit process"))
    }
}
