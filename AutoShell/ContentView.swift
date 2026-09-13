import SwiftUI

struct ContentView: View {
    @Bindable var store: TaskStore
    @State private var editingTask: ShellTask?
    @State private var deletingTask: ShellTask?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Label("AutoShell", image: "MenuBarIcon")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button { editingTask = ShellTask() } label: { Image(systemName: "plus") }
                        .help("添加任务 ⌘N")
                        .keyboardShortcut("n")
                        .accessibilityLabel("添加任务")
                }
                .padding(20)
                List(selection: $store.selectedID) {
                    Section("任务 · \(store.tasks.count)") {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task, runner: store.runner(for: task.id))
                                .tag(task.id)
                                .contextMenu {
                                    Button("启动") { store.start(task.id) }.disabled(store.runner(for: task.id).state.isActive)
                                    Button("停止") { store.stop(task.id) }.disabled(!store.runner(for: task.id).state.isActive)
                                    Button("编辑…") { editingTask = task }.disabled(store.runner(for: task.id).state.isActive)
                                    Button("删除…", role: .destructive) { deletingTask = task }.disabled(store.runner(for: task.id).state.isActive)
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("\(store.runningCount) 个任务运行中").foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(store.runningCount > 0 ? .green : .secondary)
                    }
                    .font(.caption)
                    Text("关闭窗口后继续运行。\n从菜单栏随时回来。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("打开登录项设置", systemImage: "arrow.up.forward.app") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                    .font(.caption).buttonStyle(.link)
                    .help("将 AutoShell 手动添加到系统登录项")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 310)
        } detail: {
            if let task = store.selectedTask {
                TaskDetailView(task: task, runner: store.runner(for: task.id), store: store,
                               edit: { editingTask = task }, delete: { deletingTask = task })
                    .id(task.id)
            } else {
                ContentUnavailableView {
                    Label(store.tasks.isEmpty ? "让命令常驻，让 Terminal 自由" : "选择一个任务", systemImage: "terminal")
                } description: {
                    Text(store.tasks.isEmpty ? "添加 GitHub Runner、开发服务或其他常驻命令。\n下次打开 AutoShell，它们就能自动启动。" : "查看运行状态、管理任务和阅读日志。")
                } actions: {
                    Button("添加第一个任务", systemImage: "plus") { editingTask = ShellTask() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task, isNew: !store.tasks.contains(where: { $0.id == task.id })) { try store.save($0) }
        }
        .alert("删除任务？", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button("取消", role: .cancel) { deletingTask = nil }
            Button("删除", role: .destructive) {
                if let task = deletingTask { store.delete(task.id) }
                deletingTask = nil
            }
        } message: { Text("删除“\(deletingTask?.name ?? "")”的配置。已有日志会保留在本地。") }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .frame(minWidth: 830, minHeight: 530)
    }
}

struct TaskRow: View {
    let task: ShellTask
    var runner: TaskRunner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: runner.state.symbol).foregroundStyle(runner.state.color)
                .frame(width: 16).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(runner.state.label)
                    if task.startsAutomatically {
                        Image(systemName: "bolt.fill").help("随 App 启动")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct TaskDetailView: View {
    let task: ShellTask
    var runner: TaskRunner
    var store: TaskStore
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.name).font(.title.weight(.semibold)).textSelection(.enabled)
                        HStack(spacing: 12) {
                            Label {
                                Text(runner.state.label).foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: runner.state.symbol).foregroundStyle(runner.state.color)
                            }
                            if let pid = runner.pid { Text("PID \(pid)").monospacedDigit().foregroundStyle(.secondary) }
                            if let code = runner.exitCode { Text("退出码 \(code)").foregroundStyle(.secondary) }
                        }
                        .font(.callout)
                    }
                    Spacer()
                    Menu {
                        Button("编辑任务…", action: edit).disabled(runner.state.isActive)
                        Button("在 Finder 中显示日志") { store.revealLogs(task.id) }
                        Divider()
                        Button("删除任务…", role: .destructive, action: delete).disabled(runner.state.isActive)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("更多操作")
                }
                HStack(spacing: 10) {
                    if runner.state.isActive {
                        Button("停止", systemImage: "stop.fill") { store.stop(task.id) }
                            .disabled(runner.state == .stopping)
                        Button("重新启动", systemImage: "arrow.clockwise") { store.restart(task.id) }
                            .disabled(runner.state == .stopping)
                    } else {
                        Button("启动任务", systemImage: "play.fill") { store.start(task.id) }
                            .buttonStyle(.borderedProminent)
                        Button("编辑", systemImage: "pencil", action: edit)
                    }
                    Spacer()
                    if let date = runner.startedAt {
                        Text("启动于 \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.command).font(.system(.callout, design: .monospaced))
                        .lineLimit(3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label(task.directory, systemImage: "folder")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(task.expandedDirectory)
                    HStack(spacing: 16) {
                        Label(task.startsAutomatically ? "随 App 启动" : "手动启动", systemImage: task.startsAutomatically ? "bolt" : "hand.tap")
                        if task.restartsOnFailure { Label("失败后自动重启", systemImage: "arrow.clockwise") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(24)
            Divider()
            LogPanel(runner: runner, terminal: { store.openTerminalLog(task.id) })
        }
        .background(.background)
    }
}

extension RunState {
    var color: Color {
        switch self {
        case .running, .succeeded: .green
        case .failed: .red
        case .stopping, .waiting: .orange
        case .stopped: .secondary
        }
    }
    var symbol: String {
        switch self {
        case .running: "play.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .stopping: "stop.circle"
        case .waiting: "clock.arrow.circlepath"
        case .stopped: "stop.circle"
        }
    }
}
