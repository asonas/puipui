import Foundation
import Testing
@testable import Puipui

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
