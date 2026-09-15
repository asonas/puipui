import Darwin
import Foundation

enum ScanFailure: Error, Sendable {
    case unavailable
    case incompatible
    case failed
    case invalidResult

    var label: String {
        switch self {
        case .unavailable: "NO MO"
        case .incompatible: "VERSION"
        case .failed: "FAILED"
        case .invalidResult: "INVALID"
        }
    }
}

actor MoleScanner {
    private let executable = URL(fileURLWithPath: "/opt/homebrew/bin/mo").resolvingSymlinksInPath()
    private let preview: URL

    init(preview: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mole/clean-list.txt")) {
        self.preview = preview
    }

    func scan() -> Result<UInt64, ScanFailure> {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return .failure(.unavailable) }
        guard compatibleVersion() else { return .failure(.incompatible) }
        let previousDate = modificationDate(preview)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["clean", "--dry-run"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.failed) }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return .failure(.failed) }
        guard validPreview(previousDate: previousDate), let bytes = parsePreview() else {
            return .failure(.invalidResult)
        }
        return .success(bytes)
    }

    func isCompatible() -> Bool {
        FileManager.default.isExecutableFile(atPath: executable.path) && compatibleVersion()
    }

    func hasParsablePreview() -> Bool {
        parsePreview() != nil
    }

    private func compatibleVersion() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return text.range(of: #"Mole version 1\.53\.[0-9]+"#, options: .regularExpression) != nil
    }

    func validPreview(previousDate: Date?) -> Bool {
        var freshPreview = preview
        freshPreview.removeAllCachedResourceValues()
        guard let values = try? freshPreview.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                                  .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let date = values.contentModificationDate,
              previousDate == nil || date > previousDate! else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: preview.path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              mode & 0o022 == 0 else { return false }
        return true
    }

    func modificationDate(_ url: URL) -> Date? {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        return try? freshURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func parsePreview() -> UInt64? {
        guard let text = try? String(contentsOf: preview, encoding: .utf8),
              text.hasPrefix("# Mole Cleanup Preview - ") else { return nil }
        var total = 0.0
        var recognized = false
        let expression = try? NSRegularExpression(pattern: #"  # ([0-9]+(?:\.[0-9]+)?)(B|KB|MB|GB|TB)(?:, [0-9]+ items)?$"#)
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            if line.hasPrefix("=== ") && line.hasSuffix(" ===") { continue }
            let string = String(line)
            let range = NSRange(string.startIndex..., in: string)
            guard let match = expression?.firstMatch(in: string, range: range),
                  let valueRange = Range(match.range(at: 1), in: string),
                  let unitRange = Range(match.range(at: 2), in: string),
                  let value = Double(string[valueRange]) else { return nil }
            let multiplier: Double = switch string[unitRange] {
            case "KB": 1_000
            case "MB": 1_000_000
            case "GB": 1_000_000_000
            case "TB": 1_000_000_000_000
            default: 1
            }
            total += value * multiplier
            guard total.isFinite, total < Double(UInt64.max) else { return nil }
            recognized = true
        }
        return recognized ? UInt64(total) : 0
    }
}
