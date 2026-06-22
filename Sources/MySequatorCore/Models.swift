import Foundation

public enum CompositionMode: String, CaseIterable, Sendable {
    case mean
    case sigma
    case trails
}

public enum SceneCompositionMode: String, CaseIterable, Sendable {
    case fullFrame
    case skyFreezeGround
    case skyAndGround
}

public enum OutputStretch: String, CaseIterable, Sendable {
    case none
    case auto
    case hdr
}

public enum TIFFDepth: String, CaseIterable, Sendable {
    case uint16
    case float32
}

public typealias ProgressCallback = @Sendable (_ message: String, _ fraction: Double) -> Void

public struct StackOptions: Sendable {
    public var mode: CompositionMode
    public var sceneMode: SceneCompositionMode
    public var basePath: URL?
    public var darkPaths: [URL]
    public var flatPaths: [URL]
    public var skyMask: SkyMask?
    public var skyMaskOptions: SkyMaskOptions
    public var outputStretch: OutputStretch
    public var reduceLightPollution: Bool
    public var lightPollutionStrength: Float
    public var enhanceStars: Bool
    public var starEnhancementStrength: Float
    public var sigma: Float
    public var alignmentMaxDimension: Int
    public var linearMaster: Bool

    public init(
        mode: CompositionMode = .sigma,
        sceneMode: SceneCompositionMode = .fullFrame,
        basePath: URL? = nil,
        darkPaths: [URL] = [],
        flatPaths: [URL] = [],
        skyMask: SkyMask? = nil,
        skyMaskOptions: SkyMaskOptions = SkyMaskOptions(),
        outputStretch: OutputStretch = .none,
        reduceLightPollution: Bool = false,
        lightPollutionStrength: Float = 0.45,
        enhanceStars: Bool = false,
        starEnhancementStrength: Float = 0.35,
        sigma: Float = 2.2,
        alignmentMaxDimension: Int = 1200,
        linearMaster: Bool = false
    ) {
        self.mode = mode
        self.sceneMode = sceneMode
        self.basePath = basePath
        self.darkPaths = darkPaths
        self.flatPaths = flatPaths
        self.skyMask = skyMask
        self.skyMaskOptions = skyMaskOptions
        self.outputStretch = outputStretch
        self.reduceLightPollution = reduceLightPollution
        self.lightPollutionStrength = lightPollutionStrength
        self.enhanceStars = enhanceStars
        self.starEnhancementStrength = starEnhancementStrength
        self.sigma = sigma
        self.alignmentMaxDimension = alignmentMaxDimension
        self.linearMaster = linearMaster
    }
}

public struct SaveOptions: Sendable {
    public var tiffDepth: TIFFDepth
    public var clip: Bool

    public init(tiffDepth: TIFFDepth = .uint16, clip: Bool = true) {
        self.tiffDepth = tiffDepth
        self.clip = clip
    }
}

public struct AlignmentInfo: Sendable {
    public var path: URL
    public var dy: Int
    public var dx: Int
    public var peak: Float
    public var transform: ImageTransform

    public init(path: URL, dy: Int, dx: Int, peak: Float, transform: ImageTransform? = nil) {
        self.path = path
        self.dy = dy
        self.dx = dx
        self.peak = peak
        self.transform = transform ?? .translation(dy: dy, dx: dx, peak: peak)
    }
}

public struct StackResult: Sendable {
    public var image: FloatRGBImage
    public var basePath: URL
    public var alignments: [AlignmentInfo]
    public var skyMask: SkyMask?

    public init(image: FloatRGBImage, basePath: URL, alignments: [AlignmentInfo], skyMask: SkyMask? = nil) {
        self.image = image
        self.basePath = basePath
        self.alignments = alignments
        self.skyMask = skyMask
    }
}

public enum MySequatorError: Error, LocalizedError {
    case invalidImageDimensions
    case unsupportedImageType(String)
    case loadFailed(String)
    case saveFailed(String)
    case shapeMismatch(String)
    case invalidOption(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImageDimensions:
            return "Image dimensions must be positive."
        case .unsupportedImageType(let message):
            return message
        case .loadFailed(let message):
            return message
        case .saveFailed(let message):
            return message
        case .shapeMismatch(let message):
            return message
        case .invalidOption(let message):
            return message
        }
    }
}
