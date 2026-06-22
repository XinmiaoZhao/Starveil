import Foundation

public struct ImageTransform: Sendable, Equatable {
    public var a: Float
    public var b: Float
    public var tx: Float
    public var ty: Float
    public var peak: Float

    public init(a: Float, b: Float, tx: Float, ty: Float, peak: Float = 1) {
        self.a = a
        self.b = b
        self.tx = tx
        self.ty = ty
        self.peak = peak
    }

    public static func identity() -> ImageTransform {
        ImageTransform(a: 1, b: 0, tx: 0, ty: 0, peak: 1)
    }

    public static func translation(dy: Int, dx: Int, peak: Float = 1) -> ImageTransform {
        ImageTransform(a: 1, b: 0, tx: Float(dx), ty: Float(dy), peak: peak)
    }

    public var dx: Int {
        Int(tx.rounded())
    }

    public var dy: Int {
        Int(ty.rounded())
    }

    public var scale: Float {
        sqrt(a * a + b * b)
    }

    public var rotationRadians: Float {
        atan2(b, a)
    }

    public var isIntegerTranslation: Bool {
        abs(a - 1) < 1e-6 &&
        abs(b) < 1e-6 &&
        abs(tx - tx.rounded()) < 1e-6 &&
        abs(ty - ty.rounded()) < 1e-6
    }

    public func sourcePoint(forDestinationX x: Float, y: Float) -> (x: Float, y: Float)? {
        let determinant = a * a + b * b
        guard determinant > 1e-8 else { return nil }
        let centeredX = x - tx
        let centeredY = y - ty
        return (
            x: (a * centeredX + b * centeredY) / determinant,
            y: (-b * centeredX + a * centeredY) / determinant
        )
    }
}

public func warpImageWithMask(_ image: FloatRGBImage, transform: ImageTransform, sourceMask: [UInt8]? = nil) -> (FloatRGBImage, [UInt8]) {
    var out = FloatRGBImage(width: image.width, height: image.height)
    var valid = Array(repeating: UInt8(0), count: image.pixelCount)
    let mask = sourceMask

    for y in 0..<image.height {
        for x in 0..<image.width {
            guard let source = transform.sourcePoint(forDestinationX: Float(x), y: Float(y)) else {
                continue
            }
            guard source.x >= 0, source.y >= 0, source.x <= Float(image.width - 1), source.y <= Float(image.height - 1) else {
                continue
            }

            let x0 = Int(source.x.rounded(.down))
            let y0 = Int(source.y.rounded(.down))
            let x1 = min(image.width - 1, x0 + 1)
            let y1 = min(image.height - 1, y0 + 1)

            if let mask {
                let nearestX = min(max(Int(source.x.rounded()), 0), image.width - 1)
                let nearestY = min(max(Int(source.y.rounded()), 0), image.height - 1)
                if mask[nearestY * image.width + nearestX] == 0 {
                    continue
                }
            }

            let fx = source.x - Float(x0)
            let fy = source.y - Float(y0)
            let w00 = (1 - fx) * (1 - fy)
            let w10 = fx * (1 - fy)
            let w01 = (1 - fx) * fy
            let w11 = fx * fy
            for channel in 0..<3 {
                out[x, y, channel] =
                    image[x0, y0, channel] * w00 +
                    image[x1, y0, channel] * w10 +
                    image[x0, y1, channel] * w01 +
                    image[x1, y1, channel] * w11
            }
            valid[y * image.width + x] = 1
        }
    }
    return (out, valid)
}
