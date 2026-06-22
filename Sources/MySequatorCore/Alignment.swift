import Foundation
import CMySequatorSupport

public struct Shift: Sendable {
    public let dy: Int
    public let dx: Int
    public let peak: Float
}

public func estimateImageTransform(reference: [Float], moving: [Float], width: Int, height: Int, maxDimension: Int = 1200, skyMask: SkyMask? = nil) throws -> ImageTransform {
    guard reference.count == width * height, moving.count == width * height else {
        throw MySequatorError.shapeMismatch("Reference and moving images must have matching dimensions.")
    }
    if let skyMask, skyMask.width == width, skyMask.height == height {
        if let transform = estimateStarSimilarityTransform(reference: reference, moving: moving, width: width, height: height, skyMask: skyMask) {
            return transform
        }
        if let shift = estimateStarTranslation(reference: reference, moving: moving, width: width, height: height, skyMask: skyMask) {
            return .translation(dy: shift.dy, dx: shift.dx, peak: shift.peak)
        }
    }
    if let transform = estimateStarSimilarityTransform(reference: reference, moving: moving, width: width, height: height, skyMask: nil) {
        return transform
    }
    let shift = try estimateTranslation(reference: reference, moving: moving, width: width, height: height, maxDimension: maxDimension, skyMask: nil)
    return .translation(dy: shift.dy, dx: shift.dx, peak: shift.peak)
}

public func estimateTranslation(reference: [Float], moving: [Float], width: Int, height: Int, maxDimension: Int = 1200, skyMask: SkyMask? = nil) throws -> Shift {
    guard reference.count == width * height, moving.count == width * height else {
        throw MySequatorError.shapeMismatch("Reference and moving images must have matching dimensions.")
    }
    if let skyMask, skyMask.width == width, skyMask.height == height,
       let starShift = estimateStarTranslation(reference: reference, moving: moving, width: width, height: height, skyMask: skyMask) {
        return starShift
    }
    if let starShift = estimateStarTranslation(reference: reference, moving: moving, width: width, height: height, skyMask: nil) {
        return starShift
    }

    let cap = min(maxDimension, 512)
    let preparedReference = prepareForCorrelation(reference, width: width, height: height, maxDimension: cap)
    let preparedMoving = prepareForCorrelation(moving, width: width, height: height, maxDimension: cap)
    let scale = preparedReference.scale

    var cDy: Int32 = 0
    var cDx: Int32 = 0
    var cPeak: Float = 0
    let phaseResult = preparedReference.data.withUnsafeBufferPointer { refBuffer in
        preparedMoving.data.withUnsafeBufferPointer { movBuffer in
            msq_phase_correlate_translation(
                refBuffer.baseAddress,
                movBuffer.baseAddress,
                Int32(preparedReference.width),
                Int32(preparedReference.height),
                &cDy,
                &cDx,
                &cPeak
            )
        }
    }
    if phaseResult == 0 {
        return Shift(
            dy: Int((Float(cDy) / scale).rounded()),
            dx: Int((Float(cDx) / scale).rounded()),
            peak: cPeak
        )
    }

    let searchRadiusY = min(preparedReference.height - 1, max(8, preparedReference.height / 3))
    let searchRadiusX = min(preparedReference.width - 1, max(8, preparedReference.width / 3))
    var bestDy = 0
    var bestDx = 0
    var bestScore = -Float.greatestFiniteMagnitude

    for dy in -searchRadiusY...searchRadiusY {
        for dx in -searchRadiusX...searchRadiusX {
            let score = normalizedScore(
                reference: preparedReference.data,
                moving: preparedMoving.data,
                width: preparedReference.width,
                height: preparedReference.height,
                dy: dy,
                dx: dx
            )
            if score > bestScore {
                bestScore = score
                bestDy = dy
                bestDx = dx
            }
        }
    }

    return Shift(
        dy: Int((Float(bestDy) / scale).rounded()),
        dx: Int((Float(bestDx) / scale).rounded()),
        peak: bestScore
    )
}

private struct StarPoint {
    let y: Int
    let x: Int
    let value: Float
}

