import SwiftUI
import AppKit

@main
struct AutoShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = TaskStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Label("AutoShell · \(store.runningCount) 个运行中", systemImage: store.failedCount > 0 ? "exclamationmark.square" : "terminal")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TaskStore.shared.loadAndStart()
        if TaskStore.shared.tasks.isEmpty || TaskStore.shared.errorMessage != nil { showManager() }
        NotificationCenter.default.addObserver(self, selector: #selector(showManager), name: .showTaskManager, object: nil)
    }

    @objc func showManager() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "AutoShell"
            window.contentView = NSHostingView(rootView: ContentView(store: TaskStore.shared))
            window.minSize = NSSize(width: 850, height: 560)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = TaskStore.shared
        store.prepareToQuit()
        guard store.hasProcesses else { return .terminateNow }
        Task { @MainActor in
            while store.hasProcesses { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

extension Notification.Name {
    static let showTaskManager = Notification.Name("showTaskManager")
}

struct MenuContent: View {
    var store: TaskStore

    var body: some View {
        Text("AutoShell · \(store.runningCount) 个运行中")
        if store.tasks.isEmpty {
            Text("还没有任务")
        } else {
            ForEach(store.tasks) { task in
                let runner = store.runner(for: task.id)
                Menu("\(task.name) · \(runner.state.label)") {
                    Button("查看日志与详情") {
                        store.selectedID = task.id
                        NotificationCenter.default.post(name: .showTaskManager, object: nil)
                    }
                    if runner.state.isActive {
                        Button("停止") { store.stop(task.id) }.disabled(runner.state == .stopping)
                        Button("重新启动") { store.restart(task.id) }.disabled(runner.state == .stopping)
                    } else {
                        Button("启动") { store.start(task.id) }
                    }
                }
            }
        }
        Divider()
        Button("管理任务…") { NotificationCenter.default.post(name: .showTaskManager, object: nil) }
            .keyboardShortcut("o")
        Button("启动全部") { store.startAll() }.disabled(store.tasks.isEmpty || store.isQuitting)
        Button("停止全部") { store.stopAll() }.disabled(!store.hasActiveTasks)
        Divider()
        Text("关闭窗口后，任务继续运行")
        Button("退出 AutoShell 并停止任务") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
