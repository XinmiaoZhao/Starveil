import Foundation
import XCTest
@testable import MySequatorCore

final class SkyGroundTests: XCTestCase {
    func testSkyMaskRoundTrip() throws {
        let temp = try temporaryDirectory()
        var alpha = Array(repeating: UInt8(0), count: 12 * 8)
        for y in 0..<4 {
            for x in 0..<12 {
                alpha[y * 12 + x] = UInt8((x + y) * 8)
            }
        }
        let mask = try SkyMask(width: 12, height: 8, alpha: alpha)
        let path = temp.appendingPathComponent("mask.png")

        try saveSkyMask(mask, to: path)
        let loaded = try loadSkyMask(path)

        XCTAssertEqual(loaded.width, mask.width)
        XCTAssertEqual(loaded.height, mask.height)
        XCTAssertEqual(loaded.alpha, mask.alpha)
    }

    func testInwardFeatherKeepsGroundAtZero() throws {
        var alpha = Array(repeating: UInt8(0), count: 10 * 10)
        for y in 0..<5 {
            for x in 0..<10 {
                alpha[y * 10 + x] = 255
            }
        }
        let mask = try SkyMask(width: 10, height: 10, alpha: alpha)

        let feathered = mask.inwardFeatheredAlpha(guardPixels: 1, featherPixels: 3)

        XCTAssertEqual(feathered[5 * 10 + 4], 0)
        XCTAssertEqual(feathered[4 * 10 + 4], 0)
        XCTAssertGreaterThan(feathered[3 * 10 + 4], 0)
        XCTAssertEqual(feathered[0 * 10 + 4], 1, accuracy: 0.001)
    }

    func testWarpImageWithMaskDoesNotWrapAndInterpolates() throws {
        var image = FloatRGBImage(width: 5, height: 5)
        for y in 0..<5 {
            for x in 0..<5 {
                image[x, y, 0] = Float(x)
                image[x, y, 1] = Float(y)
                image[x, y, 2] = 1
            }
        }
        var mask = Array(repeating: UInt8(1), count: 25)
        mask[2 * 5 + 2] = 0

        let warped = warpImageWithMask(image, transform: .translation(dy: 1, dx: -1), sourceMask: mask)

        XCTAssertEqual(warped.1[3 * 5 + 1], 0)
        XCTAssertEqual(warped.1[1 * 5 + 0], 1)
        XCTAssertEqual(warped.0[0, 1, 0], 1, accuracy: 0.001)
        XCTAssertEqual(warped.0[0, 1, 1], 0, accuracy: 0.001)
    }

    func testSkyFreezeGroundKeepsGroundFromBaseAndAlignsSky() throws {
        let temp = try temporaryDirectory()
        let fixture = try makeSkyGroundFixture()
        var paths: [URL] = []
        for (index, frame) in fixture.frames.enumerated() {
            let path = temp.appendingPathComponent("freeze_\(index).tiff")
            try saveImage(frame, to: path)
            paths.append(path)
        }

        let result = try stackImages(
            paths,
            options: StackOptions(
                mode: .mean,
                sceneMode: .skyFreezeGround,
                basePath: paths[0],
                skyMask: fixture.mask,
                skyMaskOptions: SkyMaskOptions(skyGuardPixels: 0, featherPixels: 2)
            )
        )

        XCTAssertEqual(result.alignments.count, paths.count)
        XCTAssertEqual(result.image[10, 50, 0], fixture.base[10, 50, 0], accuracy: 2.0 / 65535.0)
        XCTAssertGreaterThan(result.image[fixture.star.x, fixture.star.y, 2], 0.45)
    }

