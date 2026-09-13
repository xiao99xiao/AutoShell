import Foundation
import AppKit
import Darwin

@main
@MainActor
struct IntegrationTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AutoShell-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw TaskError.message("FAIL: \(message)") }
            print("PASS: \(message)")
        }
        func wait(_ seconds: TimeInterval = 10, until condition: () -> Bool) throws {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            try check(condition(), "condition completed within \(seconds)s")
        }
        func makeTask(_ name: String, _ command: String) -> ShellTask {
            var task = ShellTask()
            task.name = name
            task.command = command
            task.directory = root.path
            task.startsAutomatically = false
            return task
        }
        let store = TaskStore(rootURL: root)
        store.loadAndStart()
        defer {
            store.prepareToQuit()
            let cleanupDeadline = Date().addingTimeInterval(7)
            while store.hasProcesses && Date() < cleanupDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        var task = makeTask("输出与配置", "printf '%s\\n' \"$CUSTOM_VALUE\"; pwd; printf '错误输出\\n' >&2; exit 7")
        task.environment = "CUSTOM_VALUE=中文 空格 ' dollar $ unchanged"
        try store.save(task)
        try check(store.runner(for: task.id).pid == nil, "saving never executes command")
        store.start(task.id)
        let firstPID = store.runner(for: task.id).pid
        store.start(task.id)
        try check(firstPID == store.runner(for: task.id).pid, "duplicate start is ignored")
        try wait { store.runner(for: task.id).pid == nil }
        let output = store.runner(for: task.id)
        try check(output.state == .failed && output.exitCode == 7, "nonzero exit reports failure and code")
        try check(output.log.contains("中文 空格 ' dollar $ unchanged") && output.log.contains(root.path) && output.log.contains("错误输出"), "stdout, stderr, working directory and literal environment captured")
        try check(output.state != .waiting, "failure waits for manual restart by default")
        let restored = TaskStore(rootURL: root)
        restored.loadAndStart()
        try check(restored.tasks == store.tasks, "configuration round trips")
        try check(restored.runner(for: task.id).pid == nil && restored.runner(for: task.id).log.contains("错误输出"), "manual task stays stopped and historical log restores")

        let worker = makeTask("进程树", "trap '' TERM; /bin/sh -c 'trap \"\" TERM; echo $$ > child.pid; while :; do sleep 1; done' & wait")
        try store.save(worker)
        store.start(worker.id)
        let childURL = root.appendingPathComponent("child.pid")
        try wait { FileManager.default.fileExists(atPath: childURL.path) }
        let childPID = Int32(try String(contentsOf: childURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        store.stop(worker.id)
        try check(store.runner(for: worker.id).state == .stopping, "stop transitions immediately")
        try wait(9) { store.runner(for: worker.id).pid == nil }
        try wait(3) { kill(childPID, 0) != 0 }
        try check(store.runner(for: worker.id).state == .stopped, "manual stop is not a failure; stubborn descendants killed")

        let longTask = makeTask("重启", "echo ready; while :; do sleep 1; done")
        try store.save(longTask)
        store.start(longTask.id)
        let oldPID = store.runner(for: longTask.id).pid
        store.restart(longTask.id)
        try wait { let pid = store.runner(for: longTask.id).pid; return pid != nil && pid != oldPID }
        try check(kill(oldPID!, 0) != 0, "restart finishes previous process before replacement")
        do { try store.save(longTask); throw TaskError.message("active edit accepted") }
        catch { try check(error.localizedDescription == String(localized: "Stop the task before editing its configuration."), "active task edits rejected") }
        store.restart(longTask.id)
        store.stop(longTask.id)
        try wait { store.runner(for: longTask.id).pid == nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        try check(store.runner(for: longTask.id).pid == nil, "stop cancels a pending manual restart")

        var auto = makeTask("自动恢复", "exit 3")
        auto.restartsOnFailure = true
        try store.save(auto)
        store.start(auto.id)
        try wait { store.runner(for: auto.id).state == .waiting }
        store.stop(auto.id)
        RunLoop.main.run(until: Date().addingTimeInterval(5.5))
        try check(store.runner(for: auto.id).state == .stopped && store.runner(for: auto.id).pid == nil, "manual stop cancels backoff restart")
        store.start(auto.id)
        let autoDate = store.runner(for: auto.id).startedAt
        try wait(8) { store.runner(for: auto.id).startedAt != autoDate }
        store.stop(auto.id)
        try wait { store.runner(for: auto.id).pid == nil }

        // Older tasks have no restartInterval key and must keep loading unchanged.
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(longTask)) as! [String: Any]
        legacyObject.removeValue(forKey: "restartInterval")
        let legacy = try JSONDecoder().decode(ShellTask.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        try check(legacy.restartInterval == nil, "legacy configuration defaults to no scheduled restart")

        let decimalInterval = try ShellTask.parseRestartInterval("1,5", unit: 3600, locale: Locale(identifier: "de_DE"))
        try check(decimalInterval == 5400, "localized decimal intervals parse correctly")
        for invalidText in ["2abc", "2 3", "", "nan", "-1"] {
            do {
                _ = try ShellTask.parseRestartInterval(invalidText, unit: 60)
                throw TaskError.message("invalid interval text accepted")
            } catch {
                try check(error.localizedDescription == String(localized: "Enter a valid interval of at least 1 second."), "invalid interval text is rejected in full")
            }
        }

        let periodic = makeTask("Periodic restart", "echo periodic-ready; while :; do sleep 1; done")
        try store.save(periodic)
        store.start(periodic.id)
        let beforeSchedulePID = store.runner(for: periodic.id).pid
        try store.setRestartInterval(periodic.id, interval: 1)
        try check(store.runner(for: periodic.id).pid == beforeSchedulePID, "setting a schedule leaves the current process running")
        let persistedSchedule = TaskStore(rootURL: root)
        persistedSchedule.loadAndStart()
        try check(persistedSchedule.tasks.first { $0.id == periodic.id }?.restartInterval == 1, "per-task interval persists")
        try check(persistedSchedule.scheduledRestarts[periodic.id] == nil, "stopped tasks do not arm timers when configuration loads")
        try wait(4) { let pid = store.runner(for: periodic.id).pid; return pid != nil && pid != beforeSchedulePID }
        try check(kill(beforeSchedulePID!, 0) != 0, "scheduled restart waits for the previous process to exit")
        let secondPeriodicPID = store.runner(for: periodic.id).pid
        try wait(4) { let pid = store.runner(for: periodic.id).pid; return pid != nil && pid != secondPeriodicPID }
        try check(store.runner(for: periodic.id).log.components(separatedBy: String(localized: "Scheduled restart is due.")).count >= 3, "scheduled restart repeats and records its reason")
        try store.setRestartInterval(periodic.id, interval: nil)
        let disabledPID = store.runner(for: periodic.id).pid
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        try check(store.scheduledRestarts[periodic.id] == nil && store.runner(for: periodic.id).pid == disabledPID, "disabling the schedule cancels the timer without stopping the task")
        try store.setRestartInterval(periodic.id, interval: 1)
        store.stop(periodic.id)
        try wait { store.runner(for: periodic.id).pid == nil }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        try check(store.scheduledRestarts[periodic.id] == nil && store.runner(for: periodic.id).pid == nil, "manual stop cancels scheduled work")
        try check(store.tasks.first { $0.id == periodic.id }?.restartInterval == 1, "manual stop preserves the interval for next start")
        store.start(periodic.id)
        try check(store.scheduledRestarts[periodic.id] != nil, "starting the task resumes its periodic schedule")
        // Cancel an already due restart while the old process is still shutting down.
        let beforeCancellationDate = store.runner(for: periodic.id).startedAt
        try wait(4) { store.runner(for: periodic.id).state == .stopping }
        store.stop(periodic.id)
        try wait { store.runner(for: periodic.id).pid == nil }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        try check(store.runner(for: periodic.id).startedAt == beforeCancellationDate, "stop during a scheduled restart prevents the replacement process")

        try store.setRestartInterval(task.id, interval: 1)
        store.start(task.id)
        try wait { store.runner(for: task.id).state == .failed }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        try check(store.runner(for: task.id).state == .failed && store.scheduledRestarts[task.id] == nil, "periodic schedule respects manual failure recovery")
        for invalidInterval in [0, -1, Double.infinity, Double.nan, 1e100] {
            do {
                try store.setRestartInterval(periodic.id, interval: invalidInterval)
                throw TaskError.message("invalid restart interval accepted")
            } catch {
                try check(error.localizedDescription == String(localized: "Enter a valid interval of at least 1 second."), "invalid restart interval is rejected")
            }
        }
        try check(store.tasks.first { $0.id == periodic.id }?.restartInterval == 1, "invalid interval leaves the saved configuration intact")

        var atLaunch = makeTask("启动自动运行", "echo autostart")
        atLaunch.startsAutomatically = true
        try store.save(atLaunch)
        let relaunch = TaskStore(rootURL: root)
        relaunch.loadAndStart()
        try wait { relaunch.runner(for: atLaunch.id).state == .succeeded }
        try check(relaunch.runner(for: atLaunch.id).log.contains("autostart"), "configured task runs when app loads")

        let noisy = makeTask("日志轮转", "/usr/bin/head -c 12000000 /dev/zero | /usr/bin/tr '\\0' x; echo END_OF_LOG")
        try store.save(noisy)
        store.start(noisy.id)
        try wait(30) { store.runner(for: noisy.id).pid == nil }
        let noiseRunner = store.runner(for: noisy.id)
        try check(noiseRunner.log.contains("END_OF_LOG") && noiseRunner.log.utf8.count <= 128 * 1024 + 4, "high-volume logs keep bounded tail and final output")
        for url in [noiseRunner.logURL, noiseRunner.logURL.appendingPathExtension("1")] {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber).uint64Value
            try check(size <= 5 * 1024 * 1024, "rotated log remains below 5 MB")
        }

        let orphan = makeTask("Shell 提前退出", "sleep 90 & echo $! > orphan.pid; exit 0")
        try store.save(orphan)
        store.start(orphan.id)
        try wait { store.runner(for: orphan.id).state == .succeeded }
        let orphanPID = Int32(try String(contentsOf: root.appendingPathComponent("orphan.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        try wait(3) { kill(orphanPID, 0) != 0 }

        store.start(longTask.id)
        store.start(worker.id)
        store.start(periodic.id)
        store.prepareToQuit()
        try wait(9) { !store.hasProcesses }
        try check(!store.hasActiveTasks, "quit stops all owned tasks")
        try check(store.scheduledRestarts.isEmpty, "quit cancels all periodic schedules")
        store.start(longTask.id)
        try check(!store.hasProcesses, "no new process can launch during quit")

        var invalid = makeTask("无效目录", "echo should-not-run")
        invalid.directory = root.appendingPathComponent("missing").path
        do { _ = try invalid.validated(); throw TaskError.message("invalid directory accepted") }
        catch { try check(error.localizedDescription == String(localized: "The working directory does not exist. Choose another directory."), "invalid working directory rejected") }

        let corruptRoot = root.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corruptURL = corruptRoot.appendingPathComponent("tasks.json")
        try Data("not json".utf8).write(to: corruptURL)
        let corrupt = TaskStore(rootURL: corruptRoot)
        corrupt.loadAndStart()
        try check(corrupt.errorMessage != nil && corrupt.tasks.isEmpty, "corrupt config surfaces error")
        do { try corrupt.save(task) } catch { }
        let preserved = try String(contentsOf: corruptURL, encoding: .utf8)
        try check(preserved == "not json", "corrupt config is not overwritten")
        print("All integration tests passed.")
    }
}
