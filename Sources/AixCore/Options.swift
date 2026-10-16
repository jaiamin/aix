import Foundation

public enum ModelChoice: String, Sendable, CaseIterable {
    /// Private Cloud Compute when reachable, otherwise on-device.
    case auto
    /// On-device model only (offline, fastest to start, weakest).
    case local
    /// Apple's Private Cloud Compute model only (stronger, needs network, daily quota).
    case cloud
}

public struct Options: Equatable, Sendable {
    public var prompt = ""
    public var yes = false
    public var dryRun = false
    public var model = ModelChoice.auto
    public var help = false
    public var version = false

    public static let usage = """
    aix — turn a request into shell commands with Apple Intelligence

    Usage:
      aix [options] <request...>
      aix [options] -p "<request>"

    Options:
      -p, --prompt <text>  the request (or just type it after the options)
      -y, --yes            run without asking
      -n, --dry-run        show the commands, don't run them
      -m, --model <name>   auto | local | cloud  (default: $AIX_MODEL or auto)
      -h, --help           show this help
          --version        print the version

    Examples:
      aix find the 5 largest files here
      aix -n "count lines of Swift in the parent folder"
    """

    public static func parse(_ args: [String], env: [String: String]) throws(OptionsError) -> Options {
        var o = Options()
        if let m = env["AIX_MODEL"], !m.isEmpty {
            guard let choice = ModelChoice(rawValue: m) else { throw .badModel(m) }
            o.model = choice
        }
        var words: [String] = []
        var i = 0
        func value(for flag: String) throws(OptionsError) -> String {
            i += 1
            guard i < args.count else { throw .missingValue(flag) }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--":
                words += args[(i + 1)...]
                i = args.count
                continue
            case "-p", "--prompt": words.append(try value(for: a))
            case "-y", "--yes": o.yes = true
            case "-n", "--dry-run": o.dryRun = true
            case "-m", "--model":
                let m = try value(for: a)
                guard let choice = ModelChoice(rawValue: m) else { throw .badModel(m) }
                o.model = choice
            case "-h", "--help": o.help = true
            case "--version": o.version = true
            default:
                if a.hasPrefix("-") && a.count > 1 { throw .unknownFlag(a) }
                words.append(a)
            }
            i += 1
        }
        o.prompt = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if o.prompt.isEmpty && !o.version { o.help = true }
        return o
    }
}

public enum OptionsError: Error, Equatable, CustomStringConvertible {
    case unknownFlag(String)
    case missingValue(String)
    case badModel(String)

    public var description: String {
        switch self {
        case .unknownFlag(let f): "unknown option \(f) (use -- before a request that starts with -)"
        case .missingValue(let f): "\(f) needs a value"
        case .badModel(let m): "unknown model '\(m)'; use auto, local or cloud"
        }
    }
}
