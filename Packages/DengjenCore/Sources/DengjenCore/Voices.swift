import Foundation

/// A voice in the catalogue, as `libdengjenVoicesListJson` returns it.
public struct CatalogueVoice: Codable, Equatable, Identifiable, Sendable {
    public struct Language: Codable, Equatable, Sendable {
        public var code: String
        public var family: String
        public var nameEnglish: String
        public var nameNative: String
        public var countryEnglish: String

        enum CodingKeys: String, CodingKey {
            case code, family
            case nameEnglish = "name_english"
            case nameNative = "name_native"
            case countryEnglish = "country_english"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            family = try container.decodeIfPresent(String.self, forKey: .family) ?? ""
            nameEnglish = try container.decodeIfPresent(String.self, forKey: .nameEnglish) ?? ""
            nameNative = try container.decodeIfPresent(String.self, forKey: .nameNative) ?? ""
            countryEnglish =
                try container.decodeIfPresent(String.self, forKey: .countryEnglish) ?? ""
        }
    }

    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var size: UInt64
    }

    public var key: String
    public var name: String
    public var language: Language
    public var quality: String
    public var files: [File]

    public var id: String { key }

    /// The download size of all the voice's files, in bytes.
    public var size: UInt64 { files.reduce(0) { $0 + $1.size } }

    /// A name for people, such as "Berfin Renas (medium)".
    public var displayName: String {
        quality.isEmpty
            ? VoiceNaming.speakerName(name)
            : "\(VoiceNaming.speakerName(name)) (\(quality))"
    }

    public static func decodeList(_ json: Data) throws -> [CatalogueVoice] {
        try JSONDecoder().decode([CatalogueVoice].self, from: json)
    }
}

/// An installed voice, as `libdengjenVoicesInstalledJson` returns it.
public struct InstalledVoice: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var language: String

    enum CodingKeys: String, CodingKey {
        case key, name, language
    }

    public init(key: String, name: String, language: String) {
        self.key = key
        self.name = name
        self.language = language
    }

    public static func decodeList(_ json: Data) throws -> [InstalledVoice] {
        try JSONDecoder().decode([InstalledVoice].self, from: json)
    }
}

/// A voice the speech extension offers to the system. The host app writes the list into the App
/// Group; the extension reads it in `speechVoices`.
public struct SharedVoice: Codable, Equatable, Sendable {
    /// The system-wide identifier, `io.github.zirekhq.dengjen.<key>`.
    public var identifier: String
    /// The voice manager's key, e.g. `ku_TR-berfin_renas-medium`.
    public var key: String
    public var name: String
    /// A BCP 47 tag, e.g. `ku-TR`.
    public var language: String
    /// The voice's directory, relative to the App Group container.
    public var directory: String

    public static let identifierPrefix = "io.github.zirekhq.dengjen."

    public init(identifier: String, key: String, name: String, language: String, directory: String)
    {
        self.identifier = identifier
        self.key = key
        self.name = name
        self.language = language
        self.directory = directory
    }

    /// The shared entry for an installed voice. `voicesDirectory` is the voice manager's root,
    /// relative to the App Group container.
    public init(installed: InstalledVoice, voicesDirectory: String, modelType: String = "piper") {
        self.init(
            identifier: Self.identifierPrefix + installed.key,
            key: installed.key,
            name: "Dengjen " + VoiceNaming.speakerName(installed.name),
            language: VoiceNaming.bcp47(installed.language),
            directory: [voicesDirectory, modelType, installed.key].joined(separator: "/")
        )
    }
}

public enum VoiceList {
    /// The list's file name inside the App Group container.
    public static let fileName = "speech-voices.json"

    /// The voices in the list at `url`; a missing or unreadable list is empty.
    public static func load(from url: URL) -> [SharedVoice] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SharedVoice].self, from: data)) ?? []
    }

    public static func save(_ voices: [SharedVoice], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(voices).write(to: url, options: .atomic)
    }

    /// The Piper config (`*.onnx.json`) inside a voice directory.
    public static func configFile(in directory: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().first { $0.hasSuffix(".onnx.json") }
            .map { directory.appendingPathComponent($0) }
    }
}

public enum VoiceNaming {
    /// `berfin_renas` becomes `Berfin Renas`.
    public static func speakerName(_ name: String) -> String {
        name.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// `ku_TR` becomes `ku-TR`.
    public static func bcp47(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-")
    }
}
