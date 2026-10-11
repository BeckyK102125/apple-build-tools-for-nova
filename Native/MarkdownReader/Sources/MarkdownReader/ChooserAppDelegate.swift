import AppKit
import MarkdownReaderCore
import SwiftUI

/// Chooser mode: shows one accessible list, writes the answer to standard output, and quits.
@MainActor
final class ChooserAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let request: ChooserRequest
    private var window: NSWindow?
    private var finished = false

    init(request: ChooserRequest) {
        self.request = request
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMenu()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = request.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ChooserView(
            request: request,
            onChoose: { [weak self] index in self?.finish(.chosen(index)) },
            onCancel: { [weak self] in self?.finish(.cancelled) }
        ))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    // Command-Q still answers "cancelled", so the extension never mistakes a quit for a failure.
    func applicationWillTerminate(_ notification: Notification) {
        if !finished {
            finished = true
            FileHandle.standardOutput.write(ChooserResult.cancelled.encoded() + Data("\n".utf8))
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(.cancelled)
    }

    private func finish(_ result: ChooserResult) {
        guard !finished else { return }
        finished = true
        FileHandle.standardOutput.write(result.encoded() + Data("\n".utf8))
        NSApplication.shared.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        return menu
    }
}

struct ChooserView: View {
    let request: ChooserRequest
    let onChoose: (Int) -> Void
    let onCancel: () -> Void

    @State private var selection: Int? = 0
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title)
                .font(.title2)
                .bold()
                .accessibilityAddTraits(.isHeader)
            List(selection: $selection) {
                ForEach(Array(request.items.enumerated()), id: \.offset) { index, item in
                    Text(item).tag(index)
                }
            }
            .focused($listFocused)
            .accessibilityLabel(request.title)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Choose") {
                    if let selection { onChoose(selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
        .onAppear { listFocused = true }
    }
}
