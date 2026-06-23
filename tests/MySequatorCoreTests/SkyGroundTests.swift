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

    func testEdgeRefinementPullsBottomConnectedDarkForegroundIntoGround() throws {
        let fixture = try makeMaskRefinementFixture()

        let refined = fixture.mask.refinedForForegroundEdges(
            baseImage: fixture.image,
            options: SkyMaskOptions(skyGuardPixels: 0, featherPixels: 2, boundaryProtectionPixels: 28)
        )

        XCTAssertEqual(fixture.mask[30, 24], 255)
        XCTAssertLessThan(refined[30, 24], 128)
        XCTAssertLessThan(refined[30, 34], 128)
    }

    func testEdgeRefinementDoesNotPullIsolatedDarkSkyPatchIntoGround() throws {
        let fixture = try makeMaskRefinementFixture()

        let refined = fixture.mask.refinedForForegroundEdges(
            baseImage: fixture.image,
            options: SkyMaskOptions(skyGuardPixels: 0, featherPixels: 2, boundaryProtectionPixels: 28)
        )

        XCTAssertEqual(fixture.mask[8, 20], 255)
        XCTAssertEqual(refined[8, 20], 255)
        XCTAssertEqual(refined[12, 30], 255)
    }

    func testEdgeRefinementCanBeDisabled() throws {
        let fixture = try makeMaskRefinementFixture()

        let refined = fixture.mask.refinedForForegroundEdges(
            baseImage: fixture.image,
            options: SkyMaskOptions(
                skyGuardPixels: 0,
                featherPixels: 2,
                refineEdges: false,
                boundaryProtectionPixels: 28
            )
        )

        XCTAssertEqual(refined.alpha, fixture.mask.alpha)
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

    func testWarpImageWithMaskRejectsAnyMaskedBilinearTap() throws {
        var image = FloatRGBImage(width: 5, height: 5)
        for y in 0..<5 {
            for x in 0..<5 {
                image[x, y, 0] = Float(x)
                image[x, y, 1] = Float(y)
                image[x, y, 2] = 1
            }
        }
        var mask = Array(repeating: UInt8(1), count: 25)
        mask[1 * 5 + 2] = 0

        let transform = ImageTransform(a: 1, b: 0, tx: -0.4, ty: 0)
        let warped = warpImageWithMask(image, transform: transform, sourceMask: mask)

        XCTAssertEqual(warped.1[1 * 5 + 1], 0)
        XCTAssertEqual(warped.0[1, 1, 0], 0, accuracy: 0.001)
        XCTAssertEqual(warped.1[3 * 5 + 1], 1)
        XCTAssertEqual(warped.0[1, 3, 0], Float(1.4), accuracy: 0.001)
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

    func testSkyFreezeGroundRefinedMaskKeepsDarkForegroundEdge() throws {
        let temp = try temporaryDirectory()
        let fixture = try makeForegroundEdgeStackFixture()
        var paths: [URL] = []
        for (index, frame) in fixture.frames.enumerated() {
            let path = temp.appendingPathComponent("edge_\(index).tiff")
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
                skyMaskOptions: SkyMaskOptions(
                    skyGuardPixels: 0,
                    featherPixels: 2,
                    boundaryProtectionPixels: 32
                )
            )
        )

        XCTAssertLessThan(result.skyMask?[fixture.branch.x, fixture.branch.y] ?? 255, 128)
        XCTAssertEqual(result.image[fixture.branch.x, fixture.branch.y, 0], fixture.base[fixture.branch.x, fixture.branch.y, 0], accuracy: 2.0 / 65535.0)
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
            try stackImages([path], options: StackOptions(mode: .trails, sceneMode: .skyAndGround))
        )
    }

    func testSkyFreezeGroundAllowsStarTrailsWithoutAligningSky() throws {
        let temp = try temporaryDirectory()
        let fixture = try makeSkyGroundFixture()
        var paths: [URL] = []
        for (index, frame) in fixture.frames.enumerated() {
            let path = temp.appendingPathComponent("trails_\(index).tiff")
            try saveImage(frame, to: path)
            paths.append(path)
        }

        let result = try stackImages(
            paths,
            options: StackOptions(
                mode: .trails,
                sceneMode: .skyFreezeGround,
                basePath: paths[0],
                skyMask: fixture.mask,
                skyMaskOptions: SkyMaskOptions(skyGuardPixels: 0, featherPixels: 2)
            )
        )

        XCTAssertTrue(result.alignments.allSatisfy { $0.dx == 0 && $0.dy == 0 })
        XCTAssertEqual(result.image[10, 50, 0], fixture.base[10, 50, 0], accuracy: 2.0 / 65535.0)
        XCTAssertGreaterThan(result.image[fixture.star.x, fixture.star.y, 2], 0.45)
    }
}

