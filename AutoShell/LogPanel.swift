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
                Text("运行日志").font(.headline)
                Spacer()
                Button(pausedLog == nil ? "暂停显示" : "继续显示", systemImage: pausedLog == nil ? "pause" : "play") {
                    pausedLog = pausedLog == nil ? runner.log : nil
                }
                .help("只暂停画面，任务和日志记录继续运行")
                Button("在 Terminal 查看", systemImage: "arrow.up.forward.app", action: terminal)
                    .disabled(runner.log.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
            HStack(spacing: 14) {
                TextField("搜索日志", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("搜索日志")
                Toggle("跟随输出", isOn: $follows).toggleStyle(.checkbox).fixedSize()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(visibleLog, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("复制当前显示的日志").accessibilityLabel("复制日志")
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
            if runner.log.isEmpty {
                ContentUnavailableView("还没有输出", systemImage: "text.alignleft", description: Text("启动任务后，标准输出和错误信息会出现在这里。"))
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
                Text(pausedLog != nil ? "显示已暂停 · 后台仍在记录" : "最近 128 KB · 本地日志自动轮转（2 × 5 MB）")
                Spacer()
                Text("只读输出").help("需要交互输入的命令请在 Terminal 中运行")
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
