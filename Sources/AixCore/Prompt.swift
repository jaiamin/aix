import Foundation

/// What the model needs to know about the Mac.
public struct Environment: Sendable {
    public var osVersion: String
    public var shell: String
    public var cwd: String
    public var home: String
    public var entries: [String]
    public var gitBranch: String?
    public var tools: [String]

    public init(osVersion: String, shell: String, cwd: String, home: String, entries: [String], gitBranch: String? = nil, tools: [String] = []) {
        self.osVersion = osVersion
        self.shell = shell
        self.cwd = cwd
        self.home = home
        self.entries = entries
        self.gitBranch = gitBranch
        self.tools = tools
    }

    static let knownTools = ["git", "brew", "python3", "node", "docker", "ffmpeg", "magick", "jq", "rg", "fd", "gh", "tree", "wget", "yt-dlp", "pandoc"]

    /// fish, nu etc. don't take POSIX syntax, so they get zsh.
    public static func runnableShell(from env: String?) -> String {
        guard let env, ["zsh", "bash", "sh", "ksh", "dash"].contains((env as NSString).lastPathComponent) else { return "/bin/zsh" }
        return env
    }

    public static func current(shell: String) -> Environment {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let installed = capture([shell, "-c", #"for c; do command -v "$c" >/dev/null 2>&1 && echo "$c"; done"#, "aix"] + knownTools)
        let git = capture(["/usr/bin/git", "rev-parse", "--abbrev-ref", "HEAD"], in: cwd)
        return Environment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            shell: shell,
            cwd: cwd,
            home: fm.homeDirectoryForCurrentUser.path,
            // In ~, looking inside Desktop/Documents/Downloads triggers macOS privacy prompts.
            entries: tree(cwd, depth: cwd == fm.homeDirectoryForCurrentUser.path ? 1 : 2),
            gitBranch: git.status == 0 ? git.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            tools: installed.stdout.split(separator: "\n").map(String.init)
        )
    }

    /// Relative paths, e.g. "docs/", "docs/readme.md".
    static func tree(_ root: String, depth maxDepth: Int, limit: Int = 300) -> [String] {
        let fm = FileManager.default
        let skip: Set<String> = [".git", "node_modules", ".build", ".venv", "venv", "__pycache__", "Pods", "DerivedData", "Library"]
        var result: [String] = []
        func walk(_ rel: String, depth: Int) {
            let dir = rel.isEmpty ? root : (root as NSString).appendingPathComponent(rel)
            for name in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where result.count < limit {
                let path = rel.isEmpty ? name : rel + "/" + name
                var isDir: ObjCBool = false
                fm.fileExists(atPath: (root as NSString).appendingPathComponent(path), isDirectory: &isDir)
                result.append(isDir.boolValue ? path + "/" : path)
                if isDir.boolValue && depth < maxDepth && !skip.contains(name) { walk(path, depth: depth + 1) }
            }
        }
        walk("", depth: 1)
        return result
    }
}

public enum Prompt {
    static let maxEntries = 60

    public static func instructions(for env: Environment, request: String = "", personal: [History.Entry] = []) -> String {
        let shown = env.entries.prefix(maxEntries).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: "  ")
        let more = env.entries.count > maxEntries ? "  (+\(env.entries.count - maxEntries) more)" : ""
        let name = (env.cwd as NSString).lastPathComponent
        let git = env.gitBranch.map { "a git repository on branch \($0)" } ?? "not a git repository"
        return """
        You are a macOS terminal expert. Turn the user's request into shell commands that run on their Mac.

        THE MAC
        - macOS \(env.osVersion). Command-line tools are the BSD versions, not GNU/Linux.
        - Shell: \((env.shell as NSString).lastPathComponent). Commands run in order and stop at the first error.
        - Current folder: "." (named \(name)), \(git). "Here" means this folder.
        - Parent folder: ".."
        - Home folder: "~"
        - Extra tools installed: \(env.tools.isEmpty ? "none" : env.tools.joined(separator: ", "))
        - Files here: \(shown.isEmpty ? "(empty)" : shown)\(more)

        RULES
        - Do exactly what was asked, nothing more. For "how many", "how much", "which" or "top N", output only that answer, not raw data.
        - Search subfolders too (find . or grep -r) and skip .git.
        - Use paths exactly as they appear in the file list, relative to ".". NEVER invent file names, folders or extensions, and don't add ~ to them.
        - Commands must finish on their own: no tail -f, watch, or editors unless asked. Don't write output to a file unless asked.
        - Use macOS options only. NEVER use GNU-only options such as --max-depth, find -printf, stat -c, date -d, ps --sort, or sed -i without ''.
        - Use an extra tool only if it is listed as installed.
        - Usually one command. Stop when the request is done: no extra echo, cleanup, push or delete steps. Quote names that may contain spaces.
        - NEVER use sudo. Delete, move, kill or overwrite only what the user named.
        - Only when the user asks what a term, option or symbol means is the kind explainConcept: answer in the explanation in 1-3 sentences, with no commands. "How do I…", and anything about this Mac or its files ("what's my ip", "how much RAM"), is runOnThisMac.
        - Return no commands, and say why, if the request would wreck the system or the user's data, or has nothing to do with computers.

        EXAMPLES (from other Macs; take names and numbers from the request and the file list, never from these)
        \(examples(for: request, personal: personal))
        """
    }

