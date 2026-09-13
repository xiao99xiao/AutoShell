import SwiftUI

struct ContentView: View {
    @Bindable var store: TaskStore
    @State private var editingTask: ShellTask?
    @State private var deletingTask: ShellTask?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                Section(String(localized: "Tasks · \(store.tasks.count)")) {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task, runner: store.runner(for: task.id))
                            .tag(task.id)
                            .contextMenu {
                                Button(String(localized: "Start")) { store.start(task.id) }.disabled(store.runner(for: task.id).state.isActive)
                                Button(String(localized: "Stop")) { store.stop(task.id) }.disabled(!store.runner(for: task.id).state.isActive)
                                Button(String(localized: "Edit…")) { editingTask = task }.disabled(store.runner(for: task.id).state.isActive)
                                Button(String(localized: "Delete…"), role: .destructive) { deletingTask = task }.disabled(store.runner(for: task.id).state.isActive)
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(String(localized: "Running tasks: \(store.runningCount)")).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(store.runningCount > 0 ? .green : .secondary)
                    }
                    .font(.caption)
                    Text(String(localized: "Tasks keep running when this window closes.\nReturn from the menu bar anytime."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(String(localized: "Open Login Items Settings"), systemImage: "arrow.up.forward.app") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                    .font(.caption).buttonStyle(.link)
                    .help(String(localized: "Add AutoShell to your login items manually"))
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
                    Label(store.tasks.isEmpty ? String(localized: "Keep commands running. Free your Terminal.") : String(localized: "Select a task"), systemImage: "terminal")
                } description: {
                    Text(store.tasks.isEmpty ? String(localized: "Add GitHub runners, development servers, or other long-running commands.\nThey can start automatically the next time AutoShell opens.") : String(localized: "Check status, manage tasks, and read logs."))
                } actions: {
                    Button(String(localized: "Add Your First Task"), systemImage: "plus") { editingTask = ShellTask() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("AutoShell")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Add Task"), systemImage: "plus") { editingTask = ShellTask() }
                    .help(String(localized: "Add Task ⌘N"))
                    .keyboardShortcut("n")
                    .accessibilityIdentifier("addTask")
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task, isNew: !store.tasks.contains(where: { $0.id == task.id })) { try store.save($0) }
        }
        .alert(String(localized: "Delete task?"), isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button(String(localized: "Cancel"), role: .cancel) { deletingTask = nil }
            Button(String(localized: "Delete"), role: .destructive) {
                if let task = deletingTask { store.delete(task.id) }
                deletingTask = nil
            }
        } message: { Text(String(localized: "Delete the configuration for “\(deletingTask?.name ?? "")”? Existing logs will stay on this Mac.")) }
        .alert(String(localized: "Action could not be completed"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(String(localized: "OK")) { store.errorMessage = nil }
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
                        Image(systemName: "bolt.fill").help(String(localized: "Starts with the app"))
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
    @State private var showingRestartSchedule = false

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
                            if let code = runner.exitCode { Text(String(localized: "Exit code \(code)")).foregroundStyle(.secondary) }
                        }
                        .font(.callout)
                    }
                    Spacer()
                    Menu {
                        Button(String(localized: "Edit Task…"), action: edit).disabled(runner.state.isActive)
                        Button(String(localized: "Show Log in Finder")) { store.revealLogs(task.id) }
                        Divider()
                        Button(String(localized: "Delete Task…"), role: .destructive, action: delete).disabled(runner.state.isActive)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help(String(localized: "More Actions"))
                }
                HStack(spacing: 10) {
                    if runner.state.isActive {
                        Button(String(localized: "Stop"), systemImage: "stop.fill") { store.stop(task.id) }
                            .disabled(runner.state == .stopping)
                        Button(String(localized: "Restart"), systemImage: "arrow.clockwise") { store.restart(task.id) }
                            .disabled(runner.state == .stopping)
                    } else {
                        Button(String(localized: "Start Task"), systemImage: "play.fill") { store.start(task.id) }
                            .buttonStyle(.borderedProminent)
                        Button(String(localized: "Edit"), systemImage: "pencil", action: edit)
                    }
                    Spacer()
                    if let date = runner.startedAt {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(localized: "Started at \(date.formatted(date: .abbreviated, time: .standard))"))
                            if runner.state == .running || runner.state == .stopping {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(String(localized: "Running for \(TaskTimeFormatting.duration(context.date.timeIntervalSince(date)))"))
                                        .monospacedDigit()
                                }
                            }
                        }
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
                        Label(task.startsAutomatically ? String(localized: "Starts with the app") : String(localized: "Manual start"), systemImage: task.startsAutomatically ? "bolt" : "hand.tap")
                        if task.restartsOnFailure { Label(String(localized: "Restart on failure"), systemImage: "arrow.clockwise") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "Automatic Restart"), systemImage: "clock.arrow.circlepath")
                            .font(.callout)
                        if let interval = task.restartIntervalDescription {
                            Text(String(localized: "Every \(interval)"))
                            if let date = store.scheduledRestarts[task.id] {
                                Text(String(localized: "Next restart: \(date.formatted(date: .abbreviated, time: .standard))"))
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(String(localized: "Remaining: \(TaskTimeFormatting.remaining(until: date, now: context.date))"))
                                        .monospacedDigit()
                                }
                            } else {
                                Text(String(localized: "Resumes when the task starts"))
                            }
                        } else {
                            Text(String(localized: "Off"))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(String(localized: "Configure…")) { showingRestartSchedule = true }
                        .disabled(store.isQuitting)
                        .accessibilityIdentifier("configureRestartSchedule")
                }
            }
            .padding(24)
            Divider()
            LogPanel(runner: runner, terminal: { store.openTerminalLog(task.id) })
        }
        .background(.background)
        .sheet(isPresented: $showingRestartSchedule) {
            RestartScheduleEditor(task: task) { try store.setRestartInterval(task.id, interval: $0) }
        }
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
