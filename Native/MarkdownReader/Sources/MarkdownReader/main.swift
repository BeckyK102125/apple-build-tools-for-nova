import AppKit
import MarkdownReaderCore

MainActor.assumeIsolated {
    let delegate: NSApplicationDelegate
    if CommandLine.arguments.contains("--choose") {
        // The list arrives on standard input; an unreadable request exits without a window.
        guard let request = try? ChooserRequest.decode(FileHandle.standardInput.readDataToEndOfFile()) else {
            exit(2)
        }
        delegate = ChooserAppDelegate(request: request)
    } else {
        delegate = ReaderAppDelegate()
    }
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) {
        NSApplication.shared.run()
    }
}