private func estimateStarTranslation(reference: [Float], moving: [Float], width: Int, height: Int, skyMask: SkyMask?) -> Shift? {
    let referenceStars = detectStarPoints(reference, width: width, height: height, skyMask: skyMask)
    let movingStars = detectStarPoints(moving, width: width, height: height, skyMask: skyMask)
    guard referenceStars.count >= 12, movingStars.count >= 12 else {
        return nil
    }

    let candidateReference = Array(referenceStars.prefix(160))
    let candidateMoving = Array(movingStars.prefix(160))
    let countMoving = Array(movingStars.prefix(500))
    let maxShift = max(80, min(max(width, height) / 12, 600))
    let tolerance = max(3, min(8, max(width, height) / 1200))
    let cellSize = tolerance
    let grid = makeStarGrid(referenceStars.prefix(700), cellSize: cellSize)

    var bestDy = 0
    var bestDx = 0
    var bestCount = 0
    var bestError = Float.greatestFiniteMagnitude

    for ref in candidateReference {
        for mov in candidateMoving {
            let dy = ref.y - mov.y
            let dx = ref.x - mov.x
            guard abs(dy) <= maxShift, abs(dx) <= maxShift else {
                continue
            }
            let score = countMatches(moving: countMoving, grid: grid, dy: dy, dx: dx, tolerance: tolerance, cellSize: cellSize)
            if score.count > bestCount || (score.count == bestCount && score.error < bestError) {
                bestCount = score.count
                bestError = score.error
                bestDy = dy
                bestDx = dx
            }
        }
    }

    guard bestCount >= 12 else {
        return nil
    }

    let refined = refineShift(moving: countMoving, grid: grid, dy: bestDy, dx: bestDx, tolerance: tolerance, cellSize: cellSize)
    let matchRatio = Float(bestCount) / Float(min(referenceStars.count, movingStars.count))
    return Shift(dy: refined.dy, dx: refined.dx, peak: matchRatio)
}

private func estimateStarSimilarityTransform(reference: [Float], moving: [Float], width: Int, height: Int, skyMask: SkyMask?) -> ImageTransform? {
    let referenceStars = detectStarPoints(reference, width: width, height: height, skyMask: skyMask)
    let movingStars = detectStarPoints(moving, width: width, height: height, skyMask: skyMask)
    guard referenceStars.count >= 16, movingStars.count >= 16 else {
        return nil
    }
    guard let shift = estimateStarTranslation(reference: reference, moving: moving, width: width, height: height, skyMask: skyMask) else {
        return nil
    }

    let tolerance = max(3, min(10, max(width, height) / 1000))
    let grid = makeStarGrid(referenceStars.prefix(900), cellSize: tolerance)
    let toleranceSquared = tolerance * tolerance
    var pairs: [(moving: StarPoint, reference: StarPoint)] = []
    pairs.reserveCapacity(300)
    for point in movingStars.prefix(700) {
        if let ref = nearestPoint(
            x: point.x + shift.dx,
            y: point.y + shift.dy,
            grid: grid,
            toleranceSquared: toleranceSquared,
            cellSize: tolerance
        ) {
            pairs.append((moving: point, reference: ref))
        }
    }
    guard pairs.count >= 12 else {
        return nil
    }
    guard let transform = leastSquaresSimilarityTransform(pairs: pairs, fallback: shift) else {
        return nil
    }
    guard transform.scale >= 0.97, transform.scale <= 1.03, abs(transform.rotationRadians) <= 0.06 else {
        return .translation(dy: shift.dy, dx: shift.dx, peak: shift.peak)
    }

    var inliers = 0
    for pair in pairs {
        let x = transform.a * Float(pair.moving.x) - transform.b * Float(pair.moving.y) + transform.tx
        let y = transform.b * Float(pair.moving.x) + transform.a * Float(pair.moving.y) + transform.ty
        let dx = x - Float(pair.reference.x)
        let dy = y - Float(pair.reference.y)
        if dx * dx + dy * dy <= Float(toleranceSquared) {
            inliers += 1
        }
    }
    guard inliers >= 12 else {
        return .translation(dy: shift.dy, dx: shift.dx, peak: shift.peak)
    }
    var out = transform
    out.peak = Float(inliers) / Float(min(referenceStars.count, movingStars.count))
    return out
}

