import AppKit
import ApplicationServices

/// A window of another app, addressed through the Accessibility API.
struct ManagedWindow {
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
    let isFullScreen: Bool
    /// Frame in Accessibility coordinates (origin at top-left of the primary display, y grows down).
    let frame: CGRect?
}

struct ManagedApp {
    let app: NSRunningApplication
    let windows: [ManagedWindow]

    var name: String { app.localizedName ?? "Unknown" }
}

// MARK: - Accessibility permission

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow accessibility" prompt if the app isn't trusted yet.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Coordinates

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func isSameDisplay(as other: NSScreen) -> Bool {
        displayID != nil && displayID == other.displayID
    }
}

enum Coordinates {
    /// Cocoa uses a bottom-left origin anchored to the primary display; AX uses top-left.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func axRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen that holds the largest part of an AX-space rect.
    static func screen(forAXRect rect: CGRect) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let overlap = axRect(fromCocoa: screen.frame).intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen
    }

    /// The screen under a point in Cocoa coordinates, such as `NSEvent.mouseLocation`.
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            // The top pixel row sits on the frame's edge, so allow a 1pt margin.
            ?? NSScreen.screens.first { NSMouseInRect(point, $0.frame.insetBy(dx: -1, dy: -1), false) }
    }
}

// MARK: - Window enumeration and movement

enum WindowService {
    /// Caps how long one unresponsive app can stall the menu.
    static func configureTimeouts() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    /// Apps that have at least one standard window, sorted by name.
    /// The Accessibility API sees windows on each display's current Space, including minimized ones.
    static func appsWithWindows() -> [ManagedApp] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let windowOwners = pidsOwningVisibleWindows()

        // Querying every process is slow: most are background helpers, and an unresponsive one stalls
        // until the AX timeout. Regular apps are always checked (they may only have minimized windows);
        // other apps only if they currently show a normal window.
        let candidates = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != myPID, !app.isTerminated else { return false }
            switch app.activationPolicy {
            case .regular: return true
            case .accessory: return windowOwners.contains(app.processIdentifier)
            default: return false
            }
        }
        let pids = candidates.map(\.processIdentifier)

        // Ask all apps at once so one slow app doesn't hold up the rest.
        var found = [Int: [ManagedWindow]]()
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: pids.count) { i in
            let windows = windows(ofPID: pids[i])
            guard !windows.isEmpty else { return }
            lock.lock(); found[i] = windows; lock.unlock()
        }

        return found
            .map { ManagedApp(app: candidates[$0.key], windows: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// PIDs that own a normal (layer 0) window on screen. One fast call that needs no permissions.
    private static func pidsOwningVisibleWindows() -> Set<pid_t> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(info.compactMap { window -> pid_t? in
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return window[kCGWindowOwnerPID as String] as? pid_t
        })
    }

    private static let windowAttributes = [
        kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
        "AXFullScreen", kAXPositionAttribute, kAXSizeAttribute,
    ] as CFArray

    private static func windows(ofPID pid: pid_t) -> [ManagedWindow] {
        let axApp = AXUIElementCreateApplication(pid)
        guard let elements: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) else { return [] }

        return elements.compactMap { element in
            // Fetch everything about the window in one round trip.
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, windowAttributes, [], &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 6 else { return nil }

            let subrole = values[0] as? String
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }

            let title = values[1] as? String ?? ""
            let frame: CGRect? = {
                guard let origin: CGPoint = unpack(values[4], .cgPoint),
                      let size: CGSize = unpack(values[5], .cgSize) else { return nil }
                return CGRect(origin: origin, size: size)
            }()

            return ManagedWindow(
                element: element,
                title: title.isEmpty ? "Untitled window" : title,
                isMinimized: (values[2] as? Bool) ?? false,
                isFullScreen: (values[3] as? Bool) ?? false,
                frame: frame
            )
        }
    }

    /// Reads a point or size out of an AXValue. Missing attributes come back as `.axError` values.
    private static func unpack<T>(_ object: AnyObject, _ type: AXValueType) -> T? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        let value = object as! AXValue
        guard AXValueGetType(value) == type else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value, type, pointer) ? pointer.pointee : nil
    }

    /// Moves a window onto `screen`, keeping its relative position and shrinking it if it doesn't fit.
    /// Returns false if the window can't be moved (for example, it is in native full screen).
    @discardableResult
    static func move(_ window: ManagedWindow, to screen: NSScreen) -> Bool {
        let element = window.element
        guard !window.isFullScreen else { return false }

        if window.isMinimized {
            setAttribute(element, kAXMinimizedAttribute, kCFBooleanFalse)
        }

        guard let origin = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute) else { return false }
        let frame = CGRect(origin: origin, size: size)

        let sourceScreen = Coordinates.screen(forAXRect: frame)
        if let sourceScreen, sourceScreen.isSameDisplay(as: screen) {
            raise(element)
            return true
        }

        let target = Coordinates.axRect(fromCocoa: screen.visibleFrame)
        let source = sourceScreen.map { Coordinates.axRect(fromCocoa: $0.visibleFrame) } ?? target

        let newSize = CGSize(width: min(size.width, target.width),
                             height: min(size.height, target.height))

        // Where the window sat within the free space of its old screen, from 0 to 1 on each axis.
        func fraction(_ offset: CGFloat, _ span: CGFloat) -> CGFloat {
            span > 0 ? min(max(offset / span, 0), 1) : 0.5
        }
        let fx = fraction(frame.minX - source.minX, source.width - size.width)
        let fy = fraction(frame.minY - source.minY, source.height - size.height)
        let newOrigin = CGPoint(x: (target.minX + fx * (target.width - newSize.width)).rounded(),
                                y: (target.minY + fy * (target.height - newSize.height)).rounded())

        let resizing = newSize != size
        if resizing { setSize(element, newSize) }
        setPoint(element, kAXPositionAttribute, newOrigin)
        // Some apps clamp the size to the screen the window was on, so apply it again once it has moved.
        if resizing { setSize(element, newSize) }

        raise(element)
        return true
    }

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: AX helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = axValue(element, name) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &p) ? p : nil
    }

    private static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = axValue(element, name) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value, .cgSize, &s) ? s : nil
    }

    private static func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    private static func setPoint(_ element: AXUIElement, _ name: String, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { setAttribute(element, name, value) }
    }

    private static func setSize(_ element: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { setAttribute(element, kAXSizeAttribute, value) }
    }
}
