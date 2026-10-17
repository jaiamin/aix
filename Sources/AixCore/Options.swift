import Foundation

public struct Options: Equatable, Sendable {
    public var prompt = ""
    public var yes = false
    public var dryRun = false
    public var help = false
    public var version = false

    public static let usage = """
    aix: describe what you want, get the shell command.

    Usage:
      aix <request>     e.g. aix find the 5 largest files here
      aix               ask for the request (no quoting needed)

    Options:
      -n, --dry-run     show the command, don't run it
      -y, --yes         run without asking
      -h, --help        show this help
      -v, --version     show the version

    At the prompt: y runs, r refines, c copies, any other key cancels.
    """

    public static func parse(_ args: [String]) throws(OptionsError) -> Options {
        var o = Options()
        var words: [String] = []
        var flagsDone = false
        for a in args {
            if flagsDone || !a.hasPrefix("-") || a == "-" {
                words.append(a)
                continue
            }
            switch a {
            case "--": flagsDone = true
            case "-y", "--yes": o.yes = true
            case "-n", "--dry-run": o.dryRun = true
            case "-h", "--help": o.help = true
            case "-v", "--version": o.version = true
            default: throw .unknownFlag(a)
            }
        }
        o.prompt = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
