import Foundation
import XCTest
@testable import MySequatorCore

final class PipelineTests: XCTestCase {
    func testStackImagesAlignsAndAverages() throws {
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

        XCTAssertEqual(result.image.width, base.width)
        XCTAssertEqual(result.image.height, base.height)
        XCTAssertEqual(result.alignments.count, 4)
        XCTAssertGreaterThan(result.image.data.max() ?? 0, 0.5)
    }

    func testDefaultOutputIsNotStretched() throws {
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

        XCTAssertLessThan(result.image.data.max() ?? 1, 0.28)
    }

    func testAutoStretchIsOptional() throws {
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

        XCTAssertGreaterThan(result.image.data.max() ?? 0, 0.85)
    }

    func testTIFFRoundTripPreserves16BitRGB() throws {
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

        XCTAssertEqual(loaded.width, image.width)
        XCTAssertEqual(loaded.height, image.height)
        XCTAssertEqual(loaded.data[0], 0.25, accuracy: 1.0 / 65535.0)
        XCTAssertEqual(loaded.data[1], 0.5, accuracy: 1.0 / 65535.0)
        XCTAssertEqual(loaded.data[2], 0.75, accuracy: 1.0 / 65535.0)
    }

    func testFloat32TIFFRoundTripPreservesLinearValues() throws {
        let temp = try temporaryDirectory()
        var image = FloatRGBImage(width: 4, height: 4)
        for i in image.data.indices {
            image.data[i] = Float(i) / 10.0
        }
        let path = temp.appendingPathComponent("float-master.tiff")

        try saveImage(image, to: path, options: SaveOptions(tiffDepth: .float32, clip: false))
        let loaded = try loadImage(path)

        XCTAssertEqual(loaded.data[12], image.data[12], accuracy: 1e-6)
        XCTAssertGreaterThan(loaded.data.max() ?? 0, 1)
    }

    func testRawExtensionsAreAdvertisedButXISFIsDeferred() {
        XCTAssertTrue(rawExtensions.contains("dng"))
        XCTAssertTrue(supportedExtensions.contains("cr3"))
        XCTAssertFalse(supportedExtensions.contains("xisf"))
    }

    func testSwiftAndPythonPipelineAgreeOnSyntheticInputWhenPythonIsAvailable() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let python = root.appendingPathComponent(".conda/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw XCTSkip("Local conda Python is not available.")
        }

        let temp = try temporaryDirectory()
        let base = try makeRGBStarField(width: 40, height: 40)
        var paths: [URL] = []
        for index in 0..<4 {
            let path = temp.appendingPathComponent("compare_\(index).tiff")
            try saveImage(base, to: path)
            paths.append(path)
        }

        let swiftResult = try stackImages(paths, options: StackOptions(mode: .mean))
        let pythonOut = temp.appendingPathComponent("python-out.tiff")

        let process = Process()
        process.executableURL = python
        process.currentDirectoryURL = root
        process.arguments = ["-m", "mysequator", "--output", pythonOut.path, "--mode", "mean"] + paths.map(\.path)
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let pythonResult = try loadImage(pythonOut)
        XCTAssertEqual(swiftResult.image.width, pythonResult.width)
        XCTAssertEqual(swiftResult.image.height, pythonResult.height)
        let maxDiff = zip(swiftResult.image.data, pythonResult.data).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxDiff, 1.0 / 65535.0)
    }
}

private func makeRGBStarField(width: Int = 96, height: Int = 96) throws -> FloatRGBImage {
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

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MySequatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
