import AppKit
import Foundation

/// User-managed terms the recognizer tends to mishear (names, brands, jargon).
/// Plain text file, one term per line, # comments. Injected into the cleanup
/// prompt so the LLM corrects phonetically-similar mishearings.
enum PersonalDictionary {
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LewisWhisper", isDirectory: true)
        return dir.appendingPathComponent("dictionary.txt")
    }()

    private static let template = """
    # LewisWhisper personal dictionary
    # One term per line — names, brands, jargon the recognizer mishears.
    # Lines starting with # are ignored.
    """

    static func ensureExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (template + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Re-read on every dictation — the file is tiny and this picks up edits live.
    static func terms() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return Array(lines.prefix(100))
    }

    static func openInEditor() {
        ensureExists()
        NSWorkspace.shared.open(fileURL)
    }
}
