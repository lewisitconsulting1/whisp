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
            case "--learn":  // debug: run WordLearner.observe on a string and exit
                if let v = it.next() {
                    let promoted = WordLearner.observe(v)
                    print("candidates: \(WordLearner.extractCandidates(from: v).joined(separator: ", "))")
                    print("promoted:   \(promoted.joined(separator: ", "))")
                    exit(0)
                }
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
        print("learn candidates: \(WordLearner.extractCandidates(from: final).joined(separator: ", "))")
        exit(0)
    } catch {
        print("selftest failed: \(error)")
        exit(1)
    }
}

// MARK: - App controller

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let recorder = AudioRecorder()
    private let monitor: HotkeyMonitor
    private var cleaner: CleanupClient
    private var transcriber: Transcriber?
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var busy = false
    // capture state: hold = walkie-talkie, quick tap = hands-free until the
    // next tap or configurable post-speech silence
    private var capturing = false
    private var handsFree = false
    private var pressedAt: Date?
    private var silenceTimer: Timer?

    init(options: Options) {
        self.settings = AppSettings(options: options)
        self.monitor = HotkeyMonitor(key: options.hotkey)
        self.cleaner = CleanupClient(model: options.model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        monitor.onPress = { [weak self] in self?.startDictation() }
        monitor.onRelease = { [weak self] in self?.finishDictation() }
        cleaner = settings.makeCleaner()
        settings.onChange = { [weak self] in self?.applySettings() }

        if Permissions.missing.isEmpty {
            beginStartup()
        } else {
            enterPermissionBlockedState()
        }
    }

    /// Re-apply mutable settings after any change (from menu or Settings
    /// window). Idempotent — cheap to call for every mutation.
    private func applySettings() {
        if monitor.key != settings.hotkey {
            monitor.setKey(settings.hotkey)
            print("hotkey → \(settings.hotkey.displayName)")
        }
        let fresh = settings.makeCleaner()
        if fresh.provider != cleaner.provider || fresh.model != cleaner.model
            || fresh.baseURL != cleaner.baseURL || fresh.apiKey != cleaner.apiKey {
            cleaner = fresh
            print("cleanup → \(fresh.provider.displayName) · \(fresh.model.isEmpty ? "(server default)" : fresh.model)")
            if !fresh.provider.isCloud {
                Task { await self.cleaner.warmUp() }
            }
        }
        rebuildMenu(blocked: !Permissions.missing.isEmpty)
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
                if self.settings.level != .off && !self.settings.provider.isCloud {
                    print("warming \(self.settings.model) via \(self.settings.provider.displayName)...")
                    await self.cleaner.warmUp()
                }
                guard self.monitor.start() else {
                    print("✗ could not create event tap despite Input Monitoring being granted")
                    self.setIcon(blocked: true)
                    return
                }
                self.setIcon(idle: true, loading: false)
                print("ready — hold \(self.settings.hotkey.displayName) to dictate, quick-tap for hands-free")
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
            item.state = (lvl == settings.level) ? .on : .off
            sub.addItem(item)
        }
        menu.addItem(cleanupItem)
        menu.setSubmenu(sub, for: cleanupItem)

        let ctxItem = NSMenuItem(title: "Context Awareness", action: #selector(toggleContext), keyEquivalent: "")
        ctxItem.target = self
        ctxItem.state = settings.contextAware ? .on : .off
        menu.addItem(ctxItem)

        let learnItem = NSMenuItem(title: "Learn New Words", action: #selector(toggleLearnWords), keyEquivalent: "")
        learnItem.target = self
        learnItem.state = settings.learnWords ? .on : .off
        menu.addItem(learnItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About LewisWhisper", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quitItem = NSMenuItem(title: "Quit LewisWhisper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    // menu actions mutate settings; settings.onChange re-applies + rebuilds
    @objc private func selectLevel(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lvl = CleanupClient.Level(rawValue: raw) {
            settings.level = lvl
        }
    }

    @objc private func toggleContext() {
        settings.contextAware.toggle()
    }

    @objc private func toggleLearnWords() {
        settings.learnWords.toggle()
    }

    @objc private func showSettingsWindow() {
        SettingsWindow.show(settings: settings)
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
        guard transcriber != nil else { return }
        if handsFree {
            stopCapture()  // tap while hands-free = finish
            return
        }
        guard !busy, !capturing else { return }
        do {
            try recorder.start()
            capturing = true
            pressedAt = Date()
            setIcon(recording: true)
            playFeedback("Tink")
            print("\n● recording...")
        } catch {
            print("✗ mic start failed: \(error)")
        }
    }

    private func playFeedback(_ name: String) {
        guard settings.soundFeedback, let sound = NSSound(named: name) else { return }
        sound.volume = 0.3
        sound.play()
    }

    private func finishDictation() {
        guard capturing, !handsFree else { return }  // release is meaningless in hands-free
        let held = pressedAt.map { Date().timeIntervalSince($0) } ?? 1.0
        if held < 0.35 {
            // quick tap: switch to hands-free capture
            handsFree = true
            print("● hands-free — tap again or pause ~1s to finish")
            startSilenceWatch()
        } else {
            stopCapture()
        }
    }

    private func stopCapture() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        handsFree = false
        guard capturing else { return }
        capturing = false
        playFeedback("Pop")
        process(recorder.stop())
    }

    private func startSilenceWatch() {
        guard settings.autoStop else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.handsFree, self.capturing else { return }
                let v = self.recorder.voiceStatus()
                // stop after the configured post-speech silence; 3 min hard cap
                if (v.heardVoice && v.silenceSeconds > self.settings.silenceDelay) || v.duration > 180 {
                    self.stopCapture()
                }
            }
        }
    }

    private func process(_ samples: [Float]) {
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
        let context = (settings.contextAware && settings.level != .off) ? ContextReader.capture() : nil
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
                text, level: self.settings.level, dictionary: PersonalDictionary.terms(), context: context)
            let tLlm = Date().timeIntervalSince(t1)
            TextInserter.insert(final)
            let total = Date().timeIntervalSince(t0)
            print(String(format: "  %.1fs audio | stt %.2fs | llm %.2fs | total %.2fs", duration, tStt, tLlm, total))
            print("  raw:   \(text)")
            if final != text { print("  clean: \(final)") }
            if self.settings.learnWords {
                let learned = WordLearner.observe(final)
                if !learned.isEmpty {
                    print("  learned: \(learned.joined(separator: ", ")) → personal dictionary")
                }
            }
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
