import Foundation

public struct FloatRGBImage: Sendable {
    public let width: Int
    public let height: Int
    public var data: [Float]

    public init(width: Int, height: Int, data: [Float]) throws {
        guard width > 0, height > 0, data.count == width * height * 3 else {
            throw MySequatorError.invalidImageDimensions
        }
        self.width = width
        self.height = height
        self.data = data
    }

    public init(width: Int, height: Int, repeating value: Float = 0) {
        self.width = width
        self.height = height
        self.data = Array(repeating: value, count: width * height * 3)
    }

    public var pixelCount: Int {
        width * height
    }

    public func index(x: Int, y: Int, channel: Int) -> Int {
        ((y * width) + x) * 3 + channel
    }

    public subscript(x: Int, y: Int, channel: Int) -> Float {
        get { data[index(x: x, y: y, channel: channel)] }
        set { data[index(x: x, y: y, channel: channel)] = newValue }
    }

    public func clipped(lower: Float = 0, upper: Float = 1) -> FloatRGBImage {
        var copy = self
        for i in copy.data.indices {
            copy.data[i] = min(max(copy.data[i], lower), upper)
        }
        return copy
    }

    public func luminance() -> [Float] {
        var out = Array(repeating: Float(0), count: pixelCount)
        for pixel in 0..<pixelCount {
            let base = pixel * 3
            out[pixel] = 0.2126 * data[base] + 0.7152 * data[base + 1] + 0.0722 * data[base + 2]
        }
        return out
    }

    public func hasSameShape(as other: FloatRGBImage) -> Bool {
        width == other.width && height == other.height
    }
}

extension Array where Element == Float {
    func percentile(_ percentile: Float) -> Float {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let clipped = Swift.min(Swift.max(percentile, 0), 100)
        let position = Float(sorted.count - 1) * clipped / 100
        let lower = Int(position.rounded(FloatingPointRoundingRule.down))
        let upper = Int(position.rounded(FloatingPointRoundingRule.up))
        if lower == upper {
            return sorted[lower]
        }
        let t = position - Float(lower)
        return sorted[lower] * (1 - t) + sorted[upper] * t
    }

    func median() -> Float {
        percentile(50)
    }
}
