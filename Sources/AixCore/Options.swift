import Foundation

public struct Options: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case run
        case fix
        case explain(String)
        case initShell(String)
    }

    public var mode = Mode.run
    public var prompt = ""
    public var yes = false
    public var dryRun = false
    public var print = false
    public var help = false
    public var version = false

    public static let usage = """
    aix: describe what you want, get the shell command.

    Usage:
      aix <request>         e.g. aix find the 5 largest files here
      aix                   type the request (no quoting needed)
      aix explain <cmd>     explain a command
      aix fix               fix your last failed command (needs shell integration)
      aix init zsh          shell integration: add  eval "$(aix init zsh)"  to ~/.zshrc,
                            then press Ctrl-G to turn the text on your prompt into a command

    Options:
      -n, --dry-run         show the command, don't run it
      -y, --yes             run without asking
          --print           print only the command (used by the shell integration)
      -h, --help            show this help
      -v, --version         show the version

    At the prompt: y runs, r refines, c copies, any other key cancels.
    With shell integration, e puts the command on your prompt to edit.
    """

    public static func parse(_ args: [String]) throws(OptionsError) -> Options {
        var o = Options()
        var words: [String] = []
        var afterDashes = false
        var subcommandAllowed = true
        var rest = args[...]
        while let a = rest.popFirst() {
            if afterDashes || !a.hasPrefix("-") || a == "-" {
                if words.isEmpty { subcommandAllowed = !afterDashes }
                words.append(a)
                // `explain` takes the rest verbatim, flags included: aix explain tar -xzf a.tgz
                if subcommandAllowed && words == ["explain"] { words += rest; break }
                continue
            }
            switch a {
            case "--": afterDashes = true
            case "-y", "--yes": o.yes = true
            case "-n", "--dry-run": o.dryRun = true
            case "--print": o.print = true
            case "-h", "--help": o.help = true
            case "-v", "--version": o.version = true
            default: throw .unknownFlag(a)
            }
        }
        switch (subcommandAllowed ? words.first : nil, words.count) {
        case ("fix", 1): o.mode = .fix
        case ("init", 1): o.mode = .initShell("zsh")
        case ("init", 2): o.mode = .initShell(words[1])
        case ("explain", 2...): o.mode = .explain(words.dropFirst().joined(separator: " "))
        default: o.prompt = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return o
    }
}

public enum OptionsError: Error, Equatable, CustomStringConvertible {
    case unknownFlag(String)

    public var description: String {
        switch self {
        case .unknownFlag(let f): "unknown option \(f) (put -- before a request that starts with -)"
        }
    }
}
