import AppKit
import Foundation
import ImageIO

enum AnimatedImageKind: Sendable, Equatable {
    case notGIF
    case singleFrameGIF
    case animated(AnimatedImageDescriptor)
}

struct AnimatedImageDescriptor: Sendable, Equatable {
    static let minimumFrameDelay = 0.02
    static let defaultFrameDelay = 0.10

    let frameCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let frameDelays: [Double]
    let loopCount: Int?
    let invalidTimingCount: Int

    var decodedFrameCost: Int? {
        let (pixels, pixelOverflow) = pixelWidth.multipliedReportingOverflow(
            by: pixelHeight
        )
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }
}

struct AnimatedFrame: @unchecked Sendable {
    let image: NSImage
    let index: Int
    let decodedByteCost: Int
}

enum AnimatedImageError: Error, Equatable {
    case unreadable
    case corrupt
    case invalidDimensions
    case excessiveDimensions
    case excessiveFrameCount
    case excessiveFrameCost
    case frameDecodeFailed
}

protocol AnimatedImageLoading: Sendable {
    func classify(url: URL) async throws -> AnimatedImageKind
    func decodeFrame(
        url: URL,
        descriptor: AnimatedImageDescriptor,
        index: Int
    ) async throws -> AnimatedFrame
}

struct ImageIOAnimatedImageLoader: AnimatedImageLoading {
    static let maximumFrameCount = 10_000
    static let maximumDimension = 16_384
    static let maximumPixelCount = 100_000_000
    static let maximumDecodedFrameCost = 64 * 1_024 * 1_024

    func classify(url: URL) async throws -> AnimatedImageKind {
        try await Task.detached(priority: .userInitiated) {
            guard url.pathExtension.lowercased() == "gif" else { return .notGIF }
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw AnimatedImageError.unreadable
            }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { throw AnimatedImageError.corrupt }
            guard count > 1 else { return .singleFrameGIF }
            guard count <= Self.maximumFrameCount else {
                throw AnimatedImageError.excessiveFrameCount
            }

            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                let width = Self.integer(properties[kCGImagePropertyPixelWidth]),
                let height = Self.integer(properties[kCGImagePropertyPixelHeight]),
                width > 0,
                height > 0
            else {
                throw AnimatedImageError.invalidDimensions
            }
            try Self.validateDimensions(width: width, height: height)

            var delays: [Double] = []
            delays.reserveCapacity(count)
            var invalidTimingCount = 0
            for index in 0..<count {
                try Task.checkCancellation()
                let frameProperties = CGImageSourceCopyPropertiesAtIndex(
                    source,
                    index,
                    nil
                ) as? [CFString: Any]
                let gif = frameProperties?[kCGImagePropertyGIFDictionary]
                    as? [CFString: Any]
                let rawDelay = Self.double(gif?[kCGImagePropertyGIFUnclampedDelayTime])
                    ?? Self.double(gif?[kCGImagePropertyGIFDelayTime])
                if let rawDelay, rawDelay.isFinite, rawDelay >= AnimatedImageDescriptor.minimumFrameDelay {
                    delays.append(rawDelay)
                } else {
                    invalidTimingCount += 1
                    delays.append(AnimatedImageDescriptor.defaultFrameDelay)
                }
            }

            let globalProperties = CGImageSourceCopyProperties(source, nil)
                as? [CFString: Any]
            let gif = globalProperties?[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
            let loopCount = Self.integer(gif?[kCGImagePropertyGIFLoopCount])
            return .animated(
                AnimatedImageDescriptor(
                    frameCount: count,
                    pixelWidth: width,
                    pixelHeight: height,
                    frameDelays: delays,
                    loopCount: loopCount,
                    invalidTimingCount: invalidTimingCount
                )
            )
        }.value
    }

    func decodeFrame(
        url: URL,
        descriptor: AnimatedImageDescriptor,
        index: Int
    ) async throws -> AnimatedFrame {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard descriptor.frameDelays.indices.contains(index) else {
                throw AnimatedImageError.frameDecodeFailed
            }
            guard
                let cost = descriptor.decodedFrameCost,
                cost <= Self.maximumDecodedFrameCost
            else {
                throw AnimatedImageError.excessiveFrameCost
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                CGImageSourceGetCount(source) > index
            else {
                throw AnimatedImageError.frameDecodeFailed
            }
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                    as? [CFString: Any],
                let width = Self.integer(properties[kCGImagePropertyPixelWidth]),
                let height = Self.integer(properties[kCGImagePropertyPixelHeight])
            else {
                throw AnimatedImageError.invalidDimensions
            }
            try Self.validateDimensions(width: width, height: height)
            guard
                let image = CGImageSourceCreateImageAtIndex(
                    source,
                    index,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                )
            else {
                throw AnimatedImageError.frameDecodeFailed
            }
            let (actualCost, overflow) = image.bytesPerRow.multipliedReportingOverflow(
                by: image.height
            )
            guard !overflow, actualCost <= Self.maximumDecodedFrameCost else {
                throw AnimatedImageError.excessiveFrameCost
            }
            try Task.checkCancellation()
            return AnimatedFrame(
                image: NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                ),
                index: index,
                decodedByteCost: actualCost
            )
        }.value
    }

    private static func validateDimensions(width: Int, height: Int) throws {
        guard width <= maximumDimension, height <= maximumDimension else {
            throw AnimatedImageError.excessiveDimensions
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= maximumPixelCount else {
            throw AnimatedImageError.excessiveDimensions
        }
        let (cost, costOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !costOverflow, cost <= maximumDecodedFrameCost else {
            throw AnimatedImageError.excessiveFrameCost
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
