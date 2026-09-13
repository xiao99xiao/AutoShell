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
            Label {
                Text(String(localized: "AutoShell · Running: \(store.runningCount)"))
            } icon: {
                Image(store.failedCount > 0 ? "MenuBarIconAlert" : "MenuBarIcon")
                    .renderingMode(.template)
            }
            .accessibilityLabel(String(localized: "AutoShell · Running: \(store.runningCount) · Failed: \(store.failedCount)"))
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
        Text(String(localized: "AutoShell · Running: \(store.runningCount)"))
        if store.tasks.isEmpty {
            Text(String(localized: "No tasks yet"))
        } else {
            ForEach(store.tasks) { task in
                let runner = store.runner(for: task.id)
                Menu("\(task.name) · \(runner.state.label)") {
                    Button(String(localized: "View Logs and Details")) {
                        store.selectedID = task.id
                        NotificationCenter.default.post(name: .showTaskManager, object: nil)
                    }
                    if runner.state.isActive {
                        Button(String(localized: "Stop")) { store.stop(task.id) }.disabled(runner.state == .stopping)
                        Button(String(localized: "Restart")) { store.restart(task.id) }.disabled(runner.state == .stopping)
                    } else {
                        Button(String(localized: "Start")) { store.start(task.id) }
                    }
                }
            }
        }
        Divider()
        Button(String(localized: "Manage Tasks…")) { NotificationCenter.default.post(name: .showTaskManager, object: nil) }
            .keyboardShortcut("o")
        Button(String(localized: "Start All")) { store.startAll() }.disabled(store.tasks.isEmpty || store.isQuitting)
        Button(String(localized: "Stop All")) { store.stopAll() }.disabled(!store.hasActiveTasks)
        Divider()
        Text(String(localized: "Tasks keep running when the window closes"))
        Button(String(localized: "Quit AutoShell and Stop Tasks")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
