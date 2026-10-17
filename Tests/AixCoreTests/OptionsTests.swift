import Testing
@testable import AixCore

@Suite struct OptionsTests {
    @Test func wordsBecomeThePrompt() throws {
        let o = try Options.parse(["find", "big", "files"])
        #expect(o.prompt == "find big files")
        #expect(!o.yes && !o.dryRun)
    }

    @Test func flagsAnywhere() throws {
        let o = try Options.parse(["-n", "show", "disk", "usage", "-y"])
        #expect(o.prompt == "show disk usage")
        #expect(o.dryRun && o.yes)
    }

    @Test func doubleDashEndsFlags() throws {
        let o = try Options.parse(["--", "-y", "means", "yes"])
        #expect(o.prompt == "-y means yes")
        #expect(!o.yes)
    }

    @Test func noWordsMeansAskInteractively() throws {
        let o = try Options.parse([])
        #expect(o.prompt.isEmpty && !o.help)
    }

    @Test func subcommands() throws {
        #expect(try Options.parse(["fix"]).mode == .fix)
        #expect(try Options.parse(["init", "zsh"]).mode == .initShell("zsh"))
        #expect(try Options.parse(["init"]).mode == .initShell("zsh"))
        #expect(try Options.parse(["explain", "tar", "-xzf", "a.tgz"]).mode == .explain("tar -xzf a.tgz"))
    }

    @Test func subcommandWordsInsideRequestsStayRequests() throws {
        #expect(try Options.parse(["fix", "the", "permissions"]).mode == .run)
        #expect(try Options.parse(["init", "a", "git", "repo"]).mode == .run)
        #expect(try Options.parse(["--", "fix"]).mode == .run)
    }

    @Test func printFlag() throws {
        let o = try Options.parse(["--print", "list", "files"])
        #expect(o.print && o.prompt == "list files")
    }

    @Test func rejectsUnknownFlags() {
        #expect(throws: OptionsError.unknownFlag("--bogus")) { try Options.parse(["--bogus", "x"]) }
    }
}
