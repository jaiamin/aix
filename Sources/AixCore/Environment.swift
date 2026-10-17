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
        let found = installed(knownTools, shell: shell)
        let git = capture(["/usr/bin/git", "rev-parse", "--abbrev-ref", "HEAD"], in: cwd)
        return Environment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            shell: shell,
            cwd: cwd,
            home: fm.homeDirectoryForCurrentUser.path,
            // In ~, looking inside Desktop/Documents/Downloads triggers macOS privacy prompts.
            entries: tree(cwd, depth: cwd == fm.homeDirectoryForCurrentUser.path ? 1 : 2),
            gitBranch: git.status == 0 ? git.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            tools: knownTools.filter(found.contains)
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
