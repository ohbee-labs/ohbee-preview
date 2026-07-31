import Foundation

public enum SupportedImageFormat {
    public static let fileExtensions: Set<String> = [
        "jpeg", "jpg", "png", "heic", "heif", "gif", "tif", "tiff"
    ]

    public static func supports(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }
}

public enum OpenURLPolicy {
    public static func firstSupported(in urls: [URL]) -> URL? {
        urls.first(where: SupportedImageFormat.supports)
    }
}

public struct OpenRequest: Sendable, Equatable {
    public let generation: UInt64
    public let url: URL

    public init(generation: UInt64, url: URL) {
        self.generation = generation
        self.url = url
    }
}

public actor OpenRequestCoordinator {
    private var generation: UInt64 = 0

    public init() {}

    public func begin(url: URL) -> OpenRequest {
        generation &+= 1
        return OpenRequest(generation: generation, url: url)
    }

    public func isCurrent(_ request: OpenRequest) -> Bool {
        request.generation == generation
    }
}

public enum FolderAuthorizationState: Sendable, Equatable {
    case notAssessed
    case assessing
    case automaticAccessAvailable
    case actionAvailable
    case pickerPresented
    case authorizedForSession(URL)
    case declinedForImageSession
    case failed(FolderAccessFailure)
}

public enum FolderAccessFailure: String, Sendable, Equatable {
    case parentEnumerationDenied
    case siblingReadDenied
    case selectedFolderUnavailable
    case unknown
}

public struct ImageSessionState: Sendable, Equatable {
    public let selectedURL: URL
    public var authorization: FolderAuthorizationState

    public init(
        selectedURL: URL,
        authorization: FolderAuthorizationState = .notAssessed
    ) {
        self.selectedURL = selectedURL
        self.authorization = authorization
    }

    public mutating func beginAssessment() {
        authorization = .assessing
    }

    public mutating func automaticAccessSucceeded() {
        authorization = .automaticAccessAvailable
    }

    public mutating func automaticAccessFailed() {
        authorization = .actionAvailable
    }

    public mutating func presentPicker() {
        authorization = .pickerPresented
    }

    public mutating func authorize(folderURL: URL) {
        authorization = .authorizedForSession(folderURL)
    }

    public mutating func cancelPicker() {
        authorization = .declinedForImageSession
    }
}

public struct SessionAuthorizationMemory: Sendable {
    private var authorizedFolders: Set<URL> = []
    private var declinedImages: Set<URL> = []

    public init() {}

    public mutating func authorize(folderURL: URL) {
        authorizedFolders.insert(Self.normalized(folderURL))
    }

    public func isAuthorized(folderURL: URL) -> Bool {
        authorizedFolders.contains(Self.normalized(folderURL))
    }

    public mutating func decline(imageURL: URL) {
        declinedImages.insert(Self.normalized(imageURL))
    }

    public func wasDeclined(imageURL: URL) -> Bool {
        declinedImages.contains(Self.normalized(imageURL))
    }

    private static func normalized(_ url: URL) -> URL {
        // Keep this pure: authorization checks run on MainActor and must not
        // trigger filesystem or File Provider work.
        url.standardizedFileURL
    }
}
