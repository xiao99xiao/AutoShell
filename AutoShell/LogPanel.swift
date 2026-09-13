import SwiftUI
import AppKit

struct LogPanel: View {
    var runner: TaskRunner
    let terminal: () -> Void
    @State private var search = ""
    @State private var follows = true
    @State private var pausedLog: String?

    private var visibleLog: String {
        let text = pausedLog ?? runner.log
        guard !search.isEmpty else { return text }
        return text.components(separatedBy: .newlines).filter { $0.localizedCaseInsensitiveContains(search) }.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(localized: "Logs")).font(.headline)
                Spacer()
                Button(pausedLog == nil ? String(localized: "Pause Display") : String(localized: "Resume Display"), systemImage: pausedLog == nil ? "pause" : "play") {
                    pausedLog = pausedLog == nil ? runner.log : nil
                }
                .help(String(localized: "Pauses the display only. The task and log recording continue."))
                Button(String(localized: "View in Terminal"), systemImage: "arrow.up.forward.app", action: terminal)
                    .disabled(runner.log.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
            HStack(spacing: 14) {
                TextField(String(localized: "Search logs"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Search logs"))
                Toggle(String(localized: "Follow Output"), isOn: $follows).toggleStyle(.checkbox).fixedSize()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(visibleLog, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help(String(localized: "Copy the displayed log")).accessibilityLabel(String(localized: "Copy Log"))
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
            if runner.log.isEmpty {
                ContentUnavailableView(String(localized: "No output yet"), systemImage: "text.alignleft", description: Text(String(localized: "Start the task to see standard output and errors here.")))
                    .frame(maxHeight: .infinity)
            } else if visibleLog.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxHeight: .infinity)
            } else {
                LogTextView(text: visibleLog, follows: follows && pausedLog == nil)
                    .padding(.horizontal, 16)
            }
            if let error = runner.logError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            HStack {
                Text(pausedLog != nil ? String(localized: "Display paused · Still recording") : String(localized: "Latest 128 KB · Rotating logs (2 × 5 MB)"))
                Spacer()
                Text(String(localized: "Read-only output")).help(String(localized: "Run commands that need interactive input in Terminal"))
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }
}

/// NSTextView keeps large logs selectable and avoids a SwiftUI view per log line.
struct LogTextView: NSViewRepresentable {
    let text: String
    let follows: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .textColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let origin = scroll.contentView.bounds.origin
        view.string = text
        if follows { view.scrollToEndOfDocument(nil) }
        else { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
    }
}
