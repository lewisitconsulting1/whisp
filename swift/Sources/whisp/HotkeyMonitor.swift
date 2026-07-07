import CoreGraphics
import Foundation

/// Watches a modifier key (default: right Option) via a listen-only CGEvent tap.
/// Calls onPress when the key goes down and onRelease when it comes back up.
final class HotkeyMonitor {
    enum Key: String {
        case altRight = "alt_r"
        case cmdRight = "cmd_r"
        case ctrlRight = "ctrl_r"

        var keyCode: Int64 {
            switch self {
            case .altRight: return 61   // kVK_RightOption
            case .cmdRight: return 54   // kVK_RightCommand
            case .ctrlRight: return 62  // kVK_RightControl
            }
        }

        var flag: CGEventFlags {
            switch self {
            case .altRight: return .maskAlternate
            case .cmdRight: return .maskCommand
            case .ctrlRight: return .maskControl
            }
        }
    }

    let key: Key
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var tap: CFMachPort?
    private var pressed = false

    init(key: Key) {
        self.key = key
    }

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged, event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else { return }
        // flagsChanged fires for this keycode on both press and release; the flag
        // mask is side-agnostic (left+right Option share .maskAlternate), so track
        // the key's own down-state instead of trusting the mask for release.
        // Dispatch handlers async: >1s of work in a tap callback gets the tap
        // disabled by macOS.
        if pressed {
            pressed = false
            DispatchQueue.main.async { self.onRelease() }
        } else if event.flags.contains(key.flag) {
            pressed = true
            DispatchQueue.main.async { self.onPress() }
        }
    }
}
