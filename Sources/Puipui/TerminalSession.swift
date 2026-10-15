import AppKit
import GhosttyTerminal
import TerminalPTY

@MainActor
final class TerminalSession {
    private(set) var pid: pid_t = -1
    private var master: Int32 = -1
    private var pending = Data()
    private var timer: Timer?
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var stoppingAt: TimeInterval?
    private var foregroundGroup: pid_t = -1
    private(set) var exitCode: Int32?
    var onData: (Data) -> Void = { _ in }
    var onExit: (Int32, UInt64) -> Void = { _, _ in }

    func start() {
        pid = terminal_spawn(&master, NSHomeDirectory())
        guard pid > 0 else { exitCode = 127; onExit(127, 0); return }
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func send(_ data: Data) {
        guard master >= 0, exitCode == nil else { return }
        pending.append(data)
    }

    func resize(columns: UInt16, rows: UInt16) {
        guard master >= 0 else { return }
        _ = terminal_resize(master, columns, rows)
    }

    func stop() {
        guard pid > 0, exitCode == nil, stoppingAt == nil else { return }
        foregroundGroup = tcgetpgrp(master)
        stoppingAt = ProcessInfo.processInfo.systemUptime
        signalGroups(SIGHUP)
    }

    private func signalGroups(_ signal: Int32) {
        if foregroundGroup > 0, foregroundGroup != pid { kill(-foregroundGroup, signal) }
        kill(-pid, signal)
    }

    private func poll() {
        guard master >= 0 else { return }
        if let stoppingAt {
            let elapsed = ProcessInfo.processInfo.systemUptime - stoppingAt
            if elapsed > 2 { signalGroups(SIGKILL) }
            else if elapsed > 1 { signalGroups(SIGTERM) }
        }
        if !pending.isEmpty {
            let written = pending.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
            if written > 0 { pending.removeFirst(written) }
        }
        var bytes = [UInt8](repeating: 0, count: 8192)
        for _ in 0..<32 {
            let count = Darwin.read(master, &bytes, bytes.count)
            if count <= 0 { break }
            onData(Data(bytes.prefix(count)))
        }
        var code: Int32 = 0
        if terminal_wait(pid, &code) == 1 {
            timer?.invalidate()
            timer = nil
            close(master)
            master = -1
            exitCode = code
            onExit(code, UInt64(max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1000))
        }
    }
}

@MainActor
final class SideTerminal: NSViewController, TerminalSurfaceCloseDelegate {
    let pty = TerminalSession()
    let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))
    var onClose: () -> Void = {}
    var onExit: () -> Void = {}
    var receivedText = ""
    private lazy var session = InMemoryTerminalSession(
        write: { [weak self] data in DispatchQueue.main.async { self?.pty.send(data) } },
        resize: { [weak self] size in DispatchQueue.main.async { self?.pty.resize(columns: size.columns, rows: size.rows) } }
    )
    private let controller = TerminalController(theme: TerminalTheme()) { builder in
        builder.withBackground("292d31")
        builder.withForeground("f5f2eb")
        builder.withFontFamily("SF Mono")
        builder.withFontSize(12)
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 379))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.16, green: 0.176, blue: 0.192, alpha: 1).cgColor
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        let close = NSButton(title: "CLOSE", target: self, action: #selector(closePanel))
        close.isBordered = false
        close.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        close.contentTintColor = .white
        close.translatesAutoresizingMaskIntoConstraints = false
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.delegate = self
        terminal.configuration = TerminalSurfaceOptions(backend: .inMemory(session), waitAfterCommand: true, context: .window)
        terminal.controller = controller
        view.addSubview(terminal)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            close.heightAnchor.constraint(equalToConstant: 24),
            terminal.topAnchor.constraint(equalTo: view.topAnchor, constant: 36),
            terminal.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        pty.onData = { [weak self] data in
            guard let self else { return }
            if CommandLine.arguments.contains("--check-terminal") {
                receivedText += String(decoding: data, as: UTF8.self)
            }
            session.receive(data)
        }
        pty.onExit = { [weak self] code, runtime in
            self?.session.finish(exitCode: UInt32(code), runtimeMilliseconds: runtime)
            self?.onExit()
        }
    }

    override func viewDidLayout() { super.viewDidLayout(); terminal.fitToSize() }
    @objc private func closePanel() { onClose() }
    func terminalDidClose(processAlive: Bool) { onClose() }
}
