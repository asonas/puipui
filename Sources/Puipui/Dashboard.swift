import AppKit
import SwiftUI
import Sparkle

enum DashboardColors {
    static let paper = Color(red: 0.961, green: 0.957, blue: 0.937)
    static let ink = Color(red: 0.094, green: 0.169, blue: 0.263)
    static let muted = Color(red: 0.349, green: 0.384, blue: 0.424)
    static let dark = Color(red: 0.161, green: 0.176, blue: 0.192)
    static let button = Color(red: 0.298, green: 0.322, blue: 0.345)
    static let subtle = Color(red: 0.722, green: 0.745, blue: 0.773)
    static let light = Color(red: 0.957, green: 0.949, blue: 0.925)
    static let receive = Color(red: 0.086, green: 0.518, blue: 0.659)
    static let send = Color(red: 0.761, green: 0.306, blue: 0.404)
    static let memory = Color(red: 0.718, green: 0.510, blue: 0.153)
}

struct Dashboard: View {
    @ObservedObject var model: DashboardModel
    var detached = false
    var openTerminal: () -> Void = {}
    var updaterController: SPUStandardUpdaterController? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                metricRow {
                    Text("CPU").metricLabel()
                    Text(percent(model.latest.cpu?.total)).metricValue()
                    HStack(spacing: 8) {
                        Text("User \(percent(model.latest.cpu?.user))").foregroundStyle(DashboardColors.receive)
                        Text("Sys \(percent(model.latest.cpu?.system))").foregroundStyle(DashboardColors.send)
                    }
                    .font(.system(size: 11)).monospacedDigit()
                } chart: { MetricChart(kind: .cpu, samples: model.history, now: model.latest.timestamp) }
                metricRow {
                    Text("Memory").metricLabel()
                    Text(percent(model.latest.memory)).metricValue()
                    Text("Pressure: \(model.memoryPressure)")
                        .font(.system(size: 11))
                        .foregroundStyle(model.memoryPressure == "normal" ? DashboardColors.muted : DashboardColors.memory)
                } chart: { MetricChart(kind: .memory, samples: model.history, now: model.latest.timestamp) }
                metricRow {
                    Text("Network").metricLabel()
                    Text("RX \(networkRate(model.latest.receivedBytesPerSecond))")
                    Text("TX \(networkRate(model.latest.sentBytesPerSecond))")
                } chart: { MetricChart(kind: .network, samples: model.history, now: model.latest.timestamp) }
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .help("Receive and send rates on \(model.latest.interface ?? "the primary interface").")
            }
            .padding(.horizontal, 16).padding(.top, detached ? 48 : 16).padding(.bottom, 16)
            .foregroundStyle(DashboardColors.ink)
            .background(DashboardColors.paper)
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Free").font(.system(size: 13)).foregroundStyle(DashboardColors.subtle)
                    Spacer()
                    Text(formatBytes(model.latest.diskFree)).metricValue()
                }
                HStack(spacing: 6) {
                    Text(scanSummary)
                        .font(.system(size: 12)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.showsScanDetails.toggle() } label: {
                        LucideIcon.info.frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan details")
                    .accessibilityValue(model.showsScanDetails ? "Open" : "Closed")
                    .help("Scan details")
                    .anchorPreference(key: ScanDetailsAnchor.self, value: .bounds) { $0 }
                }
                .foregroundStyle(DashboardColors.subtle)
                .frame(height: 32)
                HStack {
                    Button(action: openTerminal) {
                        HStack(spacing: 6) { LucideIcon.terminal; Text("Terminal") }
                    }
                    .buttonStyle(DashboardButtonStyle())
                    .help("Open the embedded terminal")
                    Spacer()
                    OverflowMenu(model: model, updaterController: updaterController).frame(width: 36, height: 36)
                        .background(DashboardColors.button, in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(16)
            .foregroundStyle(DashboardColors.light)
            .background(DashboardColors.dark)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlayPreferenceValue(ScanDetailsAnchor.self) { anchor in
            if model.showsScanDetails, let anchor {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { model.showsScanDetails = false }
                        ScanDetails(model: model).frame(width: 288).fixedSize(horizontal: false, vertical: true)
                            .offset(x: 16, y: proxy[anchor].minY - 8 - proxy.size.height)
                    }
                }
            }
        }
        .onExitCommand { model.showsScanDetails = false }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }

    private func metricRow<Reading: View, Chart: View>(@ViewBuilder reading: () -> Reading,
                                                      @ViewBuilder chart: () -> Chart) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4, content: reading).frame(width: 112, alignment: .leading)
            chart().frame(width: 164)
        }.frame(minHeight: 72)
    }

    private var scanSummary: String {
        if let bytes = model.reclaimableBytes, let date = model.lastScan {
            let previous = "\(formatBytes(bytes)) reclaimable · \(scanTime(date))"
            switch model.scanState {
            case .scanning: return previous + "\nScanning…"
            case .failed: return previous + "\nUpdate failed"
            default: return previous
            }
        }
        switch model.scanState {
        case .idle: return "Not scanned yet"
        case .scanning: return "Scanning…"
        case .failed(.unavailable): return "Mole not found"
        case .failed(.incompatible): return "Mole version unsupported"
        case .failed: return "Scan failed · No result yet"
        case .ready: return "No result yet"
        }
    }

    private func scanTime(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    private func networkRate(_ value: Double?) -> String {
        guard let value else { return "—" }
        let unit = MetricChart.networkUnit(for: max(model.latest.receivedBytesPerSecond ?? 0, model.latest.sentBytesPerSecond ?? 0))
        return "\((value / unit.divisor).formatted(.number.precision(.fractionLength(0...1)))) \(unit.name)"
    }
}

