import AppKit
import MarkdownReaderCore
import SwiftUI

@MainActor
final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    private let model = ReaderModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMenu()
        // Files passed by `open -a` arrive through application(_:open:); only show help when none came.
        Task { @MainActor in
            if model.document == nil {
                model.show(ReaderDocument(
                    source: "# Reader\n\nOpen a console, report, or snapshot from Nova to read it here.",
                    fileName: "Reader"
                ))
                showWindow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last else { return }
        model.open(url)
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showWindow() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.title = model.document?.title ?? "Reader"
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ReaderView(model: model, onCopyAll: { [weak self] in
            self?.copyAll()
        }))
        window.center()
        return window
    }

    @objc func copyAll() {
        guard let source = model.document?.source else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        NSAccessibility.post(
            element: window as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Copied.",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(ProcessInfo.processInfo.processName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let copyAllItem = editMenu.addItem(withTitle: "Copy All",
                                           action: #selector(ReaderAppDelegate.copyAll), keyEquivalent: "C")
        copyAllItem.keyEquivalentModifierMask = [.command, .shift]
        copyAllItem.target = self
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        return menu
    }
}
