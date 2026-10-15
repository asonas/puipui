import SwiftUI

struct MetricChart: View {
    enum Kind { case cpu, memory, network }
    let kind: Kind
    let samples: [SystemSample]
    let now: Date

    private var maximum: Double {
        guard kind == .network else { return 1 }
        let peak = max(samples.flatMap { [$0.receivedBytesPerSecond, $0.sentBytesPerSecond].compactMap { $0 } }.max() ?? 0, 1_000)
        let magnitude = pow(10, floor(log10(peak)))
        return ([1.0, 2, 5, 10].first { $0 * magnitude >= peak } ?? 10) * magnitude
    }

    static func networkUnit(for bytes: Double) -> (divisor: Double, name: String) {
        if bytes >= 1_000_000_000 { return (1_000_000_000, "GB/s") }
        if bytes >= 1_000_000 { return (1_000_000, "MB/s") }
        return (1_000, "KB/s")
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Canvas { context, size in
                    for fraction in [0.0, 0.5, 1.0] {
                        var line = Path()
                        let y = 0.5 + (size.height - 1) * fraction
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(DashboardColors.subtle.opacity(0.6)),
                                       lineWidth: fraction == 0.5 && kind == .network ? 1 : 0.5)
                    }
                    switch kind {
                    case .cpu:
                        drawBand(context, size: size, color: DashboardColors.send, lower: { $0.cpu?.user }, upper: { $0.cpu?.total })
                        drawBand(context, size: size, color: DashboardColors.receive, lower: { $0.cpu.map { _ in 0 } }, upper: { $0.cpu?.user })
                    case .memory:
                        drawBand(context, size: size, color: DashboardColors.memory, lower: { $0.memory.map { _ in 0 } }, upper: { $0.memory })
                    case .network:
                        drawBand(context, size: size, color: DashboardColors.receive,
                                 lower: { $0.receivedBytesPerSecond.map { _ in 0 } }, upper: { $0.receivedBytesPerSecond })
                        drawBand(context, size: size, color: DashboardColors.send, belowZero: true,
                                 lower: { $0.sentBytesPerSecond.map { _ in 0 } }, upper: { $0.sentBytesPerSecond })
                    }
                }
                .frame(height: kind == .network ? 60 : 48).clipped()
                axis.frame(width: kind == .network ? 52 : 32)
            }
            HStack { Text("5m ago"); Spacer(); Text("now") }.font(.system(size: 11))
        }
        .foregroundStyle(DashboardColors.muted)
        .accessibilityElement(children: .ignore).accessibilityLabel(accessibilityDescription)
    }

    private var axis: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind == .network ? "RX \(scaleValue)" : "100%")
            Spacer(minLength: 0)
            if kind == .network {
                Text("0 \(Self.networkUnit(for: maximum).name)")
                Spacer(minLength: 0)
            }
            Text(kind == .network ? "TX \(scaleValue)" : "0%")
        }
        .font(.system(size: 10)).monospacedDigit().frame(height: kind == .network ? 60 : 48)
    }

    private var scaleValue: String {
        (maximum / Self.networkUnit(for: maximum).divisor).formatted(.number.precision(.fractionLength(0)))
    }

    private var accessibilityDescription: String {
        switch kind {
        case .cpu: "CPU history, last five minutes. User and system are stacked. Range zero to 100 percent."
        case .memory: "Memory usage history, last five minutes. Range zero to 100 percent."
        case .network: "Network history, last five minutes. Receive above zero, send below zero. Each direction has the same maximum of \(scaleValue) \(Self.networkUnit(for: maximum).name)."
        }
    }

    private func drawBand(_ context: GraphicsContext, size: CGSize, color: Color, belowZero: Bool = false,
                          lower: (SystemSample) -> Double?, upper: (SystemSample) -> Double?) {
        let baseline = kind == .network ? size.height / 2 : size.height - 0.5
        let height = kind == .network ? size.height / 2 - 0.5 : size.height - 1
        let direction: CGFloat = belowZero ? 1 : -1
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        var previousDate: Date?
        func flush() {
            guard top.count > 1 else { top.removeAll(); bottom.removeAll(); return }
            var area = Path()
            area.addLines(top + bottom.reversed())
            area.closeSubpath()
            context.fill(area, with: .color(color.opacity(0.75)))
            var trace = Path()
            trace.addLines(top)
            context.stroke(trace, with: .color(color), lineWidth: 1)
            top.removeAll()
            bottom.removeAll()
        }
        for sample in samples {
            if let previousDate, sample.timestamp.timeIntervalSince(previousDate) > 3 { flush() }
            previousDate = sample.timestamp
            guard let low = lower(sample), let high = upper(sample) else { flush(); continue }
            let x = size.width * min(max(1 + sample.timestamp.timeIntervalSince(now) / 300, 0), 1)
            top.append(CGPoint(x: x, y: baseline + direction * height * min(max(high / maximum, 0), 1)))
            bottom.append(CGPoint(x: x, y: baseline + direction * height * min(max(low / maximum, 0), 1)))
        }
        flush()
    }
}
