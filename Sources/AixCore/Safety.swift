import Foundation

/// Catches obvious disasters and names what a command changes. Not a sandbox:
/// the confirmation prompt is the real gate.
public enum Safety {
    /// Why `command` must not run, or nil.
    public static func violation(in command: String, home: String) -> String? {
        for (pattern, reason) in textRules where command.range(of: pattern, options: .regularExpression) != nil {
            return reason
        }
        for words in Shell.commands(in: command) {
            if let reason = check(words, home: home) { return reason }
        }
        if let file = redirects(in: command).first(where: { $0.readFirst }) {
            return "reads and overwrites \(file.target) at the same time, which empties it"
        }
        return nil
    }

    /// What a command changes, e.g. "deletes logs", shown before confirming.
    public static func risks(in command: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
        var notes: [String] = []
        func add(_ note: String) { if !notes.contains(note) { notes.append(note) } }
        for words in Shell.commands(in: command) {
            let program = (words[0] as NSString).lastPathComponent
            let args = words.dropFirst()
            let operands = args.filter { !$0.hasPrefix("-") }
            switch program {
            case "mv": add("moves " + names(operands.dropLast(), or: "files"))
            case "rm", "rmdir", "shred", "unlink": add("deletes " + names(operands, or: "files"))
            case "find" where args.contains("-delete") || args.contains("rm"):
                let roots = args.prefix { !$0.hasPrefix("-") }.filter { $0 != "." && $0 != "./" }
                add(roots.isEmpty ? "deletes matching files in this folder" : "deletes matching files under " + names(roots, or: "."))
            case "sed" where args.contains { $0.hasPrefix("-i") }: add("edits files in place")
            case "kill", "killall", "pkill": add("stops processes")
            case "xargs" where args.contains { ["kill", "rm", "mv"].contains($0) }:
                add(args.contains("kill") ? "stops processes" : args.contains("rm") ? "deletes files" : "moves files")
            case "git" where args.first == "reset" && args.contains("--hard"),
                 "git" where args.first == "clean",
                 "git" where args.first == "restore",
                 "git" where args.first == "checkout" && args.contains("--"):
                add("discards git changes")
            case "git" where args.first == "push": add("pushes to the remote")
            case "brew" where ["install", "uninstall", "upgrade", "remove"].contains(args.first ?? ""):
                add("changes installed software")
            default: break
            }
        }
        for r in redirects(in: command) where fileExists(r.target) {
            add("overwrites \(r.target)")
        }
        return notes
    }

    static func names<C: Collection<String>>(_ items: C, or fallback: String) -> String {
        let list = Array(items)
        switch list.count {
        case 0: return fallback
        case 1...3: return list.joined(separator: ", ")
        default: return list.prefix(2).joined(separator: ", ") + " and \(list.count - 2) more"
        }
    }

    /// `> file` targets (not `>>`, `2>` or `&>`), and whether the same file is read earlier in that step.
    static func redirects(in command: String) -> [(target: String, readFirst: Bool)] {
        var found: [(String, Bool)] = []
        let steps = command.replacingOccurrences(of: "&&", with: ";").replacingOccurrences(of: "||", with: ";")
            .split(whereSeparator: { $0 == ";" || $0 == "\n" })
        for step in steps {
            let step = String(step)
            var searchFrom = step.startIndex
            while let m = step.range(of: #"(?<![>&0-9])>(?![>&])\s*[^\s>|&;]+"#, options: .regularExpression, range: searchFrom..<step.endIndex) {
                let target = step[m].dropFirst().trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                searchFrom = m.upperBound
                guard !target.hasPrefix("/dev/") else { continue }
                let before = step[..<m.lowerBound].split(whereSeparator: { " |<\t".contains($0) })
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
                found.append((target, before.contains(target)))
            }
        }
        return found
    }

    static let textRules: [(String, String)] = [
        (#"\|\s*(sudo\s+)?(sh|bash|zsh|fish|dash|ksh)\b"#, "pipes text into a shell"),
        (#":\s*\(\s*\)\s*\{"#, "looks like a fork bomb"),
        (#">\s*/dev/r?disk"#, "writes directly to a disk device"),
    ]

    static func check(_ words: [String], home: String) -> String? {
        guard let program = words.first.map({ ($0 as NSString).lastPathComponent }) else { return nil }
        let args = Array(words.dropFirst())
        switch program {
        case "sudo", "su", "doas":
            return "runs as root"
        case "dd" where args.contains { $0.hasPrefix("of=/dev/") }:
            return "writes raw data to a device"
        case _ where program.hasPrefix("mkfs") || program.hasPrefix("newfs"):
            return "formats a filesystem"
        case "fdisk", "gpt", "csrutil", "nvram":
            return "changes disks or firmware settings"
        case "diskutil" where args.contains { ["erase", "partition", "zero", "reformat", "secure"].contains(where: $0.lowercased().contains) }:
            return "erases or repartitions a disk"
        case "shutdown", "reboot", "halt":
            return "shuts down or restarts the Mac"
        case "rm":
            let recursive = args.contains { $0 == "--recursive" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && ($0.contains("r") || $0.contains("R"))) }
            let targets = args.filter { !$0.hasPrefix("-") }
            if recursive, let t = targets.first(where: { isCritical($0, home: home, includeCwd: true) }) {
                return "recursively deletes \(t)"
            }
        case "chmod", "chown", "chgrp":
            let recursive = args.contains { $0.hasPrefix("-") && $0.contains("R") }
            if recursive, let t = args.first(where: { isCritical($0, home: home, includeCwd: false) }) {
                return "recursively changes permissions on \(t)"
            }
        case "find":
            let deletes = args.contains("-delete") || args.contains { $0 == "rm" }
            if deletes, let t = args.prefix(while: { !$0.hasPrefix("-") }).first(where: { isCritical($0, home: home, includeCwd: false) }) {
                return "deletes files across \(t)"
            }
        default:
            break
        }
        return nil
    }

    static func isCritical(_ raw: String, home: String, includeCwd: Bool) -> Bool {
        var p = raw
        for v in ["${HOME}", "$HOME"] where p.hasPrefix(v) { p = "~" + p.dropFirst(v.count) }
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        if p.hasSuffix("/*") { p = String(p.dropLast(2)); if p.isEmpty { p = "/" } }
        let roots: Set<String> = ["/", "~", "/Users", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/opt", "/Volumes"]
        if roots.contains(p) { return true }
        return includeCwd && [".", "..", "*", ".*"].contains(p)
    }
}
