import Foundation

/// Requests the user approved and that ran successfully, reused as examples so aix learns their habits.
/// Stored locally; delete the file to forget.
public struct History: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var request: String
        public var commands: [String]
        public init(request: String, commands: [String]) {
            self.request = request
            self.commands = commands
        }
    }

    public static let limit = 200
    /// $AIX_HISTORY, or ~/Library/Application Support/aix/history.json.
    public static func standard(env: [String: String]) -> History {
        if let path = env["AIX_HISTORY"], !path.isEmpty { return History(url: URL(fileURLWithPath: path)) }
        return History(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aix/history.json"))
    }

    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// Newest last; a repeated request replaces its older entry.
    public func record(_ entry: Entry) {
        var entries = load().filter { $0.request.lowercased() != entry.request.lowercased() }
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(Array(entries.suffix(Self.limit))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
