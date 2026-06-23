import AppKit
import ImageIO
import MySequatorCore

struct PreviewBitmap: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    static func load(url: URL, maxPixelSize: Int) throws -> PreviewBitmap {
        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw MySequatorError.loadFailed("Unable to create preview source.")
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            let image = try loadImage(url)
            return image.makePreviewBitmap(maxPixelSize: maxPixelSize)
        }

        let width = thumbnail.width
        let height = thumbnail.height
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MySequatorError.loadFailed("Unable to create preview context.")
        }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PreviewBitmap(width: width, height: height, pixels: pixels)
    }

    func makeImage() -> NSImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }
}

extension SkyMask {
    func makeOverlayImage(maxPixelSize: Int) -> NSImage {
        let scale = min(Float(maxPixelSize) / Float(max(width, height)), 1)
        let outWidth = max(1, Int((Float(width) * scale).rounded()))
        let outHeight = max(1, Int((Float(height) * scale).rounded()))
        var pixels = Array(repeating: UInt8(0), count: outWidth * outHeight * 4)
        for y in 0..<outHeight {
            let sourceY = min(height - 1, Int((Float(y) / Float(outHeight)) * Float(height)))
            for x in 0..<outWidth {
                let sourceX = min(width - 1, Int((Float(x) / Float(outWidth)) * Float(width)))
                let alphaValue = alpha[sourceY * width + sourceX]
                let dst = (y * outWidth + x) * 4
                pixels[dst + 0] = 0
                pixels[dst + 1] = 180
                pixels[dst + 2] = 255
                pixels[dst + 3] = UInt8((Float(alphaValue) * 0.38).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: outWidth, height: outHeight))
    }
}

extension FloatRGBImage {
    func makePreviewBitmap(maxPixelSize: Int) -> PreviewBitmap {
        let scale = min(Float(maxPixelSize) / Float(max(width, height)), 1)
        let outWidth = max(1, Int((Float(width) * scale).rounded()))
        let outHeight = max(1, Int((Float(height) * scale).rounded()))
        let clippedImage = clipped()
        var pixels = Array(repeating: UInt8(255), count: outWidth * outHeight * 4)
        for y in 0..<outHeight {
            let sourceY = min(height - 1, Int((Float(y) / scale).rounded()))
            for x in 0..<outWidth {
                let sourceX = min(width - 1, Int((Float(x) / scale).rounded()))
                let pixel = sourceY * width + sourceX
                let outPixel = y * outWidth + x
                let src = pixel * 3
                let dst = outPixel * 4
                pixels[dst + 0] = UInt8((clippedImage.data[src + 0] * 255).rounded())
                pixels[dst + 1] = UInt8((clippedImage.data[src + 1] * 255).rounded())
                pixels[dst + 2] = UInt8((clippedImage.data[src + 2] * 255).rounded())
            }
        }
        return PreviewBitmap(width: outWidth, height: outHeight, pixels: pixels)
    }

    func makePreviewImage(maxSize: CGSize) -> NSImage {
        let clippedImage = clipped()
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        for pixel in 0..<pixelCount {
            let src = pixel * 3
            let dst = pixel * 4
            pixels[dst + 0] = UInt8((clippedImage.data[src + 0] * 255).rounded())
            pixels[dst + 1] = UInt8((clippedImage.data[src + 1] * 255).rounded())
            pixels[dst + 2] = UInt8((clippedImage.data[src + 2] * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        let original = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
        let scale = min(maxSize.width / CGFloat(width), maxSize.height / CGFloat(height), 1)
        original.size = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        return original
    }
}