    static let stopWords: Set<String> = ["a", "an", "the", "in", "of", "to", "and", "or", "my", "me", "i", "is", "it", "this", "that", "here", "all", "every", "each", "for", "with", "on", "what", "show", "list", "find", "get", "how", "do", "can", "you", "please", "files", "file", "folder"]

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { w -> String in
            if w.hasSuffix("sses") { return String(w.dropLast(2)) }
            if w.count > 4 && w.hasSuffix("ies") { return w.dropLast(3) + "y" }
            if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
            return String(w)
        }.map { synonyms[$0] ?? $0 }.filter { !stopWords.contains($0) })
    }

    struct Example {
        var request: String
        var commands: [String]
        var answer: String?
        var personal = false

        var text: String {
            let list = commands.isEmpty ? "  (none)" : commands.map { "  " + $0 }.joined(separator: "\n")
            let kind = answer != nil && commands.isEmpty && request != library.last!.request ? "explainConcept" : "runOnThisMac"
            return "Request: \(request)\nKind: \(kind)\nCommands:\n\(list)" + (answer.map { "\nExplanation: \($0)" } ?? "")
        }
    }

    /// The examples sharing the most words with the request, plus the refusal. The user's own
    /// past requests win ties, but only when they're related at all.
    static func examples(for request: String, personal: [History.Entry] = [], count: Int = 10) -> String {
        let wanted = words(request)
        let pool = personal.reversed().map { Example(request: $0.request, commands: $0.commands, personal: true) }
            + library.filter { !$0.commands.isEmpty }.map { Example(request: $0.request, commands: $0.commands) }
            + questions.map { Example(request: $0.request, commands: [], answer: $0.answer) }
        let ranked = pool.enumerated()
            .map { (index: $0.offset, example: $0.element, score: words($0.element.request).intersection(wanted).count) }
            .filter { !$0.example.personal || $0.score > 0 }
            .sorted { ($0.score, $0.example.personal ? 1 : 0, -$0.index) > ($1.score, $1.example.personal ? 1 : 0, -$1.index) }
        let refusal = Example(request: library.last!.request, commands: [], answer: "That would erase everything, so aix won't do it.")
        return (ranked.prefix(count).sorted { $0.index < $1.index }.map(\.example) + [refusal])
            .map(\.text).joined(separator: "\n\n")
    }

    public static func request(_ text: String) -> String {
        "Request: \(text)"
    }

    public static func fix(command: String, status: Int32) -> String {
        """
        This command failed with exit status \(status) (its error output isn't available):
          \(command)
        Return the corrected command. Keep what it was trying to do and change as little as possible. \
        Usual causes: a typo in a command or subcommand, a GNU/Linux-only option, a missing argument.
        Examples: "git comit -m x" -> "git commit -m x"; "du --max-depth=1" -> "du -d 1"; \
        "sl" -> "ls"; "grep foo" (no file) -> "grep -r foo ."
        """
    }

    public static let explainInstructions = """
        You explain macOS shell commands to someone at the terminal. Plain text, no markdown. \
        First one sentence on what the whole command does, then one short line per important part, \
        like "-x  extract files". At most 6 lines. Mention it if the command deletes or overwrites anything.
        """

    public static func explain(_ command: String) -> String {
        "Explain: \(command)"
    }

    public static func refine(_ change: String) -> String {
        """
        Change the commands: \(change)
        Return the complete updated commands.
        """
    }

    public static func repair(issues: [String]) -> String {
        """
        Those commands won't work on this Mac:
        \(issues.map { "- " + $0 }.joined(separator: "\n"))
        Return corrected commands for the same request.
        """
    }

    public static func failure(status: Int32, stderr: String) -> String {
        let tail = String(stderr.suffix(1500)).trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        The commands failed with exit status \(status).
        Error output:
        \(tail.isEmpty ? "(none)" : tail)
        Return corrected commands for the same request. Don't repeat what failed.
        """
    }

    /// Strips markdown, a "$ " prompt, and JSON residue like `']], "`.
    public static func clean(_ command: String) -> String {
        var c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("```") {
            c = c.split(separator: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        while c.hasPrefix("`") && c.hasSuffix("`") && c.count > 1 { c = String(c.dropFirst().dropLast()) }
        if c.hasPrefix("$ ") { c.removeFirst(2) }
        func unbalanced(_ s: String) -> Bool { s.filter { $0 == "]" }.count > s.filter { $0 == "[" }.count }
        while unbalanced(c), let last = c.last, "]\", ".contains(last) { c.removeLast() }
        return c.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
