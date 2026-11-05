import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let viewController = PlayerViewController(playbackController: AVAudioPlaybackController())
        let window = NSWindow(contentViewController: viewController)
        window.title = "LLP Audio Loop Player"
        window.setContentSize(NSSize(width: 1180, height: 420))
        window.minSize = NSSize(width: 1180, height: 360)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit LLP",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        let redoItem = menuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem(
            title: "Select All",
            action: #selector(NSResponder.selectAll(_:)),
            keyEquivalent: "a"
        ))
        editMenu.addItem(menuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(menuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = .command
        return item
    }
}
