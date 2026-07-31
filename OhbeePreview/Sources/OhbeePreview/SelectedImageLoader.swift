import AppKit
import Foundation
import ImageIO
import OhbeeStage2Core

struct LoadedSelectedImage: @unchecked Sendable {
    let image: NSImage
    let sourceURL: URL
}

enum SelectedImageLoadError: Error {
    case unreadable
    case decodeFailed
}

enum SelectedImageLoader {
    static func load(url: URL) async throws -> LoadedSelectedImage {
        try await Task.detached(priority: .userInitiated) {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try Task.checkCancellation()
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw SelectedImageLoadError.unreadable
            }
            let data = try Data(contentsOf: url)
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(
                    source,
                    0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                )
            else {
                throw SelectedImageLoadError.decodeFailed
            }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            try Task.checkCancellation()
            return LoadedSelectedImage(image: image, sourceURL: url)
        }.value
    }
}

struct ParentAccessAssessment: Sendable {
    let parentURL: URL
    let canEnumerate: Bool
    let canReadRepresentativeSibling: Bool
    let failure: FolderAccessAssessmentFailure?
}

struct FolderAccessAssessmentFailure: Error, Sendable {
    let domain: String
    let code: Int
}

enum ParentAccessAssessor {
    static func assess(selectedURL: URL) async -> ParentAccessAssessment {
        await Task.detached(priority: .utility) {
            let didStart = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let parent = selectedURL.deletingLastPathComponent()
            var enumerationError: NSError?
            guard let enumerator = FileManager.default.enumerator(
                at: parent,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, error in
                    enumerationError = error as NSError
                    return false
                }
            ) else {
                return ParentAccessAssessment(
                    parentURL: parent,
                    canEnumerate: false,
                    canReadRepresentativeSibling: false,
                    failure: FolderAccessAssessmentFailure(
                        domain: NSCocoaErrorDomain,
                        code: NSFileReadNoPermissionError
                    )
                )
            }

            var observedSupportedSibling = false
            var firstSiblingFailure: NSError?
            while let candidate = enumerator.nextObject() as? URL {
                if candidate.standardizedFileURL == selectedURL.standardizedFileURL {
                    continue
                }
                guard SupportedImageFormat.supports(candidate) else { continue }
                do {
                    let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { continue }
                    observedSupportedSibling = true
                    let handle = try FileHandle(forReadingFrom: candidate)
                    _ = try handle.read(upToCount: 1)
                    try handle.close()
                    return ParentAccessAssessment(
                        parentURL: parent,
                        canEnumerate: true,
                        canReadRepresentativeSibling: true,
                        failure: nil
                    )
                } catch {
                    observedSupportedSibling = true
                    if firstSiblingFailure == nil {
                        firstSiblingFailure = error as NSError
                    }
                }
            }

            if let enumerationError {
                return ParentAccessAssessment(
                    parentURL: parent,
                    canEnumerate: false,
                    canReadRepresentativeSibling: false,
                    failure: FolderAccessAssessmentFailure(
                        domain: enumerationError.domain,
                        code: enumerationError.code
                    )
                )
            }
            if observedSupportedSibling, let firstSiblingFailure {
                return ParentAccessAssessment(
                    parentURL: parent,
                    canEnumerate: true,
                    canReadRepresentativeSibling: false,
                    failure: FolderAccessAssessmentFailure(
                        domain: firstSiblingFailure.domain,
                        code: firstSiblingFailure.code
                    )
                )
            }
            return ParentAccessAssessment(
                parentURL: parent,
                canEnumerate: true,
                canReadRepresentativeSibling: true,
                failure: nil
            )
        }.value
    }
}
