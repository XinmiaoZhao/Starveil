import XCTest
@testable import MySequatorCore

final class AlignmentTests: XCTestCase {
    func testEstimateTranslationReturnsShiftToApplyToMoving() throws {
        let reference = stars(width: 128, height: 128, points: [(30, 42), (65, 80), (90, 25), (101, 104)])
        let movingRGB = try FloatRGBImage(width: 128, height: 128, data: rgbData(fromGray: reference))
        let shifted = translateWithMask(movingRGB, dy: 7, dx: -5).0

        let shift = try estimateTranslation(reference: reference, moving: shifted.luminance(), width: 128, height: 128, maxDimension: 128)

        XCTAssertEqual(shift.dy, -7)
        XCTAssertEqual(shift.dx, 5)
    }

    func testTranslateWithMaskDoesNotWrap() {
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

        XCTAssertEqual(topRows, 0)
        XCTAssertEqual(rightColumns, 0)
        XCTAssertEqual(mask.filter { $0 != 0 }.count, 30)
    }

    func testWideAngleAlignmentCanUsePolynomialWarp() throws {
        let width = 160
        let height = 120
        var referencePoints: [(Int, Int)] = []
        for y in stride(from: 18, through: 98, by: 16) {
            for x in stride(from: 18, through: 142, by: 18) {
                referencePoints.append((y, x))
            }
        }
        let movingPoints = referencePoints.map { point -> (Int, Int) in
            let normalizedX = Float(point.1 - width / 2) / Float(width)
            let normalizedY = Float(point.0 - height / 2) / Float(width)
            let dx = Int((normalizedX * normalizedX * 7 + normalizedY * 2).rounded())
            let dy = Int((normalizedX * normalizedY * 6).rounded())
            return (point.0 + dy, point.1 + dx)
        }
        let reference = stars(width: width, height: height, points: referencePoints)
        let moving = stars(width: width, height: height, points: movingPoints)

        let transform = try estimateImageTransform(
            reference: reference,
            moving: moving,
            width: width,
            height: height,
            maxDimension: width,
            alignmentModel: .wideAngle
        )

        XCTAssertTrue(transform.usesPolynomialWarp)
        for (referencePoint, movingPoint) in zip(referencePoints.prefix(8), movingPoints.prefix(8)) {
            let source = try XCTUnwrap(transform.sourcePoint(forDestinationX: Float(referencePoint.1), y: Float(referencePoint.0)))
            XCTAssertEqual(source.x, Float(movingPoint.1), accuracy: 1.1)
            XCTAssertEqual(source.y, Float(movingPoint.0), accuracy: 1.1)
        }
    }
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
