import AppKit
import Darwin
import Foundation
import ImageIO
import OhbeeStage2Core

struct LoadedSelectedImage: @unchecked Sendable {
    let image: NSImage
}

enum SelectedImageLoadError: Error, Equatable {
    case missing
    case unsupported
    case permissionDenied
    case unreadable
    case decodeFailed
    case resourceExcessive

    var userMessage: String {
        switch self {
        case .missing:
            "The image no longer exists."
        case .unsupported:
            "This file format is not supported."
        case .permissionDenied:
            "Ohbee Preview does not have permission to read this image."
        case .unreadable:
            "The image could not be read."
        case .decodeFailed:
            "The image data could not be decoded."
        case .resourceExcessive:
            "This GIF is too large to display safely."
        }
    }
}

enum SelectedImageLoader {
    private static func hasNoReadPermissionBits(_ url: URL) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
            ),
            let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return false
        }
        return permissions.intValue & 0o444 == 0
    }

    static func load(url: URL) async throws -> LoadedSelectedImage {
        try await Task.detached(priority: .userInitiated) {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try Task.checkCancellation()
            guard SupportedImageFormat.supports(url) else {
                throw SelectedImageLoadError.unsupported
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SelectedImageLoadError.missing
            }
            if hasNoReadPermissionBits(url) {
                throw SelectedImageLoadError.permissionDenied
            }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                try? handle.close()
            } catch {
                let nsError = error as NSError
                let isPermissionError =
                    (nsError.domain == NSCocoaErrorDomain
                        && nsError.code == NSFileReadNoPermissionError)
                    || (nsError.domain == NSPOSIXErrorDomain
                        && (nsError.code == EACCES || nsError.code == EPERM))
                if isPermissionError {
                    throw SelectedImageLoadError.permissionDenied
                }
                throw SelectedImageLoadError.unreadable
            }
            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            else {
                throw SelectedImageLoadError.decodeFailed
            }
            if url.pathExtension.lowercased() == "gif" {
                let frameCount = CGImageSourceGetCount(source)
                guard frameCount <= 10_000 else {
                    throw SelectedImageLoadError.resourceExcessive
                }
                guard
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                        as? [CFString: Any],
                    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                    width > 0,
                    height > 0,
                    width <= 16_384,
                    height <= 16_384
                else {
                    throw SelectedImageLoadError.resourceExcessive
                }
                let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
                guard !overflow, pixels <= 16_777_216 else {
                    throw SelectedImageLoadError.resourceExcessive
                }
            }
            guard
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
            return LoadedSelectedImage(image: image)
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
                    defer { try? handle.close() }
                    _ = try handle.read(upToCount: 1)
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
