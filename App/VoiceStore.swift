import AVFoundation
import DengjenCore
import Foundation

/// The voice manager's state for the window: the catalogue, what is installed, and the download in
/// progress. Voice manager calls run on one background queue, in order.
@MainActor
final class VoiceStore: ObservableObject {
    @Published private(set) var voices: [CatalogueVoice] = []
    @Published private(set) var installedKeys: Set<String> = []
    @Published private(set) var installingKey: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var showAllLanguages = false {
        didSet { Task { await reload() } }
    }

    /// The language listed first and by default.
    static let primaryLanguage = "ku"

    private let queue = DispatchQueue(label: "io.github.zirekhq.dengjen.voices")
    private var client: VoicesClient?
    private let container: URL?

    init() {
        container = AppGroup.containerURL()
        guard let container else {
            errorMessage = String(
                localized: "This build has no shared App Group, so voices cannot be installed.")
            return
        }
        do {
            client = try VoicesClient(
                voicesDirectory: container.appendingPathComponent(AppGroup.voicesDirectory))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the catalogue and the installed voices.
    func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        let language = showAllLanguages ? nil : Self.primaryLanguage
        do {
            let (catalogue, installed) = try await run {
                () throws -> ([CatalogueVoice], [InstalledVoice]) in
                try client.refreshCatalogue()
                return (
                    try CatalogueVoice.decodeList(client.list(language: language)),
                    try InstalledVoice.decodeList(client.installed())
                )
            }
            voices = catalogue.sorted(by: Self.listOrder)
            installedKeys = Set(installed.map(\.key))
            publish(installed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func install(_ voice: CatalogueVoice) async {
        guard let client, installingKey == nil else { return }
        installingKey = voice.key
        progress = 0
        defer { installingKey = nil }
        do {
            let installed = try await run { () throws -> [InstalledVoice] in
                try client.install(voice.key) { done, total in
                    let fraction = total > 0 ? Double(done) / Double(total) : 0
                    Task { @MainActor [weak self] in self?.progress = fraction }
                }
                return try InstalledVoice.decodeList(client.installed())
            }
            installedKeys = Set(installed.map(\.key))
            publish(installed)
        } catch let error as VoicesError where error.isCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelInstall() {
        client?.cancel()
    }

    func remove(_ voice: CatalogueVoice) async {
        guard let client else { return }
        do {
            let installed = try await run { () throws -> [InstalledVoice] in
                try client.remove(voice.key)
                return try InstalledVoice.decodeList(client.installed())
            }
            installedKeys = Set(installed.map(\.key))
            publish(installed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the installed voices where the speech extension reads them, and tells the system
    /// the extension's voices changed.
    private func publish(_ installed: [InstalledVoice]) {
        guard let container else { return }
        let shared = installed.map {
            SharedVoice(installed: $0, voicesDirectory: AppGroup.voicesDirectory)
        }
        do {
            let url = AppGroup.voiceListURL(in: container)
            guard VoiceList.load(from: url) != shared else { return }
            try VoiceList.save(shared, to: url)
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Kurmanji first, then by language and name.
    private static func listOrder(_ lhs: CatalogueVoice, _ rhs: CatalogueVoice) -> Bool {
        let lhsPrimary = lhs.language.family == primaryLanguage
        let rhsPrimary = rhs.language.family == primaryLanguage
        if lhsPrimary != rhsPrimary { return lhsPrimary }
        if lhs.language.code != rhs.language.code { return lhs.language.code < rhs.language.code }
        return lhs.key < rhs.key
    }
}
