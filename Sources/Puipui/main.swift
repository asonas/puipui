import AppKit
import SwiftUI
import GhosttyTerminal
import QuartzCore

final class MenuPanel: NSPanel {
    var dismissOverlay: () -> Bool = { false }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, dismissOverlay() { return }
        super.sendEvent(event)
    }
}

@MainActor
final class GripView: NSView {
    var onDetach: ((NSPoint) -> Void)?
    var onDragStarted: () -> Void = {}
    private var moving = false
    var detached = false { didSet { needsDisplay = true } }
    private var start: NSPoint?
    private var initialOrigin: NSPoint?
    private var hovering = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard hovering || detached else { return }
        NSColor.gray.setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 9, y: bounds.midY - 1, width: 18, height: 2), xRadius: 1, yRadius: 1).fill()
    }
    override func mouseDown(with event: NSEvent) {
        start = window?.convertPoint(toScreen: event.locationInWindow)
        initialOrigin = window?.frame.origin
        moving = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start, let initialOrigin else { return }
        guard let current = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        if moving || detached || start.y - current.y > 8 {
            if !moving { moving = true; onDragStarted() }
            window?.setFrameOrigin(NSPoint(x: initialOrigin.x + current.x - start.x, y: initialOrigin.y + current.y - start.y))
        }
    }
    override func mouseUp(with event: NSEvent) {
        if moving, !detached, let origin = window?.frame.origin { onDetach?(origin) }
        start = nil
        initialOrigin = nil
        moving = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var status: NSStatusItem!
    private let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 490),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
    private let grip = GripView()
    private let dashboardModel = DashboardModel()
    private var dashboard: NSHostingView<Dashboard>!
    private var detached = false
    private var outsideMonitor: Any?
    private var windowButtons: [NSButton] = []
    private var dragging = false
    private var terminalPanel: MenuPanel?
    private var sideTerminal: SideTerminal?
    private var closingTerminal = false
    private var terminalExpanded = false
    private var terminalMotionID = 0
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "PUI"
        status.button?.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        status.button?.toolTip = "Puipui"
        status.button?.target = self
        status.button?.action = #selector(toggle)
        panel.delegate = self
        panel.dismissOverlay = { [weak self] in
            guard let self, dashboardModel.showsScanDetails else { return false }
            dashboardModel.showsScanDetails = false
            return true
        }
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 490))
        dashboard = NSHostingView(rootView: Dashboard(model: dashboardModel))
        if #available(macOS 14.0, *) { dashboard.safeAreaRegions = [] }
        dashboard.frame = content.bounds
        dashboard.autoresizingMask = [.width, .height]
        content.addSubview(dashboard)
        panel.contentView = content
        panel.setContentSize(NSSize(width: 320, height: 490))
        grip.frame = NSRect(x: 0, y: 474, width: 320, height: 16)
        grip.onDetach = { [weak self] point in self?.detach(at: point) }
        grip.onDragStarted = { [weak self] in self?.dragging = true }
        panel.contentView?.addSubview(grip)
        resizeDashboard()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.detached, !self.dragging else { return }
                self.panel.orderOut(nil)
                self.terminalPanel?.orderOut(nil)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--check-metrics") {
            checkMetrics()
            return
        }
        if CommandLine.arguments.contains("--check-storage") {
            checkStorage()
            return
        }
        if CommandLine.arguments.contains("--check-scan") {
            Task {
                switch await MoleScanner().scan() {
                case .success(let bytes): print("scan=true estimatedBytes=\(bytes)"); exit(0)
                case .failure(let error): print("scan=false reason=\(error.label)"); exit(1)
                }
            }
            return
        }
        dashboardModel.start()
        if CommandLine.arguments.contains("--check-terminal") { checkTerminal() }
        if CommandLine.arguments.contains("--check-window") {
            Task {
                if CommandLine.arguments.contains("--render-window") { try? await Task.sleep(for: .seconds(3)) }
                await checkWindow()
            }
        }
    }

    @objc private func toggle() {
        if detached {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isVisible {
            dashboardModel.showsScanDetails = false
            panel.orderOut(nil)
        } else {
            showAnchored()
        }
    }

    private func showAnchored() {
        dashboardModel.showsScanDetails = false
        guard let button = status.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? rect
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let x = min(max(rect.midX - 160, visible.minX), visible.maxX - 320)
        let y = max(visible.minY, min(rect.minY - 6, visible.maxY) - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func detach(at origin: NSPoint) {
        guard !detached else { return }
        dragging = false
        let previousFrame = panel.frame
        detached = true
        grip.detached = true
        panel.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        panel.title = "Puipui"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.level = .normal
        panel.collectionBehavior = [.managed]
        resizeDashboard()
        panel.setFrameOrigin(origin)
        panel.contentView?.layoutSubtreeIfNeeded()
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            panel.standardWindowButton(kind)?.isHidden = true
            guard let button = NSWindow.standardWindowButton(kind, for: panel.styleMask) else { continue }
            button.setFrameOrigin(NSPoint(x: 18 + CGFloat(index) * 22, y: panel.frame.height - 33))
            button.target = panel
            switch kind {
            case .closeButton: button.action = #selector(NSWindow.performClose(_:))
            case .miniaturizeButton: button.action = #selector(NSWindow.performMiniaturize(_:))
            default: button.isEnabled = false
            }
            panel.contentView?.addSubview(button)
            windowButtons.append(button)
        }
        let target = panel.frame
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && (!CommandLine.arguments.contains("--check-window") || CommandLine.arguments.contains("--animate-window")) {
            panel.setFrame(NSRect(origin: origin, size: previousFrame.size), display: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().setFrame(target, display: true)
            }
        }
        positionTerminal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        terminalPanel?.orderOut(nil)
        windowButtons.forEach { $0.removeFromSuperview() }
        windowButtons.removeAll()
        detached = false
        dragging = false
        panel.styleMask = [.borderless]
        resizeDashboard()
        grip.detached = false
        return false
    }
    func windowDidResignKey(_ notification: Notification) {
        dashboardModel.showsScanDetails = false
        if !detached && !dragging && !terminalExpanded && terminalPanel?.isVisible != true {
            panel.orderOut(nil)
            terminalPanel?.orderOut(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if detached { panel.makeKeyAndOrderFront(nil) } else { showAnchored() }
        return true
    }
    @objc private func screenChanged() {
        if panel.isVisible && !detached { showAnchored() }
    }

    private func resizeDashboard() {
        dashboard.rootView = Dashboard(model: dashboardModel, detached: detached,
                                      openTerminal: { [weak self] in self?.toggleTerminal() })
        let size = dashboard.fittingSize
        panel.setContentSize(size)
        dashboard.frame = NSRect(origin: .zero, size: size)
        dashboard.autoresizingMask = []
        grip.frame = NSRect(x: 0, y: size.height - 16, width: size.width, height: 16)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func toggleTerminal() {
        guard !closingTerminal else { return }
        if let terminalPanel {
            if terminalPanel.isVisible && terminalExpanded { hideTerminal() }
            else { showTerminal() }
            return
        }
        let terminal = SideTerminal()
        let window = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: panel.frame.height),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        let clip = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: panel.frame.height))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        terminal.view.frame = clip.bounds
        terminal.view.autoresizingMask = []
        clip.addSubview(terminal.view)
        window.contentView = clip
        window.setContentSize(NSSize(width: 560, height: panel.frame.height))
        terminal.onClose = { [weak self] in self?.closeTerminal() }
        terminal.onExit = { [weak self] in
            guard let self else { return }
            if closingTerminal && terminalPanel?.isVisible != true { finishClosingTerminal() }
        }
        sideTerminal = terminal
        terminalPanel = window
        panel.addChildWindow(window, ordered: .above)
        showTerminal(fresh: true)
        terminal.pty.start()
    }

    private func showTerminal(fresh: Bool = false) {
        guard let window = terminalPanel else { return }
        let wasVisible = !fresh && window.isVisible
        if !wasVisible { positionTerminal() }
        let destination = NSRect(x: window.frame.maxX - 560, y: window.frame.minY, width: 560, height: window.frame.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !wasVisible {
            if !reduceMotion {
                window.setFrame(NSRect(x: destination.maxX - 1, y: destination.minY, width: 1, height: destination.height), display: false)
            }
            window.alphaValue = reduceMotion ? 0 : 1
        }
        terminalExpanded = true
        terminalMotionID += 1
        window.makeKeyAndOrderFront(nil)
        if window.parent !== panel { panel.addChildWindow(window, ordered: .above) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            window.animator().setFrame(destination, display: true)
            window.animator().alphaValue = 1
        }
        sideTerminal?.terminal.acquireProgrammaticFocus()
    }

    private func hideTerminal() {
        guard let window = terminalPanel else { return }
        terminalExpanded = false
        terminalMotionID += 1
        let motionID = terminalMotionID
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            if reduceMotion { window.animator().alphaValue = 0 }
            else {
                window.animator().setFrame(NSRect(x: window.frame.maxX - 1, y: window.frame.minY,
                                                 width: 1, height: window.frame.height), display: true)
            }
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, self.terminalMotionID == motionID else { return }
                window?.orderOut(nil)
                if self.closingTerminal && self.sideTerminal?.pty.exitCode != nil { self.finishClosingTerminal() }
            }
        }
    }

    private func positionTerminal() {
        guard let terminalPanel else { return }
        let available = panel.screen?.visibleFrame
        if let available, panel.frame.minX < available.minX + 568 {
            panel.setFrameOrigin(NSPoint(x: min(available.maxX - panel.frame.width, available.minX + 568), y: panel.frame.minY))
        }
        terminalPanel.setFrame(NSRect(x: panel.frame.minX - 568, y: panel.frame.minY, width: 560, height: panel.frame.height), display: true)
        sideTerminal?.view.frame = NSRect(x: 0, y: 0, width: 560, height: panel.frame.height)
    }

    private func closeTerminal() {
        closingTerminal = true
        hideTerminal()
        if sideTerminal?.pty.exitCode != nil {
            if terminalPanel?.isVisible != true { finishClosingTerminal() }
        }
        else { sideTerminal?.pty.stop() }
    }

    private func finishClosingTerminal() {
        if let terminalPanel { panel.removeChildWindow(terminalPanel); terminalPanel.close() }
        terminalPanel = nil
        sideTerminal = nil
        closingTerminal = false
        if terminating { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        dashboardModel.stop()
        guard sideTerminal != nil else { return .terminateNow }
        if sideTerminal?.pty.exitCode != nil { closeTerminal(); return .terminateNow }
        terminating = true
        closeTerminal()
        return sideTerminal == nil ? .terminateNow : .terminateLater
    }

    private func checkTerminal() {
        showAnchored()
        toggleTerminal()
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            let unfolding = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                || (terminalPanel.map { $0.frame.width > 1 && $0.frame.width < 560 } == true)
            try? await Task.sleep(for: .seconds(2))
            guard let terminal = sideTerminal, let window = terminalPanel else { print("terminal=false"); exit(1) }
            let attached = window.parent === panel && abs(window.frame.maxX + 8 - panel.frame.minX) < 1
            _ = terminal.terminal.paste(text: "builtin printf 'PUI_%s\\n' TERMINAL_OK; if [[ -o login && -o interactive && -o rcs ]]; then builtin printf 'PUI_%s\\n' SHELL_CONFIG_ENABLED; fi")
            _ = terminal.terminal.sendKey(.enter)
            try? await Task.sleep(for: .seconds(1))
            let input = terminal.receivedText.contains("PUI_TERMINAL_OK")
            let shellConfigured = terminal.receivedText.contains("PUI_SHELL_CONFIG_ENABLED")
            toggleTerminal()
            try? await Task.sleep(for: .milliseconds(60))
            toggleTerminal()
            try? await Task.sleep(for: .milliseconds(450))
            let shown = window.isVisible && abs(window.alphaValue - 1) < 0.01
                && abs(window.frame.maxX + 8 - panel.frame.minX) < 1 && sideTerminal === terminal
                && abs(window.frame.width - 560) < 1
            let resources = GhosttyRuntimeResources.directoryURL?.path.hasPrefix(Bundle.main.bundleURL.path + "/Contents/Resources/") == true
            renderWindow(to: "build/terminal-preview.png", window: window)
            closeTerminal()
            try? await Task.sleep(for: .seconds(3))
            let reaped = terminal.pty.exitCode != nil && kill(terminal.pty.pid, 0) == -1 && errno == ESRCH
            print("terminalAttached=\(attached) input=\(input) reaped=\(reaped) bundledResources=\(resources) shellConfigured=\(shellConfigured) animatedReopen=\(shown)")
            print("drawerUnfolding=\(unfolding)")
            exit(attached && input && reaped && resources && shellConfigured && shown && unfolding ? 0 : 1)
        }
    }

    private func checkWindow() async {
        showAnchored()
        panel.contentView?.layoutSubtreeIfNeeded()
        let topPoint = NSPoint(x: 160, y: panel.contentLayoutRect.maxY - 12)
        let topHit = panel.contentView?.hitTest(topPoint)
        let gripAtTop = topHit === grip
        print("gripAtTop=\(gripAtTop) contentFlipped=\(panel.contentView?.isFlipped ?? false) gripFrame=\(grip.frame)")
        let anchoredSize = panel.contentView!.bounds.size
        let anchored = panel.isVisible && anchoredSize.width == 320 && anchoredSize.height < 490
        renderWindow(to: "build/window-anchored.png")
        dashboardModel.showsScanDetails = true
        try? await Task.sleep(for: .milliseconds(100))
        panel.contentView?.layoutSubtreeIfNeeded()
        let unchangedWithDetails = panel.contentView?.bounds.size == anchoredSize
        renderWindow(to: "build/scan-details.png")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        panel.sendEvent(escape)
        try? await Task.sleep(for: .milliseconds(100))
        let detailsDismissed = !dashboardModel.showsScanDetails
        print("detailsPreserveSize=\(unchangedWithDetails) escapeDismissesDetails=\(detailsDismissed)")
        // Leave room above the release point so screen-edge clamping does not change the origin.
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY - 60))
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: topPoint, modifierFlags: [], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: topPoint.x, y: topPoint.y - 20), modifierFlags: [], timestamp: 0.1,
                                      windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        grip.mouseDown(with: down)
        grip.mouseDragged(with: drag)
        let unchangedWhileDragging = !detached && windowButtons.isEmpty && panel.frame.size == anchoredSize
        let releasedOrigin = panel.frame.origin
        grip.mouseUp(with: drag)
        if CommandLine.arguments.contains("--animate-window") { try? await Task.sleep(for: .milliseconds(350)) }
        let released = detached && panel.styleMask.contains(.closable) && panel.level == .normal
            && panel.titleVisibility == .hidden && panel.titlebarAppearsTransparent
            && windowButtons.count == 3
            && abs(panel.frame.height - anchoredSize.height - 32) < 1
            && panel.frame.origin == releasedOrigin
        renderWindow(to: "build/window-preview.png")
        windowButtons.first?.performClick(nil)
        let closed = !panel.isVisible && !detached && windowButtons.isEmpty
        showAnchored()
        let reopened = panel.isVisible && !detached && !grip.isHidden
            && panel.contentView?.bounds.size == anchoredSize
        print("anchoredSize=\(anchoredSize) detached adds 32pt")
        print("anchored=\(anchored) detached=\(released) closed=\(closed) reopened=\(reopened)")
        print("unchangedWhileDragging=\(unchangedWhileDragging)")
        exit(anchored && gripAtTop && unchangedWhileDragging && released && closed && reopened
             && unchangedWithDetails && detailsDismissed ? 0 : 1)
    }

    private func renderWindow(to path: String, window: NSWindow? = nil) {
        guard CommandLine.arguments.contains("--render-window"),
              let frameView = (window ?? panel).contentView?.superview,
              let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            do { try png.write(to: URL(fileURLWithPath: path)) }
            catch { print("Window preview failed: \(error)"); exit(1) }
        }
    }

    private func checkMetrics() {
        Task {
            let sampler = SystemSampler()
            _ = await sampler.sample()
            try? await Task.sleep(for: .seconds(1))
            let sample = await sampler.sample()
            let cpuValid = sample.cpu.map { (0...1).contains($0.total) && (0...1).contains($0.user) && (0...1).contains($0.system) } ?? false
            let memoryValid = sample.memory.map { (0...1).contains($0) } ?? false
            let networkValid = sample.interface != nil
                && sample.receivedBytesPerSecond != nil && sample.sentBytesPerSecond != nil
            print("cpu=\(cpuValid) memory=\(memoryValid) network=\(networkValid) interface=\(sample.interface ?? "—")")
            exit(cpuValid && memoryValid && networkValid ? 0 : 1)
        }
    }

    private func checkStorage() {
        Task {
            let sample = await SystemSampler().sample()
            let scanner = MoleScanner()
            let capacityValid = sample.diskFree.map { $0 > 0 } == true
                && sample.diskTotal.map { $0 > (sample.diskFree ?? 0) } == true
            let moleValid = await scanner.isCompatible()
            let previewValid = await scanner.hasParsablePreview()
            print("capacity=\(capacityValid) mole=\(moleValid) preview=\(previewValid)")
            exit(capacityValid && moleValid && previewValid ? 0 : 1)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
