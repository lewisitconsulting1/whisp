import AppKit
import Foundation

// MARK: - CLI options

struct Options {
    var cleanup = true
    var model = "gemma3:4b"
    var hotkey: HotkeyMonitor.Key = .altRight
    var selftest: String?

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--cleanup":
                if let v = it.next() { o.cleanup = (v != "off") }
            case "--model":
                if let v = it.next() { o.model = v }
            case "--hotkey":
                if let v = it.next(), let k = HotkeyMonitor.Key(rawValue: v) { o.hotkey = k }
            case "--selftest":
                if let v = it.next() { o.selftest = v }
            case "--help", "-h":
                print("usage: whisp [--cleanup off|light] [--model gemma3:4b] [--hotkey alt_r|cmd_r|ctrl_r] [--selftest file.wav]")
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
        if options.cleanup { await cleaner.warmUp() }
        let t0 = Date()
        let text = try await transcriber.transcribe(fileURL: URL(fileURLWithPath: wavPath))
        let tStt = Date().timeIntervalSince(t0)
        let t1 = Date()
        let final = options.cleanup ? await cleaner.clean(text) : text
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

    init(options: Options) {
        self.options = options
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
        Task {
            do {
                let t = try await Transcriber.load()
                self.transcriber = t
                if self.options.cleanup {
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
            let header = NSMenuItem(title: "Grant permissions to use whisp:", action: nil, keyEquivalent: "")
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
        let quitItem = NSMenuItem(title: "Quit whisp", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
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
            let final = self.options.cleanup ? await self.cleaner.clean(text) : text
            let tLlm = Date().timeIntervalSince(t1)
            TextInserter.insert(final)
            let total = Date().timeIntervalSince(t0)
            print(String(format: "  %.1fs audio | stt %.2fs | llm %.2fs | total %.2fs", duration, tStt, tLlm, total))
            print("  raw:   \(text)")
            if final != text { print("  clean: \(final)") }
        }
    }

    private func setIcon(idle: Bool = false, loading: Bool = false, recording: Bool = false, working: Bool = false, blocked: Bool = false) {
        let title = blocked ? "⚠️" : recording ? "🔴" : working ? "⏳" : loading ? "…" : "🎙"
        statusItem?.button?.title = title
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