private func leastSquaresSimilarityTransform(pairs: [(moving: StarPoint, reference: StarPoint)], fallback: Shift) -> ImageTransform? {
    guard pairs.count >= 2 else { return nil }
    let count = Float(pairs.count)
    let movingMeanX = pairs.reduce(Float(0)) { $0 + Float($1.moving.x) } / count
    let movingMeanY = pairs.reduce(Float(0)) { $0 + Float($1.moving.y) } / count
    let referenceMeanX = pairs.reduce(Float(0)) { $0 + Float($1.reference.x) } / count
    let referenceMeanY = pairs.reduce(Float(0)) { $0 + Float($1.reference.y) } / count

    var numeratorA: Float = 0
    var numeratorB: Float = 0
    var denominator: Float = 0
    for pair in pairs {
        let mx = Float(pair.moving.x) - movingMeanX
        let my = Float(pair.moving.y) - movingMeanY
        let rx = Float(pair.reference.x) - referenceMeanX
        let ry = Float(pair.reference.y) - referenceMeanY
        numeratorA += mx * rx + my * ry
        numeratorB += mx * ry - my * rx
        denominator += mx * mx + my * my
    }
    guard denominator > 1e-6 else {
        return .translation(dy: fallback.dy, dx: fallback.dx, peak: fallback.peak)
    }

    let a = numeratorA / denominator
    let b = numeratorB / denominator
    let tx = referenceMeanX - a * movingMeanX + b * movingMeanY
    let ty = referenceMeanY - b * movingMeanX - a * movingMeanY
    return ImageTransform(a: a, b: b, tx: tx, ty: ty, peak: fallback.peak)
}

private func detectStarPoints(_ luminance: [Float], width: Int, height: Int, skyMask: SkyMask?) -> [StarPoint] {
    let roiHeight = max(32, min(height, Int((Float(height) * 0.68).rounded())))
    let sampleStep = max(width, height) > 2500 ? 2 : 1
    let sampledWidth = max(1, width / sampleStep)
    let sampledHeight = max(1, roiHeight / sampleStep)
    let radius = 2
    let count = sampledWidth * sampledHeight
    var sampled = Array(repeating: Float(0), count: count)
    for y in 0..<sampledHeight {
        let sourceY = y * sampleStep
        for x in 0..<sampledWidth {
            let sourceX = x * sampleStep
            if let skyMask, skyMask.alpha[sourceY * width + sourceX] < 128 {
                sampled[y * sampledWidth + x] = 0
            } else {
                sampled[y * sampledWidth + x] = luminance[sourceY * width + sourceX]
            }
        }
    }

    var horizontal = Array(repeating: Float(0), count: count)
    var blur = Array(repeating: Float(0), count: count)
    var highpass = Array(repeating: Float(0), count: count)

    for y in 0..<sampledHeight {
        for x in 0..<sampledWidth {
            var sum: Float = 0
            var samples: Float = 0
            for xx in max(0, x - radius)...min(sampledWidth - 1, x + radius) {
                sum += sampled[y * sampledWidth + xx]
                samples += 1
            }
            horizontal[y * sampledWidth + x] = sum / samples
        }
    }

    for y in 0..<sampledHeight {
        for x in 0..<sampledWidth {
            var sum: Float = 0
            var samples: Float = 0
            for yy in max(0, y - radius)...min(sampledHeight - 1, y + radius) {
                sum += horizontal[yy * sampledWidth + x]
                samples += 1
            }
            let index = y * sampledWidth + x
            blur[index] = sum / samples
            highpass[index] = max(sampled[index] - blur[index], 0)
        }
    }

    var samples: [Float] = []
    samples.reserveCapacity(max(1, count / 16))
    let sampleStride = max(1, count / 300_000)
    var i = 0
    while i < highpass.count {
        samples.append(highpass[i])
        i += sampleStride
    }
    let threshold = max(samples.percentile(99.72), 1e-5)

    var points: [StarPoint] = []
    points.reserveCapacity(900)
    let margin = 4
    guard sampledHeight > margin * 2, sampledWidth > margin * 2 else {
        return []
    }
    for y in margin..<(sampledHeight - margin) {
        for x in margin..<(sampledWidth - margin) {
            let index = y * sampledWidth + x
            let value = highpass[index]
            guard value >= threshold else { continue }
            if let skyMask, skyMask.alpha[(y * sampleStep) * width + x * sampleStep] < 128 {
                continue
            }

            var isPeak = true
            peakLoop: for yy in (y - 2)...(y + 2) {
                for xx in (x - 2)...(x + 2) where yy != y || xx != x {
                    if highpass[yy * sampledWidth + xx] > value {
                        isPeak = false
                        break peakLoop
                    }
                }
            }
            if isPeak {
                points.append(StarPoint(y: y * sampleStep, x: x * sampleStep, value: value))
            }
        }
    }

    points.sort { $0.value > $1.value }
    if points.count > 900 {
        points.removeSubrange(900..<points.count)
    }
    return points
}

