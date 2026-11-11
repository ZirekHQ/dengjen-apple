import Foundation

/// The App Group the host app and the speech extension share. The host installs voices into it
/// and writes the voice list; the extension reads both.
public enum AppGroup {
    /// The Info.plist key that holds the group identifier, which includes the team prefix.
    public static let infoKey = "DengjenAppGroup"
    /// The voice manager's root, relative to the container.
    public static let voicesDirectory = "voices"

    /// The shared container, or nil when the build has no App Group (an unsigned build).
    public static func containerURL(bundle: Bundle = .main) -> URL? {
        guard let identifier = bundle.object(forInfoDictionaryKey: infoKey) as? String,
            !identifier.isEmpty, !identifier.hasPrefix(".")
        else { return nil }
        #if canImport(Darwin)
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    public static func voiceListURL(in container: URL) -> URL {
        container.appendingPathComponent(VoiceList.fileName)
    }
}
