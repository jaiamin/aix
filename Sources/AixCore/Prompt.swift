import Foundation

/// Facts about the user's machine that the model can't know on its own.
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

    /// Optional tools worth telling the model about when they're installed.
    static let knownTools = ["git", "brew", "python3", "node", "docker", "ffmpeg", "magick", "jq", "rg", "fd", "gh", "tree", "wget", "yt-dlp", "pandoc"]

    /// Shells that understand `-c`, `-n` and `set -e` the same way. Anything else (fish, nu…) runs zsh.
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
            // In the home folder, stay at the top level: looking inside Desktop, Documents
            // or Downloads makes macOS show privacy prompts.
            entries: tree(cwd, depth: cwd == fm.homeDirectoryForCurrentUser.path ? 1 : 2),
            gitBranch: git.status == 0 ? git.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            tools: installed.stdout.split(separator: "\n").map(String.init)
        )
    }

    /// Paths two levels deep ("docs/", "docs/readme.md"), so the model sees where files really are.
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

    public static func instructions(for env: Environment, request: String = "") -> String {
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
        - Return no commands only if the request would wreck the system or the user's data, or isn't a computer task. Say why.

        EXAMPLES (from other Macs; take names and numbers from the request and the file list, never from these)
        \(examples(for: request))
        """
    }

    static let stopWords: Set<String> = ["a", "an", "the", "in", "of", "to", "and", "or", "my", "me", "i", "is", "it", "this", "that", "here", "all", "every", "each", "for", "with", "on", "what", "show", "list", "find", "get", "how", "do", "can", "you", "please", "files", "file", "folder"]

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { w -> String in
            // Crude plural stripping: processes → process, libraries → library, files → file.
            if w.hasSuffix("sses") { return String(w.dropLast(2)) }
            if w.count > 4 && w.hasSuffix("ies") { return w.dropLast(3) + "y" }
            if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
            return String(w)
        }.map { synonyms[$0] ?? $0 }.filter { !stopWords.contains($0) })
    }

    /// The examples most related to the request (by shared words), plus one refusal. Fewer,
    /// relevant examples distract a small model less than all of them, and keep the prompt short.
    static func examples(for request: String, count: Int = 10) -> String {
        let wanted = words(request)
        let ranked = library.enumerated()
            .filter { !$0.element.commands.isEmpty }
            .map { (index: $0.offset, example: $0.element, score: words($0.element.request).intersection(wanted).count) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        let picked = ranked.prefix(count).sorted { $0.index < $1.index }.map(\.example) + [library.last!]
        return picked.map { ex in
            "Request: \(ex.request)\nCommands:\n" + (ex.commands.isEmpty ? "  (none; the explanation says why)" : ex.commands.map { "  " + $0 }.joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }

    public static func request(_ text: String) -> String {
        "Request: \(text)"
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

    /// Small models sometimes wrap a command in backticks or prefix it with a prompt sign.
    public static func clean(_ command: String) -> String {
        var c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("```") {
            c = c.split(separator: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        while c.hasPrefix("`") && c.hasSuffix("`") && c.count > 1 { c = String(c.dropFirst().dropLast()) }
        if c.hasPrefix("$ ") { c.removeFirst(2) }
        // Residue like `']], "` from a derailed JSON array: drop trailing ] , " and spaces
        // while there are more ] than [.
        func unbalanced(_ s: String) -> Bool { s.filter { $0 == "]" }.count > s.filter { $0 == "[" }.count }
        while unbalanced(c), let last = c.last, "]\", ".contains(last) { c.removeLast() }
        return c.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
