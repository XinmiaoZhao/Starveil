import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct SkyMaskOptions: Sendable {
    public var autoMaskMaxDimension: Int
    public var skyGuardPixels: Int
    public var featherPixels: Int

    public init(autoMaskMaxDimension: Int = 1600, skyGuardPixels: Int = 8, featherPixels: Int = 24) {
        self.autoMaskMaxDimension = autoMaskMaxDimension
        self.skyGuardPixels = skyGuardPixels
        self.featherPixels = featherPixels
    }
}

public struct SkyMask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var alpha: [UInt8]

    public init(width: Int, height: Int, alpha: [UInt8]) throws {
        guard width > 0, height > 0, alpha.count == width * height else {
            throw MySequatorError.invalidImageDimensions
        }
        self.width = width
        self.height = height
        self.alpha = alpha
    }

    public init(width: Int, height: Int, skyValue: UInt8 = 0) {
        self.width = width
        self.height = height
        self.alpha = Array(repeating: skyValue, count: width * height)
    }

    public var pixelCount: Int {
        width * height
    }

    public func hasSameShape(as image: FloatRGBImage) -> Bool {
        width == image.width && height == image.height
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { alpha[y * width + x] }
        set { alpha[y * width + x] = newValue }
    }

    public mutating func paint(centerX: Int, centerY: Int, radius: Int, value: UInt8) {
        let safeRadius = max(1, radius)
        let r2 = safeRadius * safeRadius
        let y0 = max(0, centerY - safeRadius)
        let y1 = min(height - 1, centerY + safeRadius)
        let x0 = max(0, centerX - safeRadius)
        let x1 = min(width - 1, centerX + safeRadius)
        for y in y0...y1 {
            let dy = y - centerY
            for x in x0...x1 {
                let dx = x - centerX
                if dx * dx + dy * dy <= r2 {
                    alpha[y * width + x] = value
                }
            }
        }
    }

    public mutating func clear(to value: UInt8) {
        alpha = Array(repeating: value, count: pixelCount)
    }

    public mutating func invert() {
        for index in alpha.indices {
            alpha[index] = 255 &- alpha[index]
        }
    }

    public func hardSkyMask(minimumAlpha: UInt8 = 128) -> [UInt8] {
        alpha.map { $0 >= minimumAlpha ? 1 : 0 }
    }

    public func groundMask(maximumSkyAlpha: UInt8 = 127) -> [UInt8] {
        alpha.map { $0 <= maximumSkyAlpha ? 1 : 0 }
    }

    public func inwardFeatheredAlpha(guardPixels: Int, featherPixels: Int) -> [Float] {
        let distance = distanceToGround()
        let guardValue = Float(max(0, guardPixels))
        let featherValue = Float(max(1, featherPixels))
        var out = Array(repeating: Float(0), count: pixelCount)
        for pixel in 0..<pixelCount where alpha[pixel] >= 128 {
            let ramp = (Float(distance[pixel]) - guardValue) / featherValue
            let original = Float(alpha[pixel]) / 255
            out[pixel] = min(max(ramp, 0), original)
        }
        return out
    }

    public func erodedSkyMask(guardPixels: Int) -> [UInt8] {
        let distance = distanceToGround()
        let guardValue = max(0, guardPixels)
        var out = Array(repeating: UInt8(0), count: pixelCount)
        for pixel in 0..<pixelCount where alpha[pixel] >= 128 && distance[pixel] > guardValue {
            out[pixel] = 1
        }
        return out
    }

    private func distanceToGround() -> [Int] {
        let infinity = width + height + 1
        var distance = Array(repeating: infinity, count: pixelCount)
        for pixel in 0..<pixelCount where alpha[pixel] < 128 {
            distance[pixel] = 0
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                var best = distance[index]
                if x > 0 { best = min(best, distance[index - 1] + 1) }
                if y > 0 { best = min(best, distance[index - width] + 1) }
                if x > 0, y > 0 { best = min(best, distance[index - width - 1] + 2) }
                if x + 1 < width, y > 0 { best = min(best, distance[index - width + 1] + 2) }
                distance[index] = best
            }
        }

        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let index = y * width + x
                var best = distance[index]
                if x + 1 < width { best = min(best, distance[index + 1] + 1) }
                if y + 1 < height { best = min(best, distance[index + width] + 1) }
                if x + 1 < width, y + 1 < height { best = min(best, distance[index + width + 1] + 2) }
                if x > 0, y + 1 < height { best = min(best, distance[index + width - 1] + 2) }
                distance[index] = best
            }
        }
        return distance
    }
}

