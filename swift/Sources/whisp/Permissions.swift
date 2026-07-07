import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permissions {
    static func ensureAll() -> Bool {
        var ok = true

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { g in
                granted = g
                sem.signal()
            }
            sem.wait()
            if !granted {
                print("✗ Microphone permission denied")
                ok = false
            }
        default:
            print("✗ Microphone: enable in System Settings > Privacy & Security > Microphone")
            ok = false
        }

        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
            print("✗ Input Monitoring: enable in System Settings > Privacy & Security > Input Monitoring, then relaunch")
            ok = false
        }

        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            print("✗ Accessibility: enable in System Settings > Privacy & Security > Accessibility, then relaunch")
            ok = false
        }

        return ok
    }
}
