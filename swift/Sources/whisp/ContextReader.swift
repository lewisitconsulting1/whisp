import AppKit
import ApplicationServices

struct AppContext {
    let appName: String
    let nearText: String?
    let tone: String?
}

/// Best-effort read of the frontmost app and the focused text field's content
/// via the Accessibility API. Many apps don't expose AXValue — that's fine,
/// the app name alone is still useful context. Secure fields are never read.
enum ContextReader {
    static func capture() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? app.bundleIdentifier ?? "unknown"

        var nearText: String?
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            let element = focusedRef as! AXUIElement

            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String

            if subrole != kAXSecureTextFieldSubrole {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    // last few hundred chars ≈ "near the cursor" for typical
                    // append-at-end dictation; full cursor-relative windowing
                    // needs AXSelectedTextRange and is app-dependent
                    nearText = String(value.suffix(300))
                }
            }
        }
        return AppContext(appName: name, nearText: nearText, tone: AppTones.tone(for: name))
    }
}
