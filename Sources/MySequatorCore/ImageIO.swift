import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CMySequatorSupport

public let rasterExtensions: Set<String> = [
    "jpg", "jpeg", "png", "tif", "tiff", "bmp",
]

public let rawExtensions: Set<String> = [
    "3fr", "arw", "bay", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff",
    "iiq", "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf",
    "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
]

public let supportedExtensions: Set<String> = rasterExtensions.union(rawExtensions)
public let outputExtensions: Set<String> = ["tif", "tiff", "jpg", "jpeg", "png", "fit", "fits", "fts"]

public func loadImage(_ url: URL, rawOptions: RawProcessingOptions = RawProcessingOptions()) throws -> FloatRGBImage {
    let ext = url.pathExtension.lowercased()
    guard supportedExtensions.contains(ext) else {
        throw MySequatorError.unsupportedImageType("Unsupported image type: \(url.lastPathComponent)")
    }
    if rawExtensions.contains(ext) {
        return try loadRawImage(url, options: rawOptions)
    }
    if ext == "tif" || ext == "tiff" {
        return try loadTIFFImage(url)
    }
    return try loadRasterImage(url)
}

public func saveImage(_ image: FloatRGBImage, to url: URL, options: SaveOptions = SaveOptions()) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "tif", "tiff":
        try saveTIFF(image, to: url, options: options)
    case "jpg", "jpeg":
        try saveRaster8(image.clipped(), to: url, type: UTType.jpeg.identifier, quality: 0.95)
    case "png":
        try saveRaster8(image.clipped(), to: url, type: UTType.png.identifier, quality: nil)
    case "fit", "fits", "fts":
        try saveFITS(image, to: url, options: options)
    default:
        throw MySequatorError.unsupportedImageType("Output must end with .tif, .tiff, .jpg, .jpeg, .png, .fit, .fits, or .fts.")
    }
}

private func loadRawImage(_ url: URL, options: RawProcessingOptions) throws -> FloatRGBImage {
    var cImage = MSQFloatRGBImage()
    let blackLevel = options.userBlackLevel.map { min(max($0, 0), Int(Int32.max)) }
    var cOptions = MSQRawDecodeOptions(
        white_balance_mode: rawWhiteBalanceValue(options.whiteBalanceMode),
        no_auto_bright: options.noAutoBrightness ? 1 : 0,
        highlight_mode: options.highlightMode.libRawValue,
        use_user_black: blackLevel == nil ? 0 : 1,
        user_black: Int32(blackLevel ?? 0)
    )
    let result = url.path.withCString { path in
        msq_load_raw_linear_rgb_with_options(path, &cOptions, &cImage)
    }
    defer { msq_free_float_rgb_image(&cImage) }
    guard result == 0, cImage.data != nil, cImage.width > 0, cImage.height > 0 else {
        let message = cImage.error_message.map { String(cString: $0) } ?? "RAW loading failed."
        throw MySequatorError.loadFailed(message)
    }
    let count = Int(cImage.width) * Int(cImage.height) * 3
    let buffer = UnsafeBufferPointer(start: cImage.data, count: count)
    return try FloatRGBImage(width: Int(cImage.width), height: Int(cImage.height), data: Array(buffer))
}

private func rawWhiteBalanceValue(_ mode: RawWhiteBalanceMode) -> Int32 {
    switch mode {
    case .camera:
        return 0
    case .auto:
        return 1
    case .none:
        return 2
    }
}

private func loadTIFFImage(_ url: URL) throws -> FloatRGBImage {
    var cImage = MSQFloatRGBImage()
    let result = url.path.withCString { path in
        msq_read_tiff_rgb_float(path, &cImage)
    }
    defer { msq_free_float_rgb_image(&cImage) }
    if result == 0, cImage.data != nil, cImage.width > 0, cImage.height > 0 {
        let count = Int(cImage.width) * Int(cImage.height) * 3
        let buffer = UnsafeBufferPointer(start: cImage.data, count: count)
        return try FloatRGBImage(width: Int(cImage.width), height: Int(cImage.height), data: Array(buffer))
    }
    return try loadRasterImage(url)
}

private func loadRasterImage(_ url: URL) throws -> FloatRGBImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw MySequatorError.loadFailed("Unable to load \(url.lastPathComponent).")
    }
    let width = cgImage.width
    let height = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = Array(repeating: UInt16(0), count: width * height * 4)
    let bitmapInfo = CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 16,
        bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw MySequatorError.loadFailed("Unable to create image conversion context.")
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var data = Array(repeating: Float(0), count: width * height * 3)
    for pixel in 0..<(width * height) {
        let src = pixel * 4
        let dst = pixel * 3
        data[dst + 0] = Float(pixels[src + 0]) / 65535
        data[dst + 1] = Float(pixels[src + 1]) / 65535
        data[dst + 2] = Float(pixels[src + 2]) / 65535
    }
    return try FloatRGBImage(width: width, height: height, data: data)
}

