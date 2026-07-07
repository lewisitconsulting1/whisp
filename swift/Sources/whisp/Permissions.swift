import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permissions {
    enum Kind: String, CaseIterable {
        case microphone = "Microphone"
        case inputMonitoring = "Input Monitoring"
        case accessibility = "Accessibility"

        var settingsPane: String {
            switch self {
            case .microphone: return "Privacy_Microphone"
            case .inputMonitoring: return "Privacy_ListenEvent"
            case .accessibility: return "Privacy_Accessibility"
            }
        }

        var granted: Bool {
            switch self {
            case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            case .inputMonitoring: return CGPreflightListenEventAccess()
            case .accessibility: return AXIsProcessTrusted()
            }
        }
    }

    static var missing: [Kind] {
        Kind.allCases.filter { !$0.granted }
    }

    /// Fire the system prompts for everything not yet granted. Safe to call
    /// repeatedly; already-granted or already-denied permissions no-op.
    static func requestMissing() {
        if !Kind.microphone.granted {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        if !Kind.inputMonitoring.granted {
            CGRequestListenEventAccess()
        }
        if !Kind.accessibility.granted {
            // string literal instead of the kAXTrustedCheckOptionPrompt global
            // to avoid Swift concurrency complaints about the CFString global
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    static func openSettings(for kind: Kind) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)"
        if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }
}
