import Foundation
import MySequatorCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message: message)
    }
}

struct TestCase {
    let name: String
    let run: () throws -> Void
}

let tests: [TestCase] = [
    TestCase(name: "estimateTranslationReturnsShiftToApplyToMoving", run: estimateTranslationReturnsShiftToApplyToMoving),
    TestCase(name: "translateWithMaskDoesNotWrap", run: translateWithMaskDoesNotWrap),
    TestCase(name: "stackImagesAlignsAndAverages", run: stackImagesAlignsAndAverages),
    TestCase(name: "defaultOutputIsNotStretched", run: defaultOutputIsNotStretched),
    TestCase(name: "autoStretchIsOptional", run: autoStretchIsOptional),
    TestCase(name: "tiffRoundTripPreserves16BitRGB", run: tiffRoundTripPreserves16BitRGB),
    TestCase(name: "float32TIFFRoundTripPreservesLinearValues", run: float32TIFFRoundTripPreservesLinearValues),
    TestCase(name: "rawExtensionsAreAdvertisedButXISFIsDeferred", run: rawExtensionsAreAdvertisedButXISFIsDeferred),
]

var failures: [String] = []
for test in tests {
    do {
        try test.run()
        print("PASS \(test.name)")
    } catch {
        failures.append("\(test.name): \(error)")
        print("FAIL \(test.name): \(error)")
    }
}

if !failures.isEmpty {
    print("\n\(failures.count) test(s) failed:")
    for failure in failures {
        print("  \(failure)")
    }
    exit(1)
}

print("\n\(tests.count) tests passed.")

func estimateTranslationReturnsShiftToApplyToMoving() throws {
    let reference = stars(width: 128, height: 128, points: [(30, 42), (65, 80), (90, 25), (101, 104)])
    let movingRGB = try FloatRGBImage(width: 128, height: 128, data: rgbData(fromGray: reference))
    let shifted = translateWithMask(movingRGB, dy: 7, dx: -5).0

    let shift = try estimateTranslation(reference: reference, moving: shifted.luminance(), width: 128, height: 128, maxDimension: 128)

    try expect(shift.dy == -7, "Expected dy -7, got \(shift.dy)")
    try expect(shift.dx == 5, "Expected dx 5, got \(shift.dx)")
}

func translateWithMaskDoesNotWrap() throws {
    let image = FloatRGBImage(width: 8, height: 8, repeating: 1)
    let (shifted, mask) = translateWithMask(image, dy: 2, dx: -3)

    var topRows: Float = 0
    for y in 0..<2 {
        for x in 0..<8 {
            for channel in 0..<3 {
                topRows += shifted[x, y, channel]
            }
        }
    }
    var rightColumns: Float = 0
    for y in 0..<8 {
        for x in 5..<8 {
            for channel in 0..<3 {
                rightColumns += shifted[x, y, channel]
            }
        }
    }

    try expect(topRows == 0, "Translated image wrapped into top rows.")
    try expect(rightColumns == 0, "Translated image wrapped into right columns.")
    try expect(mask.filter { $0 != 0 }.count == 30, "Expected 30 valid pixels.")
}

func stackImagesAlignsAndAverages() throws {
    let temp = try temporaryDirectory()
    let base = try makeRGBStarField()
    let shifts = [(0, 0), (3, -2), (-4, 5), (2, 4)]
    var paths: [URL] = []

    for (index, shift) in shifts.enumerated() {
        let shifted = translateWithMask(base, dy: shift.0, dx: shift.1).0
        let path = temp.appendingPathComponent("frame_\(index).tiff")
        try saveImage(shifted, to: path)
        paths.append(path)
    }

    let result = try stackImages(paths, options: StackOptions(mode: .sigma))

    try expect(result.image.width == base.width, "Width mismatch.")
    try expect(result.image.height == base.height, "Height mismatch.")
    try expect(result.alignments.count == 4, "Expected 4 alignment entries.")
    try expect((result.image.data.max() ?? 0) > 0.5, "Stacked image is unexpectedly dark.")
}

func defaultOutputIsNotStretched() throws {
    let temp = try temporaryDirectory()
    var image = FloatRGBImage(width: 32, height: 32, repeating: 0.08)
    for y in 12..<15 {
        for x in 12..<15 {
            for channel in 0..<3 {
                image[x, y, channel] = 0.25
            }
        }
    }
    let paths = try (0..<2).map { index in
        let path = temp.appendingPathComponent("linear_\(index).tiff")
        try saveImage(image, to: path)
        return path
    }

    let result = try stackImages(paths, options: StackOptions(mode: .mean))

    try expect((result.image.data.max() ?? 1) < 0.28, "Default stack should remain linear.")
}