private func saveTIFF(_ image: FloatRGBImage, to url: URL, options: SaveOptions) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let data = options.clip ? image.clipped().data : image.data
    let result = data.withUnsafeBufferPointer { buffer in
        url.path.withCString { path in
            switch options.tiffDepth {
            case .float32:
                return msq_write_float_tiff(path, Int32(image.width), Int32(image.height), buffer.baseAddress, &errorMessage)
            case .uint16:
                return msq_write_uint16_tiff(path, Int32(image.width), Int32(image.height), buffer.baseAddress, &errorMessage)
            }
        }
    }
    defer { msq_free_error_message(errorMessage) }
    guard result == 0 else {
        let message = errorMessage.map { String(cString: $0) } ?? "TIFF save failed."
        throw MySequatorError.saveFailed(message)
    }
}

private func saveRaster8(_ image: FloatRGBImage, to url: URL, type: String, quality: Double?) throws {
    var pixels = Array(repeating: UInt8(255), count: image.width * image.height * 4)
    for pixel in 0..<image.pixelCount {
        let src = pixel * 3
        let dst = pixel * 4
        pixels[dst + 0] = UInt8((min(max(image.data[src + 0], 0), 1) * 255).rounded())
        pixels[dst + 1] = UInt8((min(max(image.data[src + 1], 0), 1) * 255).rounded())
        pixels[dst + 2] = UInt8((min(max(image.data[src + 2], 0), 1) * 255).rounded())
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw MySequatorError.saveFailed("Unable to create output image.")
    }

    var properties: [CFString: Any] = [:]
    if let quality {
        properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw MySequatorError.saveFailed("Failed writing \(url.lastPathComponent).")
    }
}

private func saveFITS(_ image: FloatRGBImage, to url: URL, options: SaveOptions) throws {
    let imageData = options.clip ? image.clipped().data : image.data
    var data = Data()
    let headerCards = [
        fitsCard(keyword: "SIMPLE", value: "T", comment: "conforms to FITS standard"),
        fitsCard(keyword: "BITPIX", value: "-32", comment: "32-bit floating point"),
        fitsCard(keyword: "NAXIS", value: "3", comment: "RGB image cube"),
        fitsCard(keyword: "NAXIS1", value: "\(image.width)", comment: "width"),
        fitsCard(keyword: "NAXIS2", value: "\(image.height)", comment: "height"),
        fitsCard(keyword: "NAXIS3", value: "3", comment: "RGB channels"),
        fitsCard(keyword: "EXTEND", value: "T", comment: nil),
        fitsCard(keyword: "BZERO", value: "0.0", comment: nil),
        fitsCard(keyword: "BSCALE", value: "1.0", comment: nil),
        fitsComment("Linear stacked data from MySequator"),
        fitsEndCard()
    ]

    for card in headerCards {
        guard let encoded = card.data(using: .ascii) else {
            throw MySequatorError.saveFailed("Unable to encode FITS header.")
        }
        data.append(encoded)
    }
    padFITSBlock(&data, byte: UInt8(ascii: " "))

    for channel in 0..<3 {
        for pixel in 0..<image.pixelCount {
            let value = imageData[pixel * 3 + channel]
            data.appendBigEndianFloat(value.isFinite ? value : 0)
        }
    }
    padFITSBlock(&data, byte: 0)

    do {
        try data.write(to: url, options: .atomic)
    } catch {
        throw MySequatorError.saveFailed("Failed writing \(url.lastPathComponent): \(error.localizedDescription)")
    }
}

private func fitsCard(keyword: String, value: String, comment: String?) -> String {
    let base = keyword.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value
    let withComment = comment.map { "\(base) / \($0)" } ?? base
    return String(withComment.prefix(80)).padding(toLength: 80, withPad: " ", startingAt: 0)
}

private func fitsComment(_ comment: String) -> String {
    String("COMMENT \(comment)".prefix(80)).padding(toLength: 80, withPad: " ", startingAt: 0)
}

private func fitsEndCard() -> String {
    "END".padding(toLength: 80, withPad: " ", startingAt: 0)
}

private func padFITSBlock(_ data: inout Data, byte: UInt8) {
    let remainder = data.count % 2880
    if remainder > 0 {
        data.append(contentsOf: Array(repeating: byte, count: 2880 - remainder))
    }
}

private extension Data {
    mutating func appendBigEndianFloat(_ value: Float) {
        var bits = value.bitPattern.bigEndian
        Swift.withUnsafeBytes(of: &bits) {
            append(contentsOf: $0)
        }
    }
}
