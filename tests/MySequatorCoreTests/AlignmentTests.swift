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
