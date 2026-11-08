import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    /// The display whose menu bar icon was clicked; windows are moved here.
    private var targetScreen: NSScreen?
    /// Resized app icons, so reopening the menu doesn't reload them from disk.
    private var iconCache: [pid_t: NSImage] = [:]

    private static let showWindowsKey = "showIndividualWindows"
    private var showIndividualWindows: Bool {
        get { UserDefaults.standard.object(forKey: Self.showWindowsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.showWindowsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowService.configureTimeouts()

        // With "Displays have separate Spaces" on (the macOS default), the system draws
        // this one status item in the menu bar of every display.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.make()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if !Accessibility.isTrusted { Accessibility.requestAccess() }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // The pointer is on the icon that was just clicked, so its screen is the target.
        targetScreen = Coordinates.screen(containing: NSEvent.mouseLocation)
            ?? statusItem.button?.window?.screen
            ?? NSScreen.main
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        guard Accessibility.isTrusted else {
            menu.addItem(disabled("Pullie needs Accessibility access to move windows."))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
            addFooter()
            return
        }

        let screenName = targetScreen?.localizedName ?? "this screen"
        menu.addItem(disabled("Move to \(screenName)"))
        menu.addItem(.separator())

        let apps = WindowService.appsWithWindows()
        if apps.isEmpty {
            menu.addItem(disabled("No open windows"))
        }

        for managed in apps {
            let appItem = item(managed.name, #selector(moveApp(_:)))
            appItem.image = icon(for: managed.app)
            appItem.representedObject = managed
            appItem.toolTip = "Move all \(managed.name) windows to \(screenName)"
            menu.addItem(appItem)

            guard showIndividualWindows else {
                if managed.windows.allSatisfy(isOnTarget) { appItem.state = .on }
                continue
            }

            for window in managed.windows {
                var title = window.title
                if window.isMinimized { title += " (minimized)" }
                if window.isFullScreen { title += " (full screen)" }

                let windowItem = item(truncate(title), #selector(moveWindow(_:)))
                windowItem.indentationLevel = 1
                windowItem.representedObject = (managed.app, window)
                windowItem.isEnabled = !window.isFullScreen
                if isOnTarget(window) { windowItem.state = .on }
                menu.addItem(windowItem)
            }
        }

        addFooter()
    }

    private func addFooter() {
        menu.addItem(.separator())

        let settings = NSMenu()
        let windows = item("Show Individual Windows", #selector(toggleShowIndividualWindows))
        windows.state = showIndividualWindows ? .on : .off
        settings.addItem(windows)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settings.addItem(login)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        menu.addItem(settingsItem)
        menu.addItem(item("Quit Pullie", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    // MARK: Actions

    @objc private func moveApp(_ sender: NSMenuItem) {
        guard let managed = sender.representedObject as? ManagedApp, let screen = targetScreen else { return }
        // Move back-to-front so the app's frontmost window stays on top.
        for window in managed.windows.reversed() {
            WindowService.move(window, to: screen)
        }
        managed.app.activate(options: [.activateAllWindows])
    }

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let (app, window) = sender.representedObject as? (NSRunningApplication, ManagedWindow),
              let screen = targetScreen else { return }
        WindowService.move(window, to: screen)
        app.activate(options: [])
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.requestAccess()
        Accessibility.openSettings()
    }

    @objc private func toggleShowIndividualWindows() {
        showIndividualWindows.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }

    // MARK: Helpers

    private func isOnTarget(_ window: ManagedWindow) -> Bool {
        guard let frame = window.frame, let target = targetScreen,
              let current = Coordinates.screen(forAXRect: frame) else { return false }
        return current.isSameDisplay(as: target)
    }

    private func icon(for app: NSRunningApplication) -> NSImage? {
        let pid = app.processIdentifier
        if let cached = iconCache[pid] { return cached }
        guard let image = app.icon?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        iconCache[pid] = image
        return image
    }

    private func truncate(_ s: String, max: Int = 60) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
