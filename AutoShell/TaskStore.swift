import AppKit
import Observation

@MainActor @Observable
final class TaskStore {
    static let shared = TaskStore()
    private(set) var tasks: [ShellTask] = []
    var selectedID: UUID?
    var errorMessage: String?
    private(set) var isQuitting = false
    @ObservationIgnored private var runners: [UUID: TaskRunner] = [:]
    @ObservationIgnored private var pendingRestarts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var failureCounts: [UUID: Int] = [:]
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var configurationReadable = true
    let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AutoShell", isDirectory: true)
    }

    var runningCount: Int { runners.values.filter { $0.state == .running }.count }
    var hasActiveTasks: Bool { runners.values.contains { $0.state.isActive } }
    var hasProcesses: Bool { runners.values.contains { $0.pid != nil } }
    var failedCount: Int { runners.values.filter { $0.state == .failed }.count }
    var selectedTask: ShellTask? { tasks.first { $0.id == selectedID } }

    func loadAndStart() {
        guard !loaded else { return }
        loaded = true
        let url = rootURL.appendingPathComponent("tasks.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                tasks = try JSONDecoder().decode([ShellTask].self, from: Data(contentsOf: url))
                guard Set(tasks.map(\.id)).count == tasks.count else { throw TaskError.message("任务 ID 重复。") }
            }
            for task in tasks { _ = runner(for: task.id) }
            selectedID = tasks.first?.id
            for task in tasks where task.startsAutomatically { start(task.id) }
        } catch {
            tasks = []
            configurationReadable = false
            errorMessage = "无法读取任务配置，原文件已保留。请检查 \(url.path)：\(error.localizedDescription)"
        }
    }

    func runner(for id: UUID) -> TaskRunner {
        if let existing = runners[id] { return existing }
        let runner = TaskRunner(logURL: rootURL.appendingPathComponent("Logs/\(id.uuidString).log"))
        runner.onExit = { [weak self] failed in self?.didExit(id, failed: failed) }
        runners[id] = runner
        return runner
    }

    func save(_ task: ShellTask) throws {
        let task = try task.validated()
        guard !runner(for: task.id).state.isActive else { throw TaskError.message("请先停止任务，再修改配置。") }
        var updated = tasks
        if let index = updated.firstIndex(where: { $0.id == task.id }) { updated[index] = task }
        else { updated.append(task) }
        try persist(updated)
        tasks = updated
        selectedID = task.id
    }

    func delete(_ id: UUID) {
        guard !runner(for: id).state.isActive else { return }
        do {
            let updated = tasks.filter { $0.id != id }
            try persist(updated)
            tasks = updated
            runners[id] = nil
            if selectedID == id { selectedID = tasks.first?.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func start(_ id: UUID) {
        guard !isQuitting, let task = tasks.first(where: { $0.id == id }) else { return }
        let runner = runner(for: id)
        guard runner.pid == nil else { return }
        cancelRestart(id)
        do { try runner.start(task) }
        catch { runner.markFailure(error) }
    }

    func stop(_ id: UUID) {
        cancelRestart(id)
        failureCounts[id] = nil
        runner(for: id).stop()
    }

    func restart(_ id: UUID) {
        guard !isQuitting else { return }
        stop(id)
        if runner(for: id).pid == nil { start(id); return }
        pendingRestarts[id] = Task { [weak self] in
            while let self, self.runner(for: id).pid != nil {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.start(id)
        }
    }

    func startAll() { for task in tasks where !runner(for: task.id).state.isActive { start(task.id) } }
    func stopAll() { for task in tasks { stop(task.id) } }
    func prepareToQuit() { isQuitting = true; stopAll() }

    func openTerminalLog(_ id: UUID) {
        let logURL = runner(for: id).logURL
        do {
            let directory = rootURL.appendingPathComponent("Terminal", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = directory.appendingPathComponent("\(id.uuidString).command")
            let quote = "'" + logURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let text = "#!/bin/sh\nprintf '%s\\n' 'AutoShell · 实时日志（只读，按 Control-C 结束查看）'\nexec /usr/bin/tail -n 200 -F \(quote)\n"
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                throw TaskError.message("未找到 Terminal。")
            }
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: .init()) { _, error in
                if let error { Task { @MainActor in self.errorMessage = error.localizedDescription } }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func revealLogs(_ id: UUID) {
        let url = runner(for: id).logURL
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { errorMessage = "任务还没有日志。启动一次任务后即可查看日志文件。" }
    }

    private func didExit(_ id: UUID, failed: Bool) {
        guard failed, !isQuitting, let task = tasks.first(where: { $0.id == id }), task.restartsOnFailure else { return }
        let runner = runner(for: id)
        if let startedAt = runner.startedAt, Date().timeIntervalSince(startedAt) > 60 { failureCounts[id] = 0 }
        let attempts = min((failureCounts[id] ?? 0) + 1, 5)
        failureCounts[id] = attempts
        let delay = min(5 * (1 << (attempts - 1)), 60)
        runner.markWaiting()
        pendingRestarts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.start(id)
        }
    }

    private func cancelRestart(_ id: UUID) {
        pendingRestarts.removeValue(forKey: id)?.cancel()
    }

    private func persist(_ tasks: [ShellTask]) throws {
        guard configurationReadable else { throw TaskError.message("原配置无法读取，已阻止覆盖。请先修复 tasks.json 并重启 App。") }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = rootURL.appendingPathComponent("tasks.json")
        try encoder.encode(tasks).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
