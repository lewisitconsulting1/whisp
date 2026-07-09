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
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var shortName: String {
        settings.provider.displayName.components(separatedBy: " (").first ?? settings.provider.displayName
    }

    private func runTest() {
        testing = true
        testResult = nil
        let client = settings.makeCleaner()
        Task {
            let result = await client.test()
            await MainActor.run {
                testing = false
                switch result {
                case .success(let seconds):
                    testResult = (true, String(format: "✓ %@ responded in %.1f s", shortName, seconds))
                case .failure(let failure):
                    testResult = (false, "✗ \(failure.message)")
                }
            }
        }
    }

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

            Section("Cleanup AI") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(CleanupProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }

                if settings.provider.urlEditable {
                    TextField("Server URL", text: $settings.serverURL)
                        .autocorrectionDisabled()
                }

                if settings.provider.needsKey || settings.provider == .custom {
                    SecureField("API key", text: $settings.apiKey)
                }

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
                    TextField("Model", text: $settings.model,
                              prompt: Text(settings.provider.defaultModel.isEmpty
                                           ? "server's loaded model" : settings.provider.defaultModel))
                }

                HStack {
                    Button("Test") { runTest() }
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let result = testResult {
                        Text(result.text)
                            .font(.caption)
                            .foregroundStyle(result.ok ? Color.green : Color.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                if settings.provider.isCloud {
                    Text("Transcript text is sent to \(shortName) for cleanup. Audio never leaves this Mac — speech-to-text is always local.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .onChange(of: settings.provider) { _, _ in
            testResult = nil
            Task { await loadModels() }
        }
        .onChange(of: settings.serverURL) { _, _ in
            Task { await loadModels() }
        }
    }

    /// Populate the model picker from the server's model list (Ollama
    /// `/api/tags`, LM Studio/custom `/models`); cloud providers use the
    /// free-text field with the preset default.
    private func loadModels() async {
        installedModels = []
        let base = settings.serverURL.isEmpty ? settings.provider.defaultBaseURL : settings.serverURL
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        var names: [String] = []
        do {
            switch settings.provider {
            case .localOllama, .remoteOllama:
                struct Tags: Decodable {
                    struct M: Decodable { let name: String }
                    let models: [M]
                }
                guard let url = URL(string: trimmed + "/api/tags") else { return }
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 2))
                names = try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
            case .lmStudio, .custom:
                struct Models: Decodable {
                    struct M: Decodable { let id: String }
                    let data: [M]
                }
                guard let url = URL(string: trimmed + "/models") else { return }
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 2))
                names = try JSONDecoder().decode(Models.self, from: data).data.map(\.id).sorted()
            default:
                return  // cloud providers: free-text model field
            }
        } catch {
            return  // unreachable server: leave the free-text field
        }
        guard !names.isEmpty else { return }
        if !settings.model.isEmpty, !names.contains(settings.model) {
            names.insert(settings.model, at: 0)
        }
        if settings.model.isEmpty, settings.provider == .lmStudio, let first = names.first {
            settings.model = first
        }
        installedModels = names
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
