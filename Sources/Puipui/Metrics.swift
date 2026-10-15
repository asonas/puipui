import Darwin
import Foundation
import SystemConfiguration

struct SystemSample: Sendable {
    let timestamp: Date
    let cpu: CPUUsage?
    let memory: Double?
    let interface: String?
    let receivedBytesPerSecond: Double?
    let sentBytesPerSecond: Double?
    let diskFree: UInt64?
    let diskTotal: UInt64?
}

struct CPUTicks: Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

struct CPUUsage: Sendable {
    let user: Double
    let system: Double
    var total: Double { user + system }

    init?(current: CPUTicks?, previous: CPUTicks?) {
        guard let current, let previous,
              current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else { return nil }
        let user = current.user - previous.user + current.nice - previous.nice
        let system = current.system - previous.system
        let total = user + system + current.idle - previous.idle
        guard total > 0 else { return nil }
        self.user = Double(user) / Double(total)
        self.system = Double(system) / Double(total)
    }
}

private struct NetworkCounters: Sendable {
    let interface: String
    let received: UInt64
    let sent: UInt64
}

actor SystemSampler {
    private var previousCPU: CPUTicks?
    private var previousNetwork: NetworkCounters?
    private var previousTime: ContinuousClock.Instant?
    private var diskCapacity: (free: UInt64, total: UInt64)?
    private var samplesSinceDiskRefresh = 60

    func sample() -> SystemSample {
        let now = ContinuousClock.now
        let ticks = readCPUTicks()
        let counters = readNetworkCounters()
        let cpu = CPUUsage(current: ticks, previous: previousCPU)
        let network = networkRates(current: counters, previous: previousNetwork,
                                   elapsed: previousTime.map { $0.duration(to: now) })
        if samplesSinceDiskRefresh >= 60 || diskCapacity == nil {
            diskCapacity = readDiskCapacity()
            samplesSinceDiskRefresh = 0
        } else {
            samplesSinceDiskRefresh += 1
        }
        previousCPU = ticks
        previousNetwork = counters
        previousTime = now

        return SystemSample(timestamp: Date(), cpu: cpu, memory: readMemoryUsage(),
                            interface: counters?.interface,
                            receivedBytesPerSecond: network?.received,
                            sentBytesPerSecond: network?.sent,
                            diskFree: diskCapacity?.free,
                            diskTotal: diskCapacity?.total)
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    private func readMemoryUsage() -> Double? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let used = Double(pages) * Double(pageSize)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(max(used / total, 0), 1)
    }

    private func readDiskCapacity() -> (free: UInt64, total: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attributes[.systemFreeSize] as? NSNumber,
              let total = attributes[.systemSize] as? NSNumber else { return nil }
        return (free.uint64Value, total.uint64Value)
    }

    private func readNetworkCounters() -> NetworkCounters? {
        guard let primary = primaryInterface() else { return nil }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let address = cursor {
            let item = address.pointee
            if String(cString: item.ifa_name) == primary,
               item.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return NetworkCounters(interface: primary,
                                       received: UInt64(data.pointee.ifi_ibytes),
                                       sent: UInt64(data.pointee.ifi_obytes))
            }
            cursor = item.ifa_next
        }
        return nil
    }

    private func primaryInterface() -> String? {
        guard let value = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString),
              let dictionary = value as? [String: Any] else { return nil }
        return dictionary["PrimaryInterface"] as? String
    }

    private func networkRates(current: NetworkCounters?, previous: NetworkCounters?,
                              elapsed: Duration?) -> (received: Double, sent: Double)? {
        guard let current, let previous, current.interface == previous.interface,
              current.received >= previous.received, current.sent >= previous.sent,
              let elapsed else { return nil }
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        guard seconds > 0 else { return nil }
        return (Double(current.received - previous.received) / seconds,
                Double(current.sent - previous.sent) / seconds)
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var latest = SystemSample(timestamp: Date(), cpu: nil, memory: nil, interface: nil,
                                                      receivedBytesPerSecond: nil, sentBytesPerSecond: nil,
                                                      diskFree: nil, diskTotal: nil)
    @Published private(set) var history: [SystemSample] = []
    @Published private(set) var memoryPressure = "normal"
    @Published private(set) var reclaimableBytes: UInt64?
    @Published private(set) var lastScan: Date?
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var nextScan: Date?
    @Published private(set) var moleExecutable: URL?
    @Published var showsScanDetails = false

    private let sampler = SystemSampler()
    private var samplingTask: Task<Void, Never>?
    private var pressureSource: DispatchSourceMemoryPressure?
    private let moleScanner: MoleScanner
    private var scheduledScanTask: Task<Void, Never>?

    init(moleScanner: MoleScanner = MoleScanner()) {
        self.moleScanner = moleScanner
    }

    func start() {
        guard samplingTask == nil else { return }
        startMemoryPressureMonitoring()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sample = await sampler.sample()
                apply(sample)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        scheduledScanTask = Task { [weak self] in await self?.scan() }
    }

    func scan() async {
        guard scanState != .scanning else { return }
        scheduledScanTask?.cancel()
        scheduledScanTask = nil
        nextScan = nil
        scanState = .scanning
        let result = await moleScanner.scan()
        moleExecutable = await moleScanner.executable
        let completed = Date()
        switch result {
        case .success(let bytes):
            reclaimableBytes = bytes
            lastScan = completed
            scanState = .ready
        case .failure(let error):
            scanState = .failed(error)
        }
        nextScan = completed.addingTimeInterval(3600)
        scheduledScanTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            guard let self else { return }
            scheduledScanTask = nil
            await scan()
        }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        scheduledScanTask?.cancel()
        scheduledScanTask = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func apply(_ sample: SystemSample) {
        latest = sample
        history.append(sample)
        history.removeAll { $0.timestamp < sample.timestamp.addingTimeInterval(-300) }
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            if event.contains(.critical) { memoryPressure = "critical" }
            else if event.contains(.warning) { memoryPressure = "warning" }
            else { memoryPressure = "normal" }
        }
        source.resume()
        pressureSource = source
    }
}

enum ScanState: Equatable {
    case idle
    case scanning
    case ready
    case failed(ScanFailure)

    var failure: ScanFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }

    var moleStatus: String {
        switch self {
        case .idle, .scanning: "Checking…"
        case .failed(.unavailable): "Not found"
        case .failed(.incompatible): "Unsupported"
        default: "Ready"
        }
    }
}