public func autoSkyMask(for image: FloatRGBImage, options: SkyMaskOptions = SkyMaskOptions()) throws -> SkyMask {
    let scale = min(Float(options.autoMaskMaxDimension) / Float(max(image.width, image.height)), 1)
    let sampledWidth = max(16, Int((Float(image.width) * scale).rounded()))
    let sampledHeight = max(16, Int((Float(image.height) * scale).rounded()))
    let luminance = image.luminance()
    var sampled = Array(repeating: Float(0), count: sampledWidth * sampledHeight)
    for y in 0..<sampledHeight {
        let sourceY = min(image.height - 1, Int((Float(y) / Float(sampledHeight)) * Float(image.height)))
        for x in 0..<sampledWidth {
            let sourceX = min(image.width - 1, Int((Float(x) / Float(sampledWidth)) * Float(image.width)))
            sampled[y * sampledWidth + x] = luminance[sourceY * image.width + sourceX]
        }
    }

    let rowScores = rowSkyScores(sampled, width: sampledWidth, height: sampledHeight)
    let defaultHorizon = Int((Float(sampledHeight) * 0.68).rounded())
    var bestHorizon = defaultHorizon
    var bestScore = -Float.greatestFiniteMagnitude
    let minRow = sampledHeight / 4
    let maxRow = min(sampledHeight - 2, sampledHeight * 9 / 10)
    for row in minRow...maxRow {
        let skyScore = rowScores[0..<row].reduce(0, +) / Float(max(row, 1))
        let groundScore = rowScores[row..<sampledHeight].reduce(0, +) / Float(max(sampledHeight - row, 1))
        let verticalPrior = 1 - abs(Float(row - defaultHorizon)) / Float(max(sampledHeight, 1))
        let score = (skyScore - groundScore) + 0.20 * verticalPrior
        if score > bestScore {
            bestScore = score
            bestHorizon = row
        }
    }

    var sampledAlpha = Array(repeating: UInt8(0), count: sampledWidth * sampledHeight)
    let horizonBand = max(2, sampledHeight / 80)
    for y in 0..<sampledHeight {
        let ramp = Float(bestHorizon - y) / Float(horizonBand)
        let value = UInt8((min(max(ramp, 0), 1) * 255).rounded())
        for x in 0..<sampledWidth {
            sampledAlpha[y * sampledWidth + x] = value
        }
    }

    var fullAlpha = Array(repeating: UInt8(0), count: image.pixelCount)
    for y in 0..<image.height {
        let sy = min(sampledHeight - 1, Int((Float(y) / Float(image.height)) * Float(sampledHeight)))
        for x in 0..<image.width {
            let sx = min(sampledWidth - 1, Int((Float(x) / Float(image.width)) * Float(sampledWidth)))
            fullAlpha[y * image.width + x] = sampledAlpha[sy * sampledWidth + sx]
        }
    }
    return try SkyMask(width: image.width, height: image.height, alpha: fullAlpha)
}

private func rowSkyScores(_ sampled: [Float], width: Int, height: Int) -> [Float] {
    let radius = 2
    var scores = Array(repeating: Float(0), count: height)
    for y in 0..<height {
        var total: Float = 0
        for x in 0..<width {
            let center = sampled[y * width + x]
            var blur: Float = 0
            var count: Float = 0
            for yy in max(0, y - radius)...min(height - 1, y + radius) {
                for xx in max(0, x - radius)...min(width - 1, x + radius) {
                    blur += sampled[yy * width + xx]
                    count += 1
                }
            }
            total += max(center - blur / count, 0)
        }
        let verticalPrior = 1 - Float(y) / Float(max(height - 1, 1))
        scores[y] = total / Float(width) + 0.05 * verticalPrior
    }
    return scores
}

public func loadSkyMask(_ url: URL) throws -> SkyMask {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw MySequatorError.loadFailed("Unable to load sky mask \(url.lastPathComponent).")
    }
    let width = cgImage.width
    let height = cgImage.height
    var pixels = Array(repeating: UInt8(0), count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw MySequatorError.loadFailed("Unable to create sky mask conversion context.")
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var alpha = Array(repeating: UInt8(0), count: width * height)
    for pixel in 0..<(width * height) {
        let src = pixel * 4
        alpha[pixel] = UInt8((UInt16(pixels[src]) + UInt16(pixels[src + 1]) + UInt16(pixels[src + 2])) / 3)
    }
    return try SkyMask(width: width, height: height, alpha: alpha)
}

public func saveSkyMask(_ mask: SkyMask, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let type = url.pathExtension.lowercased() == "tif" || url.pathExtension.lowercased() == "tiff"
        ? UTType.tiff.identifier
        : UTType.png.identifier
    var pixels = Array(repeating: UInt8(255), count: mask.pixelCount * 4)
    for pixel in 0..<mask.pixelCount {
        let dst = pixel * 4
        let value = mask.alpha[pixel]
        pixels[dst + 0] = value
        pixels[dst + 1] = value
        pixels[dst + 2] = value
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let cgImage = CGImage(
            width: mask.width,
            height: mask.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: mask.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw MySequatorError.saveFailed("Unable to create sky mask output image.")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw MySequatorError.saveFailed("Failed writing sky mask \(url.lastPathComponent).")
    }
}
