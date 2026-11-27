import Foundation

/// Model layer: reads and writes `config.json`.
/// Default location: `~/Library/Application Support/Mac Stats/config.json`.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mac Stats", isDirectory: true)
    }

    public static var defaultURL: URL { supportDirectory.appendingPathComponent("config.json") }

    /// Loads the config. A missing or unreadable file gives the default config.
    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return .default }
        return (try? ConfigStore.decode(data)) ?? .default
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigStore.encode(config).write(to: url, options: .atomic)
    }

    public static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
