import Darwin
import Foundation
import OhbeeStage2Core

private struct Measurement: Codable {
    let entries: Int
    let eligibleImages: Int
    let enumerationMilliseconds: Double
    let sortingMilliseconds: Double
    let matchingMilliseconds: Double
    let totalMilliseconds: Double
    let selectedPosition: Int?
    let maximumResidentBytes: UInt64
}

private let resultPrefix = "OHBEE_BENCHMARK_JSON="

private func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000
        + Double(parts.attoseconds) / 1_000_000_000_000_000
}

private func maximumResidentBytes() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return UInt64(max(0, usage.ru_maxrss))
}

private func createFixture(entryCount: Int, at folder: URL) throws -> URL {
    let manager = FileManager.default
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let supported = ["jpg", "PNG", "heic", "gif", "tiff"]
    var selected: URL?

    for index in 0..<entryCount {
        let url: URL
        switch index % 20 {
        case 0:
            url = folder.appendingPathComponent(".hidden-\(index).jpg")
        case 1:
            url = folder.appendingPathComponent("subfolder-\(index)", isDirectory: true)
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            continue
        case 2:
            url = folder.appendingPathComponent("package-\(index).app", isDirectory: true)
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            continue
        case 3:
            url = folder.appendingPathComponent("notes-\(index).txt")
        case 4:
            url = folder.appendingPathComponent("image-\(index).raw")
        case 5:
            url = folder.appendingPathComponent("link-\(index).jpg")
            let target = folder.appendingPathComponent("notes-\(index - 2).txt")
            try manager.createSymbolicLink(at: url, withDestinationURL: target)
            continue
        default:
            let extensionName = supported[index % supported.count]
            let casePrefix = index.isMultiple(of: 2) ? "IMG" : "img"
            url = folder.appendingPathComponent("\(casePrefix)-\(index).\(extensionName)")
        }
        guard manager.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if selected == nil, SupportedImageFormat.supports(url), !url.lastPathComponent.hasPrefix(".") {
            selected = url
        }
    }
    guard let selected else { throw CocoaError(.fileNoSuchFile) }
    return selected
}

@main
private enum LargeFolderBenchmark {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--measure" {
            guard arguments.count == 4, let count = Int(arguments[3]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let selected = URL(fileURLWithPath: arguments[2])
            let started = ContinuousClock.now
            let result = try await FolderNavigationService.discover(
                folderURL: folder,
                selectedURL: selected
            )
            let measurement = Measurement(
                entries: count,
                eligibleImages: result.eligibleImageCount,
                enumerationMilliseconds: milliseconds(result.enumerationDuration),
                sortingMilliseconds: milliseconds(result.sortingDuration),
                matchingMilliseconds: milliseconds(result.matchingDuration),
                totalMilliseconds: milliseconds(started.duration(to: .now)),
                selectedPosition: result.snapshot?.position,
                maximumResidentBytes: maximumResidentBytes()
            )
            let data = try JSONEncoder().encode(measurement)
            print(resultPrefix + String(decoding: data, as: UTF8.self))
            return
        }

        let counts = arguments.compactMap(Int.init)
        let scenarios = counts.isEmpty ? [100, 1_000, 10_000, 100_000] : counts
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "ohbee-large-folder-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        var measurements: [Measurement] = []
        for count in scenarios {
            let folder = root.appendingPathComponent("entries-\(count)", isDirectory: true)
            let selected = try createFixture(entryCount: count, at: folder)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--measure", folder.path, selected.path, String(count)]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.executableNotLoadable)
            }
            let text = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            guard let line = text.split(separator: "\n").first(where: {
                $0.hasPrefix(resultPrefix)
            }) else {
                throw CocoaError(.coderReadCorrupt)
            }
            let payload = line.dropFirst(resultPrefix.count)
            let measurement = try JSONDecoder().decode(
                Measurement.self,
                from: Data(payload.utf8)
            )
            measurements.append(measurement)
            print(
                "METRIC entries=\(count) eligible=\(measurement.eligibleImages) "
                + "enumerationMs=\(measurement.enumerationMilliseconds) "
                + "sortMs=\(measurement.sortingMilliseconds) "
                + "matchMs=\(measurement.matchingMilliseconds) "
                + "totalMs=\(measurement.totalMilliseconds) "
                + "maxRSSBytes=\(measurement.maximumResidentBytes)"
            )
            try manager.removeItem(at: folder)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(measurements)
        print(String(decoding: data, as: UTF8.self))
    }
}
