import AppKit
import Foundation

/// Per-app tone presets: the cleanup model is told what register fits the app
/// you're dictating into. User-editable file overrides the built-in defaults.
enum AppTones {
    static let fileURL = PersonalDictionary.fileURL
        .deletingLastPathComponent()
        .appendingPathComponent("app_tones.txt")

    private static let defaults: [(match: String, tone: String)] = [
        ("messages", "casual and friendly"),
        ("slack", "casual"),
        ("discord", "casual"),
        ("whatsapp", "casual and friendly"),
        ("mail", "professional"),
        ("outlook", "professional"),
        ("word", "professional"),
        ("pages", "professional"),
    ]

    private static let template = """
    # LewisWhisper per-app tones
    # "App Name: tone" — the cleanup AI matches this register in that app.
    # Matching is case-insensitive on the app name; file entries override the
    # built-in defaults (Messages/Slack/Discord/WhatsApp casual, Mail/Outlook/
    # Word/Pages professional).
    # Examples:
    # Notes: terse bullet-point style
    # Safari: neutral
    """

    static func ensureExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (template + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func tone(for appName: String) -> String? {
        let name = appName.lowercased()
        // user file first
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let colon = trimmed.firstIndex(of: ":") else { continue }
                let app = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let tone = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !app.isEmpty, !tone.isEmpty, name.contains(app) {
                    return tone
                }
            }
        }
        return defaults.first { name.contains($0.match) }?.tone
    }

    static func openInEditor() {
        ensureExists()
        NSWorkspace.shared.open(fileURL)
    }
}
