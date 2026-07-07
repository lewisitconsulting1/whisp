import AppKit
import Foundation

// MARK: - CLI options

struct Options {
    var level: CleanupClient.Level
    var contextAware: Bool
    var model: String
    var hotkey: HotkeyMonitor.Key = .altRight
    var selftest: String?

    static func parse(_ args: [String]) -> Options {
        let defaults = UserDefaults.standard
        var o = Options(
            level: CleanupClient.Level(rawValue: defaults.string(forKey: "cleanupLevel") ?? "") ?? .light,
            contextAware: defaults.object(forKey: "contextAwareness") as? Bool ?? true,
            model: defaults.string(forKey: "model") ?? "gemma3:4b"
        )
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--cleanup":
                if let v = it.next(), let l = CleanupClient.Level(rawValue: v) { o.level = l }
            case "--context":
                if let v = it.next() { o.contextAware = (v != "off") }
            case "--model":
                if let v = it.next() { o.model = v }
            case "--hotkey":
                if let v = it.next(), let k = HotkeyMonitor.Key(rawValue: v) { o.hotkey = k }
            case "--selftest":
                if let v = it.next() { o.selftest = v }
            case "--help", "-h":
                print("usage: LewisWhisper [--cleanup off|light|medium|high] [--context off] [--model gemma3:4b] [--hotkey alt_r|cmd_r|ctrl_r] [--selftest file.wav]")
                exit(0)
            default:
                break
            }
        }
        return o
    }
}

// MARK: - Headless pipeline check (no permissions needed)

func runSelftest(wavPath: String, options: Options) async {
    do {
        let transcriber = try await Transcriber.load()
        let cleaner = CleanupClient(model: options.model)
        if options.level != .off { await cleaner.warmUp() }
        let dictionary = PersonalDictionary.terms()
        if !dictionary.isEmpty { print("dictionary: \(dictionary.joined(separator: ", "))") }
        let t0 = Date()
        let text = try await transcriber.transcribe(fileURL: URL(fileURLWithPath: wavPath))
        let tStt = Date().timeIntervalSince(t0)
        let t1 = Date()
        let final = await cleaner.clean(text, level: options.level, dictionary: dictionary, context: nil)
        let tLlm = Date().timeIntervalSince(t1)
        print(String(format: "stt %.2fs | llm %.2fs | total %.2fs", tStt, tLlm, Date().timeIntervalSince(t0)))
        print("raw:   \(text)")
        if final != text { print("clean: \(final)") }
        exit(0)
    } catch {
        print("selftest failed: \(error)")
        exit(1)
    }
}