private func makeStarGrid<S: Sequence>(_ points: S, cellSize: Int) -> [Int64: [StarPoint]] where S.Element == StarPoint {
    var grid: [Int64: [StarPoint]] = [:]
    for point in points {
        let key = gridKey(x: point.x / cellSize, y: point.y / cellSize)
        grid[key, default: []].append(point)
    }
    return grid
}

private func countMatches(moving: [StarPoint], grid: [Int64: [StarPoint]], dy: Int, dx: Int, tolerance: Int, cellSize: Int) -> (count: Int, error: Float) {
    var count = 0
    var error: Float = 0
    let toleranceSquared = tolerance * tolerance
    for point in moving {
        if let distance = nearestDistanceSquared(x: point.x + dx, y: point.y + dy, grid: grid, toleranceSquared: toleranceSquared, cellSize: cellSize) {
            count += 1
            error += sqrt(Float(distance))
        }
    }
    return (count, count > 0 ? error / Float(count) : Float.greatestFiniteMagnitude)
}

private func refineShift(moving: [StarPoint], grid: [Int64: [StarPoint]], dy: Int, dx: Int, tolerance: Int, cellSize: Int) -> (dy: Int, dx: Int) {
    var deltasY: [Float] = []
    var deltasX: [Float] = []
    let toleranceSquared = tolerance * tolerance
    for point in moving {
        if let ref = nearestPoint(x: point.x + dx, y: point.y + dy, grid: grid, toleranceSquared: toleranceSquared, cellSize: cellSize) {
            deltasY.append(Float(ref.y - point.y))
            deltasX.append(Float(ref.x - point.x))
        }
    }
    guard deltasY.count >= 6 else {
        return (dy, dx)
    }
    return (Int(deltasY.median().rounded()), Int(deltasX.median().rounded()))
}

private func nearestDistanceSquared(x: Int, y: Int, grid: [Int64: [StarPoint]], toleranceSquared: Int, cellSize: Int) -> Int? {
    nearestPoint(x: x, y: y, grid: grid, toleranceSquared: toleranceSquared, cellSize: cellSize).map {
        let ddx = $0.x - x
        let ddy = $0.y - y
        return ddx * ddx + ddy * ddy
    }
}

private func nearestPoint(x: Int, y: Int, grid: [Int64: [StarPoint]], toleranceSquared: Int, cellSize: Int) -> StarPoint? {
    let cellX = x / cellSize
    let cellY = y / cellSize
    var best: StarPoint?
    var bestDistance = toleranceSquared + 1
    for yy in (cellY - 1)...(cellY + 1) {
        for xx in (cellX - 1)...(cellX + 1) {
            for point in grid[gridKey(x: xx, y: yy), default: []] {
                let dx = point.x - x
                let dy = point.y - y
                let distance = dx * dx + dy * dy
                if distance <= toleranceSquared, distance < bestDistance {
                    bestDistance = distance
                    best = point
                }
            }
        }
    }
    return best
}

private func gridKey(x: Int, y: Int) -> Int64 {
    (Int64(y) << 32) ^ Int64(x & 0xffff_ffff)
}

public func translateWithMask(_ image: FloatRGBImage, dy: Int, dx: Int) -> (FloatRGBImage, [UInt8]) {
    var shifted = FloatRGBImage(width: image.width, height: image.height)
    var mask = Array(repeating: UInt8(0), count: image.width * image.height)

    let srcY0 = max(0, -dy)
    let srcY1 = min(image.height, image.height - dy)
    let dstY0 = max(0, dy)
    let srcX0 = max(0, -dx)
    let srcX1 = min(image.width, image.width - dx)
    let dstX0 = max(0, dx)

    guard srcY1 > srcY0, srcX1 > srcX0 else {
        return (shifted, mask)
    }

    for sy in srcY0..<srcY1 {
        let dyOut = dstY0 + (sy - srcY0)
        for sx in srcX0..<srcX1 {
            let dxOut = dstX0 + (sx - srcX0)
            mask[dyOut * image.width + dxOut] = 1
            for channel in 0..<3 {
                shifted[dxOut, dyOut, channel] = image[sx, sy, channel]
            }
        }
    }
    return (shifted, mask)
}

