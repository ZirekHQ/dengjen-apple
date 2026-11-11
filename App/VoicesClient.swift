import Foundation
import LibdengjenVoices

/// A failed `libdengjen-voices` call.
struct VoicesError: LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? { message }
    var isCancelled: Bool { code == VOICES_ERR_CANCELLED }
}

/// Holds the Swift closure that `libdengjenVoicesInstall` reports progress to.
private final class ProgressBox {
    let report: (UInt64, UInt64) -> Void

    init(_ report: @escaping (UInt64, UInt64) -> Void) {
        self.report = report
    }
}

/// The `libdengjen-voices` C API: catalogue, verified downloads and removal.
///
/// Every call but `cancel()` blocks, so callers run them off the main thread, one at a time.
/// This file imports only `LibdengjenVoices`; `Libdengjen` defines its own `ExternError`.
final class VoicesClient: @unchecked Sendable {
    static let catalogueURL = "https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json"
    static let filesBaseURL = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
    static let modelType = "piper"

    private let handle: OpaquePointer

    init(voicesDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: voicesDirectory, withIntermediateDirectories: true)
        var error = LibdengjenVoices.ExternError()
        let opened: OpaquePointer? = voicesDirectory.path.withCString { directory in
            Self.modelType.withCString { modelType in
                Self.catalogueURL.withCString { catalogue in
                    Self.filesBaseURL.withCString { files in
                        var config = VoicesConfig()
                        config.struct_size = UInt32(MemoryLayout<VoicesConfig>.stride)
                        config.voices_dir = directory
                        config.model_type = modelType
                        config.catalogue_url = catalogue
                        config.files_base_url = files
                        return libdengjenVoicesOpen(&config, &error)
                    }
                }
            }
        }
        try Self.check(&error)
        guard let opened else {
            throw VoicesError(code: VOICES_ERR_INVALID_CONFIGURATION, message: "Could not open the voice manager")
        }
        handle = opened
    }

    deinit {
        libdengjenVoicesClose(handle)
    }

    /// Downloads the catalogue; falls back to the cached copy when offline.
    func refreshCatalogue() throws {
        var error = LibdengjenVoices.ExternError()
        libdengjenVoicesFetchCatalogue(handle, &error)
        do {
            try Self.check(&error)
        } catch let fetchError {
            libdengjenVoicesLoadCachedCatalogue(handle, &error)
            guard (try? Self.check(&error)) != nil else { throw fetchError }
        }
    }

    /// The JSON of the catalogue voices, optionally only those of one language (`ku` matches `ku_TR`).
    func list(language: String?) throws -> Data {
        var error = LibdengjenVoices.ExternError()
        let json: UnsafeMutablePointer<CChar>?
        if let language {
            json = language.withCString { libdengjenVoicesListJson(handle, $0, &error) }
        } else {
            json = libdengjenVoicesListJson(handle, nil, &error)
        }
        return try Self.takeString(json, &error)
    }

    /// The JSON of the installed voices.
    func installed() throws -> Data {
        var error = LibdengjenVoices.ExternError()
        let json = libdengjenVoicesInstalledJson(handle, &error)
        return try Self.takeString(json, &error)
    }

    func install(_ key: String, progress: @escaping (UInt64, UInt64) -> Void) throws {
        let box = Unmanaged.passRetained(ProgressBox(progress))
        defer { box.release() }
        var error = LibdengjenVoices.ExternError()
        key.withCString { key in
            libdengjenVoicesInstall(
                handle, key,
                { done, total, userData in
                    guard let userData else { return }
                    Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
                        .report(done, total)
                }, box.toOpaque(), &error)
        }
        try Self.check(&error)
    }

    /// Stops the install in flight, from any thread.
    func cancel() {
        libdengjenVoicesCancel(handle)
    }

    func remove(_ key: String) throws {
        var error = LibdengjenVoices.ExternError()
        key.withCString { libdengjenVoicesRemove(handle, $0, &error) }
        try Self.check(&error)
    }

    private static func takeString(
        _ pointer: UnsafeMutablePointer<CChar>?, _ error: inout LibdengjenVoices.ExternError
    ) throws -> Data {
        try check(&error)
        guard let pointer else { return Data("[]".utf8) }
        defer { libdengjenVoicesFreeString(pointer) }
        return Data(String(cString: pointer).utf8)
    }

    private static func check(_ error: inout LibdengjenVoices.ExternError) throws {
        guard error.code != 0 else { return }
        let code = error.code
        let message = error.message.map { String(cString: $0) } ?? "Voice manager error \(code)"
        if let pointer = error.message {
            libdengjenVoicesFreeString(pointer)
        }
        error = LibdengjenVoices.ExternError()
        throw VoicesError(code: code, message: message)
    }
}
