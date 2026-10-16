import Foundation

/// A last-resort deny list. It catches the obvious catastrophes a small model can produce; it is
/// NOT a sandbox and is easy to get around on purpose. The confirmation prompt is the real gate.
public enum Safety {
    /// Returns why `command` must not run, or nil if nothing obviously catastrophic was found.
    public static func violation(in command: String, home: String) -> String? {
        for (pattern, reason) in textRules where command.range(of: pattern, options: .regularExpression) != nil {
            return reason
        }
        for words in Shell.commands(in: command) {
            if let reason = check(words, home: home) { return reason }
        }
        return nil
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

    /// Paths whose wholesale deletion or permission change would wreck the system or home folder.
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
