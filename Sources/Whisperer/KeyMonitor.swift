import Cocoa
import Carbon

@MainActor
class KeyMonitor {
    // Key code for right option key is 61
    fileprivate let rightOptionKeyCode: Int = 61
    
    fileprivate var isRightOptionPressed = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logEnabled = false
    
    var onRightOptionKeyDown: (() -> Void)?
    var onRightOptionKeyUp: (() -> Void)?
    
    init() {}
    
    deinit {
        // Cannot use Task in deinit as it captures self and outlives deinit
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }
    
    func start() -> Bool {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // For C callbacks we can't use a closure that captures context directly
        // So we'll use a static callback function and pass self as userInfo
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Listen-only is sufficient for hotkey detection and is less fragile.
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("Failed to create event tap")
            return false
        }
        
        self.eventTap = eventTap
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            log("Key monitor started")
            return true
        }
        
        CGEvent.tapEnable(tap: eventTap, enable: false)
        self.eventTap = nil
        log("Failed to create event tap run loop source")
        return false
    }
    
    // Keep this as a regular MainActor method since we call it from the main actor
    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        
        log("Key monitor stopped")
    }
    
    private func log(_ message: String) {
        if logEnabled {
            print("[KeyMonitor] \(message)")
        }
    }
    
    // Helper function to handle key events on the main actor
    nonisolated func handleKeyEvent(isPressed: Bool, keyCode: Int64) {
        if keyCode == Int64(rightOptionKeyCode) {
            Task { @MainActor in
                if isPressed {
                    isRightOptionPressed = true
                    onRightOptionKeyDown?()
                } else {
                    isRightOptionPressed = false
                    onRightOptionKeyUp?()
                }
            }
        }
    }
}

// Static callback function for the event tap - must NOT be actor-isolated
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    
    // Get the KeyMonitor instance from userInfo
    let keyMonitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    
    if type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isOptionPressed = flags.contains(.maskAlternate)
        
        // Use the nonisolated helper to handle the event
        keyMonitor.handleKeyEvent(isPressed: isOptionPressed, keyCode: keyCode)
    }
    
    return Unmanaged.passUnretained(event)
}