// MARK: - App controller

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let options: Options
    private let recorder = AudioRecorder()
    private let monitor: HotkeyMonitor
    private let cleaner: CleanupClient
    private var transcriber: Transcriber?
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var busy = false
    private var level: CleanupClient.Level {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: "cleanupLevel") }
    }
    private var contextAware: Bool {
        didSet { UserDefaults.standard.set(contextAware, forKey: "contextAwareness") }
    }

    init(options: Options) {
        self.options = options
        self.level = options.level
        self.contextAware = options.contextAware
        self.monitor = HotkeyMonitor(key: options.hotkey)
        self.cleaner = CleanupClient(model: options.model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        monitor.onPress = { [weak self] in self?.startDictation() }
        monitor.onRelease = { [weak self] in self?.finishDictation() }

        if Permissions.missing.isEmpty {
            beginStartup()
        } else {
            enterPermissionBlockedState()
        }
    }

    /// Bundled app launched from Finder has no terminal to read instructions
    /// from: fire the system prompts, show what's missing in the menu, and
    /// poll until everything is granted.
    private func enterPermissionBlockedState() {
        setIcon(blocked: true)
        Permissions.requestMissing()
        rebuildMenu(blocked: true)
        print("waiting for permissions: \(Permissions.missing.map(\.rawValue).joined(separator: ", "))")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // scheduledTimer fires on the main run loop
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Permissions.missing.isEmpty else {
                    self.rebuildMenu(blocked: true)
                    return
                }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.beginStartup()
            }
        }
    }

    private func beginStartup() {
        setIcon(idle: false, loading: true)
        rebuildMenu(blocked: false)
        PersonalDictionary.ensureExists()
        Task {
            do {
                let t = try await Transcriber.load()
                self.transcriber = t
                if self.level != .off {
                    print("warming \(self.options.model) via Ollama...")
                    await self.cleaner.warmUp()
                }
                guard self.monitor.start() else {
                    print("✗ could not create event tap despite Input Monitoring being granted")
                    self.setIcon(blocked: true)
                    return
                }
                self.setIcon(idle: true, loading: false)
                let keyName = self.options.hotkey.rawValue.split(separator: "_").first.map(String.init) ?? "alt"
                print("ready — hold RIGHT \(keyName.uppercased()) to dictate, release to insert")
            } catch {
                print("✗ failed to load speech model: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    private func rebuildMenu(blocked: Bool) {
        let menu = NSMenu()
        if blocked {
            let header = NSMenuItem(title: "Grant permissions to use LewisWhisper:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for kind in Permissions.missing {
                let item = NSMenuItem(title: "Open \(kind.rawValue) Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = kind.rawValue
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let cleanupItem = NSMenuItem(title: "Cleanup", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for lvl in CleanupClient.Level.allCases {
            let item = NSMenuItem(title: lvl.menuTitle, action: #selector(selectLevel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lvl.rawValue
            item.state = (lvl == level) ? .on : .off
            sub.addItem(item)
        }
        menu.addItem(cleanupItem)
        menu.setSubmenu(sub, for: cleanupItem)

        let ctxItem = NSMenuItem(title: "Context Awareness", action: #selector(toggleContext), keyEquivalent: "")
        ctxItem.target = self
        ctxItem.state = contextAware ? .on : .off
        menu.addItem(ctxItem)

        let dictItem = NSMenuItem(title: "Edit Personal Dictionary…", action: #selector(editDictionary), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About LewisWhisper", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quitItem = NSMenuItem(title: "Quit LewisWhisper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func selectLevel(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lvl = CleanupClient.Level(rawValue: raw) {
            level = lvl
            rebuildMenu(blocked: false)
        }
    }

    @objc private func toggleContext() {
        contextAware.toggle()
        rebuildMenu(blocked: false)
    }

    @objc private func editDictionary() {
        PersonalDictionary.openInEditor()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Created by Chadwick Lewis\nLewis IT Consulting\n\nFully local dictation — your voice never leaves this Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let kind = Permissions.Kind(rawValue: raw) {
            Permissions.openSettings(for: kind)
        }
    }

    private func startDictation() {
        guard !busy, transcriber != nil else { return }
        do {
            try recorder.start()
            setIcon(recording: true)
            print("\n● recording...")
        } catch {
            print("✗ mic start failed: \(error)")
        }
    }

    private func finishDictation() {
        guard transcriber != nil else { return }
        let samples = recorder.stop()
        setIcon(idle: true, loading: false)
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        guard duration >= 0.3 else {
            print("  (too short, ignored)")
            return
        }
        guard !busy else { return }
        busy = true
        setIcon(working: true)
        // capture focus context now, before the paste target could change
        let context = (contextAware && level != .off) ? ContextReader.capture() : nil
        Task {
            defer {
                self.busy = false
                self.setIcon(idle: true, loading: false)
            }
            let t0 = Date()
            guard let text = try? await self.transcriber?.transcribe(samples), !text.isEmpty else {
                print("  (no speech detected)")
                return
            }
            let tStt = Date().timeIntervalSince(t0)
            let t1 = Date()
            let final = await self.cleaner.clean(
                text, level: self.level, dictionary: PersonalDictionary.terms(), context: context)
            let tLlm = Date().timeIntervalSince(t1)
            TextInserter.insert(final)
            let total = Date().timeIntervalSince(t0)
            print(String(format: "  %.1fs audio | stt %.2fs | llm %.2fs | total %.2fs", duration, tStt, tLlm, total))
            print("  raw:   \(text)")
            if final != text { print("  clean: \(final)") }
        }
    }

    /// Soundwave template image from the bundle (adapts to menu bar light/dark);
    /// nil when running the bare binary from a terminal — emoji fallback.
    private static let menuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    private func setIcon(idle: Bool = false, loading: Bool = false, recording: Bool = false, working: Bool = false, blocked: Bool = false) {
        guard let button = statusItem?.button else { return }
        let transient = blocked || recording || working || loading
        if !transient, let img = Self.menuBarImage {
            button.image = img
            button.title = ""
        } else {
            button.image = nil
            button.title = blocked ? "⚠️" : recording ? "🔴" : working ? "⏳" : loading ? "…" : "🎙"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry

let options = Options.parse(CommandLine.arguments)
if let wav = options.selftest {
    // keep top-level code synchronous (async top-level would change AppKit
    // entry semantics); runSelftest exits the process when done
    Task.detached { await runSelftest(wavPath: wav, options: options) }
    dispatchMain()
}
// top-level code runs on the main thread but isn't statically MainActor-isolated
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = AppController(options: options)
    app.delegate = controller
    withExtendedLifetime(controller) {
        app.run()
    }
}