private struct ScanDetails: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan details").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
            row("Last success", value: date(model.lastScan))
            row("Next scan", value: model.scanState == .scanning ? "After this scan" : date(model.nextScan))
            row("Mole", value: model.scanState.moleStatus)
            if let executable = model.moleExecutable {
                Text(executable.path).font(.system(size: 12)).foregroundStyle(DashboardColors.muted)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let failure = model.scanState.failure {
                Text(failure.explanation).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13)).monospacedDigit().padding(16)
        .foregroundStyle(DashboardColors.ink)
        .background(DashboardColors.paper, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        .accessibilityElement(children: .contain).accessibilityLabel("Scan details")
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        let day = Calendar.current.isDateInToday(value) ? "Today" : value.formatted(date: .abbreviated, time: .omitted)
        return "\(day), \(value.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ScanDetailsAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

enum LucideIcon: String, View {
    case info, terminal, ellipsis
    var image: NSImage {
        // PDFs preserve the Figma-exported Lucide geometry at native display scale.
        let url = Bundle.module.url(forResource: rawValue, withExtension: "pdf")!
        let image = NSImage(contentsOf: url)!
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    var body: some View {
        Image(nsImage: image).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
    }
}

private struct OverflowMenu: NSViewRepresentable {
    @ObservedObject var model: DashboardModel
    var updaterController: SPUStandardUpdaterController?

    func makeCoordinator() -> Coordinator { Coordinator(model: model, updaterController: updaterController) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.image = LucideIcon.ellipsis.image
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(DashboardColors.light)
        button.setAccessibilityLabel("More actions")
        button.toolTip = "More actions"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.model = model
        context.coordinator.updaterController = updaterController
    }

    @MainActor final class Coordinator: NSObject {
        var model: DashboardModel
        var updaterController: SPUStandardUpdaterController?
        init(model: DashboardModel, updaterController: SPUStandardUpdaterController?) {
            self.model = model
            self.updaterController = updaterController
        }

        @objc func open(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let scan = NSMenuItem(title: model.scanState == .scanning ? "Scanning…" : "Scan",
                                  action: #selector(scan), keyEquivalent: "")
            scan.target = self
            scan.isEnabled = model.scanState != .scanning
            menu.addItem(scan)
            menu.addItem(.separator())
            if let updaterController {
                let update = NSMenuItem(title: "Check for Updates…",
                                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
                update.target = updaterController
                update.isEnabled = updaterController.updater.canCheckForUpdates
                menu.addItem(update)
                menu.addItem(.separator())
            }
            let quit = NSMenuItem(title: "Quit puipui", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }

        @objc private func scan() { Task { await model.scan() } }
        @objc private func quit() { NSApp.terminate(nil) }
    }
}

private struct DashboardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 8).frame(height: 36)
            .background(DashboardColors.button.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension Text {
    func metricLabel() -> some View { font(.system(size: 13, weight: .medium)).foregroundStyle(DashboardColors.muted) }
    func metricValue() -> some View { font(.system(size: 22, weight: .semibold)).monospacedDigit() }
}

private func formatBytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useGB, .useTB]
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: value))
}
