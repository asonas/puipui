import AppKit
import SwiftUI

struct Dashboard: View {
    @ObservedObject var model: DashboardModel
    var detached = false
    var openTerminal: () -> Void = {}
    var prepareCleanup: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                MetricRow(name: "CPU", value: percent(model.latest.cpu), history: model.cpuHistory, fixedScale: 1)
                MetricRow(name: "MEM", value: memoryValue, history: model.memoryHistory, fixedScale: 1)
                MetricRow(name: "NET", value: networkValue, history: model.networkHistory, fixedScale: nil)
            }
            .padding(.horizontal, 22).padding(.top, detached ? 48 : 16).padding(.bottom, 16)
            .foregroundStyle(Color(red: 0.04, green: 0.13, blue: 0.31))
            .background(Color(red: 0.96, green: 0.957, blue: 0.937))
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DISK FREE").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text(bytes(model.latest.diskFree)).font(.system(size: 30, design: .monospaced))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.18))
                        Rectangle().fill(.white.opacity(0.72))
                            .frame(width: proxy.size.width * diskFreeFraction)
                    }
                }.frame(height: 4)
                HStack {
                    Button("CLEAN  \(bytes(model.reclaimableBytes))", action: prepareCleanup)
                        .buttonStyle(.plain)
                        .help("Prepare mo clean in a new terminal. Press Enter to run.")
                        .disabled(model.scanState == "SCANNING")
                    Spacer()
                    Button(scanLabel) { Task { await model.scan() } }
                        .buttonStyle(.plain)
                        .disabled(model.scanState == "SCANNING")
                }
                .font(.system(size: 10, design: .monospaced))
                HStack {
                    Button(action: openTerminal) { Label("TERMINAL", systemImage: "terminal") }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Label("QUIT", systemImage: "power") }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .help("Quit Puipui")
                }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
            .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.92))
            .background(Color(red: 0.16, green: 0.176, blue: 0.192))
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea()
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .environment(\.colorScheme, .light)
    }

    private var memoryValue: String {
        guard let memory = model.latest.memory else { return "—" }
        return "\(Int((memory * 100).rounded()))%\n\(model.memoryPressure)"
    }

    private var diskFreeFraction: CGFloat {
        guard let free = model.latest.diskFree, let total = model.latest.diskTotal, total > 0 else { return 0 }
        return CGFloat(min(Double(free) / Double(total), 1))
    }

    private var scanLabel: String {
        if model.scanState == "SCANNING" { return "SCAN  …" }
        if model.scanState != "READY" { return "SCAN  \(model.scanState)" }
        guard let date = model.lastScan else { return "SCAN  NOW" }
        return "SCAN  " + date.formatted(date: .omitted, time: .shortened)
    }

    private func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(value))
    }

    private var networkValue: String {
        guard let received = model.latest.receivedBytesPerSecond,
              let sent = model.latest.sentBytesPerSecond else { return "—" }
        return "↓ \(rate(received))\n↑ \(rate(sent))"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    private func rate(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes)) + "/s"
    }
}

private struct MetricRow: View {
    let name: String
    let value: String
    let history: [Double]
    let fixedScale: Double?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(value).font(.system(size: 10, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 96, alignment: .leading)
            Sparkline(values: history, fixedScale: fixedScale)
        }
        .frame(height: 66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(value), \(fixedScale == nil ? "graph shows receive plus send" : "graph range 0 to 100 percent")")
    }
}

private struct Sparkline: View {
    let values: [Double]
    let fixedScale: Double?

    private var maximum: Double {
        guard fixedScale == nil else { return 1 }
        let peak = max(values.max() ?? 0, 1_000)
        let magnitude = pow(10, floor(log10(peak)))
        let step = [1.0, 2, 5, 10].first { $0 * magnitude >= peak } ?? 10
        return step * magnitude
    }

    private var upperLabel: String {
        if fixedScale != nil { return "100%" }
        let units = maximum >= 1_000_000_000 ? (1_000_000_000.0, "GB/s")
            : maximum >= 1_000_000 ? (1_000_000.0, "MB/s") : (1_000.0, "KB/s")
        return "\(Int((maximum / units.0).rounded())) \(units.1)"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                if fixedScale == nil { Text("RX + TX") }
                Spacer(minLength: 0)
                Text(upperLabel)
            }
        Canvas { context, size in
            for fraction in [0.0, 0.5, 1.0] {
                var line = Path()
                let y = 1 + (size.height - 2) * fraction
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.primary.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 0.5, dash: fraction == 0.5 ? [2, 3] : []))
            }
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = 1 + (size.height - 2) * (1 - CGFloat(min(max(value / maximum, 0), 1)))
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(.primary.opacity(0.72)), lineWidth: 1.25)
        }
        .frame(height: 30)
            Text(fixedScale == nil ? "0 B/s" : "0%")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Color(red: 0.30, green: 0.34, blue: 0.39))
        .help(fixedScale == nil ? "Receive + send. Vertical scale adjusts to the visible peak." : "Fixed vertical scale: 0–100%")
    }
}
