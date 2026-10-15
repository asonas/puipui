import Foundation
import Testing
@testable import Puipui

@Test func cpuBreakdownUsesIntervalAndIncludesNiceInUser() throws {
    let previous = CPUTicks(user: 100, system: 50, idle: 500, nice: 10)
    let current = CPUTicks(user: 120, system: 60, idle: 565, nice: 15)
    let usage = try #require(CPUUsage(current: current, previous: previous))
    #expect(abs(usage.user - 0.25) < 0.000_001)
    #expect(abs(usage.system - 0.10) < 0.000_001)
    #expect(abs(usage.total - 0.35) < 0.000_001)
    #expect(CPUUsage(current: current, previous: nil) == nil)
    #expect(CPUUsage(current: previous, previous: current) == nil)
    #expect(CPUUsage(current: current, previous: current) == nil)
}