    func testSkyAndGroundStacksGroundWithoutMovingIt() throws {
        let temp = try temporaryDirectory()
        let fixture = try makeSkyGroundFixture(addGroundOffsets: true)
        var paths: [URL] = []
        for (index, frame) in fixture.frames.enumerated() {
            let path = temp.appendingPathComponent("ground_\(index).tiff")
            try saveImage(frame, to: path)
            paths.append(path)
        }

        let result = try stackImages(
            paths,
            options: StackOptions(
                mode: .mean,
                sceneMode: .skyAndGround,
                basePath: paths[0],
                skyMask: fixture.mask,
                skyMaskOptions: SkyMaskOptions(skyGuardPixels: 0, featherPixels: 2)
            )
        )

        let expectedGround = fixture.frames.map { $0[20, 52, 1] }.reduce(0, +) / Float(fixture.frames.count)
        XCTAssertEqual(result.image[20, 52, 1], expectedGround, accuracy: 3.0 / 65535.0)
        XCTAssertGreaterThan(result.image[fixture.star.x, fixture.star.y, 2], 0.45)
    }

    func testTrailsRejectsSkyGroundSceneMode() throws {
        let image = FloatRGBImage(width: 24, height: 24, repeating: 0.1)
        let temp = try temporaryDirectory()
        let path = temp.appendingPathComponent("frame.tiff")
        try saveImage(image, to: path)

        XCTAssertThrowsError(
            try stackImages([path], options: StackOptions(mode: .trails, sceneMode: .skyFreezeGround))
        )
    }
}

private func makeSkyGroundFixture(addGroundOffsets: Bool = false) throws -> (base: FloatRGBImage, frames: [FloatRGBImage], mask: SkyMask, star: (x: Int, y: Int)) {
    let width = 96
    let height = 64
    let horizon = 42
    var base = FloatRGBImage(width: width, height: height, repeating: 0.02)
    for y in horizon..<height {
        for x in 0..<width {
            base[x, y, 0] = 0.12 + Float(x) * 0.0005
            base[x, y, 1] = 0.10 + Float(y - horizon) * 0.001
            base[x, y, 2] = 0.08
        }
    }

    var starPoints: [(x: Int, y: Int)] = []
    for row in 0..<4 {
        for column in 0..<6 {
            starPoints.append((x: 9 + column * 14 + (row % 2) * 4, y: 7 + row * 8))
        }
    }
    for point in starPoints {
        for yy in max(0, point.y - 1)...min(height - 1, point.y + 1) {
            for xx in max(0, point.x - 1)...min(width - 1, point.x + 1) {
                base[xx, yy, 0] = 0.45
                base[xx, yy, 1] = 0.50
                base[xx, yy, 2] = 0.85
            }
        }
        base[point.x, point.y, 0] = 0.80
        base[point.x, point.y, 1] = 0.85
        base[point.x, point.y, 2] = 1.00
    }

    var alpha = Array(repeating: UInt8(0), count: width * height)
    for y in 0..<horizon {
        for x in 0..<width {
            alpha[y * width + x] = 255
        }
    }
    let mask = try SkyMask(width: width, height: height, alpha: alpha)

    let shifts = [(0, 0), (2, -1), (-2, 3), (1, 2)]
    let skyOnly = skyOnlyImage(base, horizon: horizon)
    var frames: [FloatRGBImage] = []
    for (index, shift) in shifts.enumerated() {
        let shiftedSky = translateWithMask(skyOnly, dy: shift.0, dx: shift.1).0
        var frame = base
        for y in 0..<horizon {
            for x in 0..<width {
                for channel in 0..<3 {
                    frame[x, y, channel] = shiftedSky[x, y, channel]
                }
            }
        }
        if addGroundOffsets {
            let offset = Float(index) * 0.01
            for y in horizon..<height {
                for x in 0..<width {
                    frame[x, y, 1] = min(frame[x, y, 1] + offset, 1)
                }
            }
        }
        frames.append(frame)
    }

    return (base: base, frames: frames, mask: mask, star: starPoints[7])
}

private func skyOnlyImage(_ image: FloatRGBImage, horizon: Int) -> FloatRGBImage {
    var out = FloatRGBImage(width: image.width, height: image.height, repeating: 0.02)
    for y in 0..<horizon {
        for x in 0..<image.width {
            for channel in 0..<3 {
                out[x, y, channel] = image[x, y, channel]
            }
        }
    }
    return out
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MySequatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