func autoStretchIsOptional() throws {
    let temp = try temporaryDirectory()
    var image = FloatRGBImage(width: 32, height: 32, repeating: 0.08)
    for y in 12..<15 {
        for x in 12..<15 {
            for channel in 0..<3 {
                image[x, y, channel] = 0.25
            }
        }
    }
    let paths = try (0..<2).map { index in
        let path = temp.appendingPathComponent("auto_\(index).tiff")
        try saveImage(image, to: path)
        return path
    }

    let result = try stackImages(paths, options: StackOptions(mode: .mean, outputStretch: .auto))

    try expect((result.image.data.max() ?? 0) > 0.85, "Auto stretch did not brighten output.")
}

func tiffRoundTripPreserves16BitRGB() throws {
    let temp = try temporaryDirectory()
    var image = FloatRGBImage(width: 10, height: 12)
    for pixel in 0..<image.pixelCount {
        image.data[pixel * 3 + 0] = 0.25
        image.data[pixel * 3 + 1] = 0.5
        image.data[pixel * 3 + 2] = 0.75
    }
    let path = temp.appendingPathComponent("roundtrip.tiff")

    try saveImage(image, to: path)
    let loaded = try loadImage(path)

    try expect(loaded.width == image.width, "Width mismatch.")
    try expect(loaded.height == image.height, "Height mismatch.")
    try expect(abs(loaded.data[0] - 0.25) < 1.0 / 65535.0, "Red channel did not round-trip.")
    try expect(abs(loaded.data[1] - 0.5) < 1.0 / 65535.0, "Green channel did not round-trip.")
    try expect(abs(loaded.data[2] - 0.75) < 1.0 / 65535.0, "Blue channel did not round-trip.")
}

func float32TIFFRoundTripPreservesLinearValues() throws {
    let temp = try temporaryDirectory()
    var image = FloatRGBImage(width: 4, height: 4)
    for i in image.data.indices {
        image.data[i] = Float(i) / 10.0
    }
    let path = temp.appendingPathComponent("float-master.tiff")

    try saveImage(image, to: path, options: SaveOptions(tiffDepth: .float32, clip: false))
    let loaded = try loadImage(path)

    try expect(abs(loaded.data[12] - image.data[12]) < 1e-6, "Float32 TIFF did not preserve value.")
    try expect((loaded.data.max() ?? 0) > 1, "Float32 TIFF unexpectedly clipped linear values.")
}

func rawExtensionsAreAdvertisedButXISFIsDeferred() throws {
    try expect(rawExtensions.contains("dng"), "DNG should be advertised.")
    try expect(supportedExtensions.contains("cr3"), "CR3 should be advertised.")
    try expect(!supportedExtensions.contains("xisf"), "XISF should remain deferred.")
}

func stars(width: Int, height: Int, points: [(Int, Int)]) -> [Float] {
    var image = Array(repeating: Float(0), count: width * height)
    for (y, x) in points {
        image[y * width + x] = 1
        for yy in max(0, y - 1)...min(height - 1, y + 1) {
            for xx in max(0, x - 1)...min(width - 1, x + 1) {
                image[yy * width + xx] = min(image[yy * width + xx] + 0.25, 1)
            }
        }
    }
    return image
}

func rgbData(fromGray gray: [Float]) -> [Float] {
    var out = Array(repeating: Float(0), count: gray.count * 3)
    for pixel in gray.indices {
        out[pixel * 3 + 0] = gray[pixel]
        out[pixel * 3 + 1] = gray[pixel]
        out[pixel * 3 + 2] = gray[pixel]
    }
    return out
}

func makeRGBStarField(width: Int = 96, height: Int = 96) throws -> FloatRGBImage {
    var image = FloatRGBImage(width: width, height: height, repeating: 0.03)
    let points = [
        (height * 18 / 96, width * 20 / 96),
        (height * 32 / 96, width * 70 / 96),
        (height * 45 / 96, width * 40 / 96),
        (height * 72 / 96, width * 60 / 96),
        (height * 80 / 96, width * 24 / 96),
    ]
    for (y, x) in points {
        for yy in max(0, y - 1)...min(height - 1, y + 1) {
            for xx in max(0, x - 1)...min(width - 1, x + 1) {
                image[xx, yy, 0] = 0.55
                image[xx, yy, 1] = 0.60
                image[xx, yy, 2] = 1.00
            }
        }
        for channel in 0..<3 {
            image[x, y, channel] = 1
        }
    }
    return image.clipped()
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MySequatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
