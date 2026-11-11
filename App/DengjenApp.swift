import DengjenCore
import SwiftUI

@main
struct DengjenApp: App {
    @StateObject private var store = VoiceStore()

    var body: some Scene {
        WindowGroup {
            VoiceManagerView(store: store)
                .frame(minWidth: 520, minHeight: 420)
        }
    }
}

/// Lists the voices, installs and removes them. Every control has a label VoiceOver reads.
struct VoiceManagerView: View {
    @ObservedObject var store: VoiceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dengjen voices")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(
                "Install a voice, then choose it in System Settings, Accessibility, Spoken Content, or in VoiceOver Utility."
            )
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Toggle("Show all languages", isOn: $store.showAllLanguages)
                Spacer()
                Button("Refresh") { Task { await store.reload() } }
                    .disabled(store.isLoading || store.installingKey != nil)
            }

            if store.isLoading && store.voices.isEmpty {
                ProgressView("Loading the voice list")
            }

            List(store.voices) { voice in
                VoiceRow(voice: voice, store: store)
            }
            .accessibilityLabel("Voices")
        }
        .padding()
        .task { await store.reload() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct VoiceRow: View {
    let voice: CatalogueVoice
    @ObservedObject var store: VoiceStore

    private var isInstalled: Bool { store.installedKeys.contains(voice.key) }
    private var isInstalling: Bool { store.installingKey == voice.key }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(voice.displayName)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if isInstalling {
                ProgressView(value: store.progress)
                    .frame(width: 120)
                    .accessibilityLabel("Downloading \(voice.displayName)")
                    .accessibilityValue("\(Int(store.progress * 100)) percent")
                Button("Cancel") { store.cancelInstall() }
                    .accessibilityLabel("Cancel downloading \(voice.displayName)")
            } else if isInstalled {
                Button("Remove") { Task { await store.remove(voice) } }
                    .accessibilityLabel("Remove \(voice.displayName)")
                    .disabled(store.installingKey != nil)
            } else {
                Button("Install") { Task { await store.install(voice) } }
                    .accessibilityLabel("Install \(voice.displayName)")
                    .disabled(store.installingKey != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        let language = voice.language.nameNative.isEmpty
            ? voice.language.code : "\(voice.language.nameNative) (\(voice.language.code))"
        let size = ByteCountFormatter.string(fromByteCount: Int64(voice.size), countStyle: .file)
        let state = isInstalled ? String(localized: "Installed") : size
        return "\(language), \(state)"
    }
}
