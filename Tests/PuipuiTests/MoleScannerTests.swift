import Foundation
import Testing
@testable import Puipui

private struct MoleFixture {
    let folder: URL
    let executable: URL
    let preview: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        executable = folder.appendingPathComponent("mo")
        preview = folder.appendingPathComponent("preview.txt")
        try writeExecutable()
    }

    func writeExecutable(version: String = "1.53.2", exitCode: Int = 0, delay: Bool = false) throws {
        let path = preview.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
            printf '%s\\n' 'Mole version \(version)'
            exit 0
        fi
        [ "$1" = "clean" ] && [ "$2" = "--dry-run" ] || exit 9
        \(delay ? "/bin/sleep 0.15" : ":")
        [ \(exitCode) -eq 0 ] || exit \(exitCode)
        printf '# Mole Cleanup Preview - fixture\\n/tmp/cache  # 2.4GB\\n' > '\(path)'
        /bin/chmod 600 '\(path)'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

@Test func executableLookupFollowsPathOrderAndSkipsDirectories() throws {
    let first = try MoleFixture()
    let second = try MoleFixture()
    defer { first.remove(); second.remove() }
    #expect(MoleScanner.findExecutable(in: "\(first.folder.path):\(second.folder.path)") == first.executable)
    try FileManager.default.removeItem(at: first.executable)
    try FileManager.default.createDirectory(at: first.executable, withIntermediateDirectories: false)
    #expect(MoleScanner.findExecutable(in: "\(first.folder.path):\(second.folder.path)") == second.executable)
}

@Test(arguments: ["1.53.2", "1.59.0", "1.59.1"])
func supportedMoleVersionsCanScan(version: String) async throws {
    let fixture = try MoleFixture()
    defer { fixture.remove() }
    try fixture.writeExecutable(version: version)
    let scanner = MoleScanner(executable: fixture.executable, preview: fixture.preview)
    #expect(await scanner.scan() == .success(2_400_000_000))
}

@Test(arguments: ["1.52.0", "1.60.0", "2.0.0", "1.59.1-beta", "1.59.1-windows"])
func unsupportedMoleDoesNotRunCleanup(version: String) async throws {
    let fixture = try MoleFixture()
    defer { fixture.remove() }
    try fixture.writeExecutable(version: version)
    let scanner = MoleScanner(executable: fixture.executable, preview: fixture.preview)
    #expect(await scanner.scan() == .failure(.incompatible))
    #expect(!FileManager.default.fileExists(atPath: fixture.preview.path))
}

@Test func nestedMole159CandidatesAreNotCountedTwice() async throws {
    let fixture = try MoleFixture()
    defer { fixture.remove() }
    let contents = """
    # Mole Cleanup Preview - 2026-10-15 22:40:00
    === User essentials ===
    /tmp/cache  # 1.02GB, 2 items
    /tmp/cache/child  # 25.7MB, counted under /tmp/cache
    /tmp/cache/unknown  # size unknown, 2 items, counted under /tmp/cache
    /tmp/other  # 4KB
    """
    try Data(contents.utf8).write(to: fixture.preview)
    let scanner = MoleScanner(preview: fixture.preview)
    #expect(await scanner.parsePreview() == 1_020_004_000)
}

@Test @MainActor func startupScansImmediatelyAndRescanningRetainsLastSuccessOnFailure() async throws {
    let fixture = try MoleFixture()
    defer { fixture.remove() }
    let model = DashboardModel(moleScanner: MoleScanner(executable: fixture.executable, preview: fixture.preview))
    defer { model.stop() }
    model.start()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.lastScan == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.scanState == .ready)
    #expect(model.reclaimableBytes == 2_400_000_000)
    let lastSuccess = try #require(model.lastScan)
    let firstSchedule = try #require(model.nextScan)
    #expect(firstSchedule.timeIntervalSince(lastSuccess) == 3600)
    #expect(model.moleExecutable == fixture.executable)

    try fixture.writeExecutable(exitCode: 1, delay: true)
    let rescan = Task { await model.scan() }
    while model.scanState != .scanning && ContinuousClock.now < deadline { await Task.yield() }
    #expect(model.nextScan == nil)
    await model.scan()
    #expect(model.scanState == .scanning)
    await rescan.value
    #expect(model.scanState == .failed(.failed))
    #expect(model.reclaimableBytes == 2_400_000_000)
    #expect(model.lastScan == lastSuccess)
    #expect(try #require(model.nextScan) > firstSchedule)
}

@Test @MainActor func unsupportedMoleHasNoResultAndCanBeRechecked() async throws {
    let fixture = try MoleFixture()
    defer { fixture.remove() }
    try fixture.writeExecutable(version: "9.0.0")
    let model = DashboardModel(moleScanner: MoleScanner(executable: fixture.executable, preview: fixture.preview))
    defer { model.stop() }
    await model.scan()
    #expect(model.scanState == .failed(.incompatible))
    #expect(model.reclaimableBytes == nil)
    #expect(model.lastScan == nil)
    try fixture.writeExecutable()
    await model.scan()
    #expect(model.scanState == .ready)
    #expect(model.reclaimableBytes == 2_400_000_000)
}

@Test func previewFreshnessSurvivesCachedURLMetadata() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("preview.txt")
    try Data("old".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100), .posixPermissions: 0o600], ofItemAtPath: url.path)
    _ = try url.resourceValues(forKeys: [.contentModificationDateKey])
    let scanner = MoleScanner(preview: url)
    let before = await scanner.modificationDate(url)
    #expect(await scanner.validPreview(previousDate: before) == false)
    try Data("new".utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: url.path)
    #expect(await scanner.validPreview(previousDate: before))
}

@Test func parsesMoleDecimalSizesAndRejectsUnrecognizedResults() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("preview.txt")
    let header = "# Mole Cleanup Preview - 2026-09-09 09:31:31\n\n"
    try Data((header + "=== User essentials ===\n/tmp/cache-a  # 25.7MB\n/tmp/cache-b  # 1.02GB, 2 items\n/tmp/cache-c  # 4KB\n").utf8).write(to: url)
    let scanner = MoleScanner(preview: url)
    #expect(await scanner.parsePreview() == 1_045_704_000)
    try Data((header + "/tmp/cache  # size unknown\n").utf8).write(to: url)
    #expect(await scanner.parsePreview() == nil)
    try Data("invalid format".utf8).write(to: url)
    #expect(await scanner.parsePreview() == nil)
    try Data(header.utf8).write(to: url)
    #expect(await scanner.parsePreview() == 0)
}
