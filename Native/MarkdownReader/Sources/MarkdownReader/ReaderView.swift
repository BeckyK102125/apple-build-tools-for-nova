import MarkdownReaderCore
import SwiftUI

struct ReaderView: View {
    let model: ReaderModel
    let onCopyAll: () -> Void

    @Namespace private var headingRotor
    @AccessibilityFocusState private var focusedHeading: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Copy All", action: onCopyAll)
                    .accessibilityHint("Copies the whole document.")
            }
            .padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array((model.document?.displayBlocks ?? []).enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Fresh accessibility elements for each document, so focus can land on the new first heading.
                .id(model.revision)
                // Mac VoiceOver lists headings only from an app-supplied rotor (VoiceOver Test G2).
                .accessibilityRotor("Headings") {
                    ForEach(model.document?.headings ?? []) { heading in
                        AccessibilityRotorEntry(Text(heading.text), id: heading.id, in: headingRotor)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .onChange(of: model.revision, initial: true) { _, _ in
            let first = model.document?.headings.first?.id
            // Heading ids restart at 1 per document; clear first so setting focus is always a change,
            // and wait until the window is key so activation does not take focus back.
            focusedHeading = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                focusedHeading = first
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block {
        case let .heading(id, level, text):
            Text(text)
                .font(level == 1 ? .title : level == 2 ? .title2 : .title3)
                .bold()
                .accessibilityAddTraits(.isHeader)
                .accessibilityRotorEntry(id: id, in: headingRotor)
                .accessibilityFocused($focusedHeading, equals: id)
        case let .paragraph(text):
            Text(text).textSelection(.enabled)
        case let .code(text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