private struct PreparedGray {
    let data: [Float]
    let width: Int
    let height: Int
    let scale: Float
}

private func prepareForCorrelation(_ image: [Float], width: Int, height: Int, maxDimension: Int) -> PreparedGray {
    let longest = max(width, height)
    let requestedScale = longest > maxDimension ? Float(maxDimension) / Float(longest) : 1
    let requestedWidth = max(32, Int((Float(width) * requestedScale).rounded()))
    let requestedHeight = max(32, Int((Float(height) * requestedScale).rounded()))
    let newWidth = nearestPowerOfTwo(requestedWidth)
    let newHeight = nearestPowerOfTwo(requestedHeight)
    let scale = min(Float(newWidth) / Float(width), Float(newHeight) / Float(height))
    var work = resizeGray(image, width: width, height: height, newWidth: newWidth, newHeight: newHeight)
    let median = work.median()
    for i in work.indices {
        work[i] -= median
    }
    let spread = work.map { abs($0) }.percentile(95)
    if spread > 0 {
        for i in work.indices {
            work[i] = min(max(work[i] / spread, -1), 1)
        }
    }
    for y in 0..<newHeight {
        let wy = hanning(index: y, count: newHeight)
        for x in 0..<newWidth {
            work[y * newWidth + x] *= wy * hanning(index: x, count: newWidth)
        }
    }
    return PreparedGray(data: work, width: newWidth, height: newHeight, scale: scale)
}

private func nearestPowerOfTwo(_ value: Int) -> Int {
    let clamped = max(value, 32)
    var lower = 1
    while lower * 2 <= clamped {
        lower *= 2
    }
    let upper = lower * 2
    return (clamped - lower) <= (upper - clamped) ? lower : upper
}

private func normalizedScore(reference: [Float], moving: [Float], width: Int, height: Int, dy: Int, dx: Int) -> Float {
    let srcY0 = max(0, -dy)
    let srcY1 = min(height, height - dy)
    let dstY0 = max(0, dy)
    let srcX0 = max(0, -dx)
    let srcX1 = min(width, width - dx)
    let dstX0 = max(0, dx)

    guard srcY1 > srcY0, srcX1 > srcX0 else { return -Float.greatestFiniteMagnitude }

    var dot: Float = 0
    var refEnergy: Float = 0
    var movEnergy: Float = 0

    for sy in srcY0..<srcY1 {
        let ry = dstY0 + (sy - srcY0)
        for sx in srcX0..<srcX1 {
            let rx = dstX0 + (sx - srcX0)
            let refValue = reference[ry * width + rx]
            let movValue = moving[sy * width + sx]
            dot += refValue * movValue
            refEnergy += refValue * refValue
            movEnergy += movValue * movValue
        }
    }
    let denominator = sqrt(max(refEnergy * movEnergy, 1e-12))
    return dot / denominator
}

private func resizeGray(_ image: [Float], width: Int, height: Int, newWidth: Int, newHeight: Int) -> [Float] {
    if width == newWidth, height == newHeight {
        return image
    }
    var out = Array(repeating: Float(0), count: newWidth * newHeight)
    for y in 0..<newHeight {
        let sourceY = Float(y) * Float(height - 1) / Float(max(newHeight - 1, 1))
        let y0 = Int(sourceY.rounded(.down))
        let y1 = min(y0 + 1, height - 1)
        let ty = sourceY - Float(y0)
        for x in 0..<newWidth {
            let sourceX = Float(x) * Float(width - 1) / Float(max(newWidth - 1, 1))
            let x0 = Int(sourceX.rounded(.down))
            let x1 = min(x0 + 1, width - 1)
            let tx = sourceX - Float(x0)
            let a = image[y0 * width + x0] * (1 - tx) + image[y0 * width + x1] * tx
            let b = image[y1 * width + x0] * (1 - tx) + image[y1 * width + x1] * tx
            out[y * newWidth + x] = a * (1 - ty) + b * ty
        }
    }
    return out
}

private func hanning(index: Int, count: Int) -> Float {
    guard count > 1 else { return 1 }
    return 0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(count - 1))
}
