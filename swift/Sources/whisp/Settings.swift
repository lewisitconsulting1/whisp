import AppKit
import SwiftUI

// MARK: - Single source of truth for user preferences

/// UserDefaults-backed settings shared by the menu and the Settings window.
/// `onChange` fires after any mutation so the controller can re-apply state
/// (menu checkmarks, hotkey swap, cleanup-model swap) idempotently.
@MainActor
final class AppSettings: ObservableObject {
    var onChange: (() -> Void)?

    @Published var hotkey: HotkeyMonitor.Key {
        didSet { persist(hotkey.rawValue, "hotkey") }
    }
    @Published var level: CleanupClient.Level {
        didSet { persist(level.rawValue, "cleanupLevel") }
    }
    @Published var provider: CleanupProvider {
        didSet {
            persist(provider.rawValue, "cleanupProvider")
            // switching providers swaps in that provider's remembered URL/model/key
            serverURL = UserDefaults.standard.string(forKey: "serverURL.\(provider.rawValue)") ?? provider.defaultBaseURL
            model = UserDefaults.standard.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModel
            apiKey = KeychainStore.get(account: "apikey.\(provider.rawValue)") ?? ""
        }
    }
    @Published var serverURL: String {
        didSet { persist(serverURL, "serverURL.\(provider.rawValue)") }
    }
    @Published var model: String {
        didSet { persist(model, "model.\(provider.rawValue)") }
    }
    /// Keychain-backed mirror — the key itself is never written to UserDefaults
    @Published var apiKey: String {
        didSet {
            KeychainStore.set(apiKey, account: "apikey.\(provider.rawValue)")
            onChange?()
        }
    }
    @Published var contextAware: Bool {
        didSet { persist(contextAware, "contextAwareness") }
    }
    @Published var autoStop: Bool {
        didSet { persist(autoStop, "autoStopSilence") }
    }
    @Published var silenceDelay: Double {
        didSet { persist(silenceDelay, "silenceDelay") }
    }
    @Published var learnWords: Bool {
        didSet { persist(learnWords, "learnWords") }
    }
    @Published var soundFeedback: Bool {
        didSet { persist(soundFeedback, "soundFeedback") }
    }

    init(options: Options) {
        let d = UserDefaults.standard
        // property-observer note: assignments in init don't fire didSet, so
        // seeding from CLI options here doesn't spuriously persist them
        self.hotkey = options.hotkey
        self.level = options.level
        let storedProvider = CleanupProvider(rawValue: d.string(forKey: "cleanupProvider") ?? "") ?? .localOllama
        self.provider = storedProvider
        self.serverURL = d.string(forKey: "serverURL.\(storedProvider.rawValue)") ?? storedProvider.defaultBaseURL
        // migration: pre-provider versions stored a single "model" key
        if d.string(forKey: "model.\(CleanupProvider.localOllama.rawValue)") == nil,
           let legacy = d.string(forKey: "model") {
            d.set(legacy, forKey: "model.\(CleanupProvider.localOllama.rawValue)")
        }
        self.model = d.string(forKey: "model.\(storedProvider.rawValue)") ?? options.model
        self.apiKey = KeychainStore.get(account: "apikey.\(storedProvider.rawValue)") ?? ""
        self.contextAware = options.contextAware
        self.autoStop = d.object(forKey: "autoStopSilence") as? Bool ?? true
        self.silenceDelay = d.object(forKey: "silenceDelay") as? Double ?? 1.2
        self.learnWords = d.object(forKey: "learnWords") as? Bool ?? true
        self.soundFeedback = d.object(forKey: "soundFeedback") as? Bool ?? true
    }

    func makeCleaner() -> CleanupClient {
        CleanupClient(
            provider: provider,
            baseURL: serverURL.isEmpty ? provider.defaultBaseURL : serverURL,
            model: model.isEmpty ? provider.defaultModel : model,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
    }

    private func persist(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var installedModels: [String] = []
    @State private var ollamaReachable = true

    /// Lewis IT logo from the bundle; black-on-transparent, rendered as a
    /// template so it adapts to light/dark. Absent when running unbundled.
    private static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "lewis-it-logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    if let logo = Self.logo {
                        Image(nsImage: logo)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 52)
                            .foregroundStyle(.primary)
                    }
                    Text("Created by Chadwick Lewis · Lewis IT Consulting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section("Dictation") {
                Picker("Hotkey", selection: $settings.hotkey) {
                    ForEach(HotkeyMonitor.Key.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                Toggle("Auto-stop on silence (hands-free)", isOn: $settings.autoStop)
                if settings.autoStop {
                    HStack {
                        Text("Stop after")
                        Slider(value: $settings.silenceDelay, in: 0.5...3.0, step: 0.1)
                        Text(String(format: "%.1f s", settings.silenceDelay))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Sound feedback", isOn: $settings.soundFeedback)
            }

            Section("Cleanup") {
                Picker("Level", selection: $settings.level) {
                    ForEach(CleanupClient.Level.allCases, id: \.self) { lvl in
                        Text(lvl.menuTitle).tag(lvl)
                    }
                }
                if !installedModels.isEmpty {
                    Picker("Model", selection: $settings.model) {
                        ForEach(installedModels, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Model", text: $settings.model)
                    if !ollamaReachable {
                        Text("Ollama isn't reachable — raw transcripts will be pasted until it's running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Context awareness", isOn: $settings.contextAware)
                Toggle("Learn new words automatically", isOn: $settings.learnWords)
            }

            Section("Customization files") {
                HStack {
                    Button("Personal Dictionary…") { PersonalDictionary.openInEditor() }
                    Button("App Tones…") { AppTones.openInEditor() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await loadModels() }
    }

    /// Populate the model picker from Ollama's local API; fall back to a
    /// free-text field when unreachable.
    private func loadModels() async {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!, timeoutInterval: 2)
        req.httpMethod = "GET"
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            var names = try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
            if !names.contains(settings.model) { names.insert(settings.model, at: 0) }
            installedModels = names
        } catch {
            ollamaReachable = false
            installedModels = []
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(settings: AppSettings) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let w = NSWindow(contentViewController: hosting)
            w.title = "LewisWhisper Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
