import AppKit
import CoreGraphics

/// Inserts text into the focused app: pasteboard write + synthetic Cmd+V,
/// restoring the previous clipboard contents afterwards.
enum TextInserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        // small delay so the pasteboard write is visible to the target app
        usleep(50_000)

        // Post real Cmd key events around the V rather than flag-only V events —
        // session modifier state can be unreliable for flag-tagged synthetic
        // shortcuts after sleep/wake.
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKey: CGKeyCode = 0x37  // kVK_Command
        let vKey: CGKeyCode = 0x09    // kVK_ANSI_V
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdUp?.flags = []
        for event in [cmdDown, vDown, vUp, cmdUp] {
            event?.post(tap: .cghidEventTap)
        }

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
    }
}
