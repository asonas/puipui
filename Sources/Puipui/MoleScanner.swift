import Darwin
import Foundation

enum ScanFailure: Error, Sendable, Equatable {
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

    var explanation: String {
        switch self {
        case .unavailable: "Mole was not found in your login shell’s PATH. Install Mole, then choose Scan to check again."
        case .incompatible: "This version of Puipui supports Mole 1.53.x. Choose Scan after installing a compatible version."
        case .failed: "The scan did not finish successfully. Choose Scan to try again."
        case .invalidResult: "Mole did not produce a fresh, readable cleanup preview. Choose Scan to try again."
        }
    }
}

actor MoleScanner {
    private(set) var executable: URL?
    private let suppliedExecutable: URL?
    private let preview: URL

    init(executable: URL? = nil, preview: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mole/clean-list.txt")) {
        suppliedExecutable = executable
        self.preview = preview
    }

    func scan() -> Result<UInt64, ScanFailure> {
        executable = suppliedExecutable ?? resolveExecutable()
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else { return .failure(.unavailable) }
        guard compatibleVersion(executable) else { return .failure(.incompatible) }
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
        executable = suppliedExecutable ?? resolveExecutable()
        guard let executable else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path) && compatibleVersion(executable)
    }

    func hasParsablePreview() -> Bool {
        parsePreview() != nil
    }

    private func resolveExecutable() -> URL? {
        guard let account = getpwuid(getuid()), let shell = account.pointee.pw_shell else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: String(cString: shell))
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.arguments = ["-l", "-c", "printf '\\0%s\\0' \"$PATH\""]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?.split(separator: "\0", omittingEmptySubsequences: false).dropLast().last else { return nil }
        return Self.findExecutable(in: String(path))
    }

    static func findExecutable(in searchPath: String) -> URL? {
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
            let base = directory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser
                : URL(fileURLWithPath: String(directory), relativeTo: FileManager.default.homeDirectoryForCurrentUser)
            let candidate = base.appendingPathComponent("mo").standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
        return nil
    }

    private func compatibleVersion(_ executable: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
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
