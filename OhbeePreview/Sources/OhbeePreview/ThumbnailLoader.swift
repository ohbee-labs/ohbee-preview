import CoreGraphics
import Foundation
import ImageIO

struct ThumbnailRequestKey: Hashable, Sendable {
    let url: URL
    let maximumPixelSize: Int

    init(url: URL, maximumPixelSize: Int) {
        self.url = url.standardizedFileURL
        self.maximumPixelSize = maximumPixelSize
    }
}

final class ThumbnailPayload: @unchecked Sendable {
    let image: CGImage
    let cost: Int

    init(image: CGImage) {
        self.image = image
        cost = image.bytesPerRow * image.height
    }
}

enum ThumbnailLoadError: Error, Equatable {
    case sourceUnavailable
    case generationFailed
}

protocol ThumbnailLoading: Sendable {
    func loadThumbnail(
        from url: URL,
        maximumPixelSize: Int
    ) async throws -> ThumbnailPayload
}

struct ImageIOThumbnailLoader: ThumbnailLoading {
    func loadThumbnail(
        from url: URL,
        maximumPixelSize: Int
    ) async throws -> ThumbnailPayload {
        // The scheduler invokes this method from its bounded worker Task. Keep
        // ImageIO in that task so cancellation identity is preserved; a
        // detached decode would continue after its row or folder was cancelled.
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ThumbnailLoadError.sourceUnavailable
        }

        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw ThumbnailLoadError.generationFailed
        }
        try Task.checkCancellation()
        return ThumbnailPayload(image: image)
    }
}
