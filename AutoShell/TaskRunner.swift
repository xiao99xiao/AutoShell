import Foundation
import Observation
import Darwin

/// Each command owns a process group. Background children in that group are stopped with it.
@MainActor @Observable
final class TaskRunner {
    private(set) var state: RunState = .stopped
    private(set) var pid: pid_t?
    private(set) var startedAt: Date?
    private(set) var exitCode: Int32?
    private(set) var log = ""
    private(set) var logRevision = 0
    private(set) var logError: String?
    let logURL: URL
    @ObservationIgnored var onExit: ((Bool) -> Void)?
    @ObservationIgnored private var readFD: Int32 = -1
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var outputSource: DispatchSourceRead?
    @ObservationIgnored private var needsPublish = false
    @ObservationIgnored private var reachedEOF = false
    @ObservationIgnored private var stopDeadline: Date?
    @ObservationIgnored private var wasStopped = false
    @ObservationIgnored private var diskHandle: FileHandle?
    @ObservationIgnored private var diskBytes: UInt64 = 0
    @ObservationIgnored private var tail = Data()
    private let diskLimit: UInt64 = 5 * 1024 * 1024
    private let tailLimit = 128 * 1024

    init(logURL: URL) {
        self.logURL = logURL
        if let handle = try? FileHandle(forReadingFrom: logURL) {
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > UInt64(tailLimit) ? size - UInt64(tailLimit) : 0)
            tail = (try? handle.readToEnd()) ?? Data()
            try? handle.close()
            log = String(decoding: tail, as: UTF8.self)
        }
    }

    func start(_ task: ShellTask) throws {
        guard pid == nil else { return }
        let task = try task.validated()
        try prepareLog()
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw posixError(errno) }
        defer { close(descriptors[1]) }
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        _ = fcntl(descriptors[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(descriptors[1], F_SETFD, FD_CLOEXEC)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        posix_spawn_file_actions_addclose(&actions, descriptors[1])
        posix_spawn_file_actions_addchdir(&actions, task.expandedDirectory)
        posix_spawnattr_setpgroup(&attributes, 0)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGPIPE, SIGHUP, SIGQUIT] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment.merge(try task.environmentValues()) { _, new in new }
        let argumentStrings: [String] = [task.shell, "-l", "-c", task.command]
        let args: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) } + [nil]
        let env: [UnsafeMutablePointer<CChar>?] = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { args.forEach { free($0) }; env.forEach { free($0) } }
        var child: pid_t = 0
        let result = args.withUnsafeBufferPointer { argv in
            env.withUnsafeBufferPointer { envp in
                posix_spawn(&child, task.shell, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard result == 0 else { close(descriptors[0]); throw posixError(result) }
        readFD = descriptors[0]
        reachedEOF = false
        pid = child
        startedAt = Date()
        exitCode = nil
        state = .running
        wasStopped = false
        stopDeadline = nil
        let message = String(localized: "Started PID \(child)")
        append(Data("\n── \(Date().formatted()) · \(message) ──\n".utf8))
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        // The descriptor must close only after the source stops observing it.
        let ownedFD = readFD
        source.setCancelHandler { close(ownedFD) }
        outputSource = source
        source.resume()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        guard let pid else { state = .stopped; return }
        guard state != .stopping else { return }
        wasStopped = true
        state = .stopping
        stopDeadline = Date().addingTimeInterval(5)
        kill(-pid, SIGTERM)
        let message = String(localized: "Stopping; remaining processes will be forced to quit after 5 seconds.")
        append(Data("\n[AutoShell] \(message)\n".utf8))
    }

    func markWaiting() { state = .waiting }
    func markFailure(_ error: Error) {
        state = .failed
        append(Data("\n[AutoShell] \(error.localizedDescription)\n".utf8))
    }

    private func poll() {
        guard let pid else { return }
        drain()
        publishLog()
        if let deadline = stopDeadline, Date() >= deadline { kill(-pid, SIGKILL) }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        guard result == pid else { return }
        // A shell exiting must not leave its background workers behind.
        kill(-pid, SIGKILL)
        drain()
        outputSource?.cancel()
        outputSource = nil
        readFD = -1
        timer?.invalidate()
        timer = nil
        self.pid = nil
        stopDeadline = nil
        let signal = status & 0x7f
        let code = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        exitCode = code
        let failed = !wasStopped && code != 0
        state = wasStopped ? .stopped : (failed ? .failed : .succeeded)
        let message = String(localized: "\(state.label) · Exit code \(code)")
        append(Data("\n[AutoShell] \(message)\n".utf8))
        try? diskHandle?.close()
        diskHandle = nil
        onExit?(failed)
    }

    private func drain() {
        guard !reachedEOF, readFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var batch = Data()
        // Bound work per tick: noisy tasks exert pipe backpressure, not unbounded memory growth.
        for _ in 0..<16 {
            let count = read(readFD, &buffer, buffer.count)
            if count > 0 { batch.append(contentsOf: buffer.prefix(count)) }
            else if count == 0 { reachedEOF = true; outputSource?.cancel(); break }
            else if count < 0 && errno == EINTR { continue }
            else { break }
        }
        if !batch.isEmpty { append(batch, publish: false) }
    }

    private func prepareLog() throws {
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: logURL.path) {
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw TaskError.message(String(localized: "Could not create the log file. Check directory permissions."))
            }
        }
        diskHandle = try FileHandle(forWritingTo: logURL)
        diskBytes = try diskHandle!.seekToEnd()
        logError = nil
    }

    private func append(_ data: Data, publish: Bool = true) {
        tail.append(data)
        if tail.count > tailLimit { tail.removeFirst(tail.count - tailLimit) }
        needsPublish = true
        if publish { publishLog() }
        do {
            if diskHandle == nil { try prepareLog() }
            if diskBytes + UInt64(data.count) > diskLimit {
                try diskHandle?.close()
                diskHandle = nil
                let archive = logURL.appendingPathExtension("1")
                if FileManager.default.fileExists(atPath: archive.path) { try FileManager.default.removeItem(at: archive) }
                try FileManager.default.moveItem(at: logURL, to: archive)
                try prepareLog()
            }
            try diskHandle?.write(contentsOf: data)
            diskBytes += UInt64(data.count)
        } catch { logError = String(localized: "Could not write the log: \(error.localizedDescription)") }
    }

    private func publishLog() {
        guard needsPublish else { return }
        log = String(decoding: tail, as: UTF8.self)
        logRevision += 1
        needsPublish = false
    }

    private func posixError(_ code: Int32) -> Error {
        TaskError.message(String(cString: strerror(code)))
    }
}