private func makeMaskRefinementFixture() throws -> (image: FloatRGBImage, mask: SkyMask) {
    let width = 64
    let height = 48
    let horizon = 34
    var image = FloatRGBImage(width: width, height: height, repeating: 0.025)
    for y in horizon..<height {
        for x in 0..<width {
            image[x, y, 0] = 0.08
            image[x, y, 1] = 0.075
            image[x, y, 2] = 0.07
        }
    }

    for y in 20..<height {
        for x in 29...31 {
            image[x, y, 0] = 0.004
            image[x, y, 1] = 0.004
            image[x, y, 2] = 0.004
        }
    }
    for y in 18...21 {
        for x in 7...10 {
            image[x, y, 0] = 0.004
            image[x, y, 1] = 0.004
            image[x, y, 2] = 0.004
        }
    }

    var alpha = Array(repeating: UInt8(0), count: width * height)
    for y in 0..<horizon {
        for x in 0..<width {
            alpha[y * width + x] = 255
        }
    }
    return (image, try SkyMask(width: width, height: height, alpha: alpha))
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

private func makeForegroundEdgeStackFixture() throws -> (base: FloatRGBImage, frames: [FloatRGBImage], mask: SkyMask, branch: (x: Int, y: Int)) {
    let width = 96
    let height = 64
    let horizon = 42
    let branch = (x: 36, y: 29)
    var base = FloatRGBImage(width: width, height: height, repeating: 0.025)

    for y in horizon..<height {
        for x in 0..<width {
            base[x, y, 0] = 0.11
            base[x, y, 1] = 0.10
            base[x, y, 2] = 0.08
        }
    }

    var starPoints: [(x: Int, y: Int)] = []
    for row in 0..<4 {
        for column in 0..<6 {
            starPoints.append((x: 10 + column * 13 + (row % 2) * 5, y: 7 + row * 8))
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

    paintStaticBranch(&base, x: branch.x, fromY: 24)

    var alpha = Array(repeating: UInt8(0), count: width * height)
    for y in 0..<horizon {
        for x in 0..<width {
            alpha[y * width + x] = 255
        }
    }
    let mask = try SkyMask(width: width, height: height, alpha: alpha)

    let shifts = [(0, 0), (2, -1), (-2, 3), (1, 2)]
    let skyOnly = skyOnlyImage(baseWithoutBranch(base, branchX: branch.x, fromY: 24), horizon: horizon)
    var frames: [FloatRGBImage] = []
    for shift in shifts {
        let shiftedSky = translateWithMask(skyOnly, dy: shift.0, dx: shift.1).0
        var frame = base
        for y in 0..<horizon {
            for x in 0..<width {
                for channel in 0..<3 {
                    frame[x, y, channel] = shiftedSky[x, y, channel]
                }
            }
        }
        paintStaticBranch(&frame, x: branch.x, fromY: 24)
        frames.append(frame)
    }

    return (base, frames, mask, branch)
}

private func baseWithoutBranch(_ image: FloatRGBImage, branchX: Int, fromY: Int) -> FloatRGBImage {
    var out = image
    for y in fromY..<out.height {
        for x in max(0, branchX - 1)...min(out.width - 1, branchX + 1) {
            if y < 42 {
                out[x, y, 0] = 0.025
                out[x, y, 1] = 0.025
                out[x, y, 2] = 0.025
            }
        }
    }
    return out
}

private func paintStaticBranch(_ image: inout FloatRGBImage, x branchX: Int, fromY: Int) {
    for y in fromY..<image.height {
        for x in max(0, branchX - 1)...min(image.width - 1, branchX + 1) {
            image[x, y, 0] = 0.004
            image[x, y, 1] = 0.004
            image[x, y, 2] = 0.004
        }
    }
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
