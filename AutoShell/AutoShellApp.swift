import SwiftUI
import AppKit

@main
struct AutoShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = TaskStore.shared

    var body: some Scene {
        Window("AutoShell", id: ManagerWindow.id) {
            ContentView(store: store)
        }
        .defaultSize(width: 1060, height: 700)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.automatic)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands { SidebarCommands() }

        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuBarStatusLabel(store: store, delegate: delegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openManager: (() -> Void)?
    private var didStart = false

    func configureWindowOpening(_ action: @escaping () -> Void) {
        openManager = action
        guard !didStart else { return }
        didStart = true
        TaskStore.shared.loadAndStart()
        if TaskStore.shared.tasks.isEmpty || TaskStore.shared.errorMessage != nil { action() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openManager?()
        return false
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

enum ManagerWindow {
    static let id = "task-manager"
}

private struct MenuBarStatusLabel: View {
    @Environment(\.openWindow) private var openWindow
    var store: TaskStore
    var delegate: AppDelegate

    var body: some View {
        Label {
            Text(String(localized: "AutoShell · Running: \(store.runningCount)"))
        } icon: {
            Image(store.failedCount > 0 ? "MenuBarIconAlert" : "MenuBarIcon")
                .renderingMode(.template)
        }
        .accessibilityLabel(String(localized: "AutoShell · Running: \(store.runningCount) · Failed: \(store.failedCount)"))
        .task {
            delegate.configureWindowOpening {
                openWindow(id: ManagerWindow.id)
                NSApp.activate()
            }
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
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
                        showManager()
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
        Button(String(localized: "Manage Tasks…")) { showManager() }
            .keyboardShortcut("o")
        Button(String(localized: "Start All")) { store.startAll() }.disabled(store.tasks.isEmpty || store.isQuitting)
        Button(String(localized: "Stop All")) { store.stopAll() }.disabled(!store.hasActiveTasks)
        Divider()
        Text(String(localized: "Tasks keep running when the window closes"))
        Button(String(localized: "Quit AutoShell and Stop Tasks")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func showManager() {
        openWindow(id: ManagerWindow.id)
        NSApp.activate()
    }
}
