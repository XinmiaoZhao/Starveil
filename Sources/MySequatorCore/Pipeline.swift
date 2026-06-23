import Foundation
import CMySequatorSupport

public func stackImages(
    _ imagePaths: [URL],
    options originalOptions: StackOptions = StackOptions(),
    progress: ProgressCallback? = nil
) throws -> StackResult {
    guard !imagePaths.isEmpty else {
        throw MySequatorError.invalidOption("Add at least one star image.")
    }

    var options = originalOptions
    if options.linearMaster {
        options.outputStretch = .none
        options.reduceLightPollution = false
        options.enhanceStars = false
    }
    if options.sceneMode == .skyAndGround, options.mode == .trails {
        throw MySequatorError.invalidOption("Star-trail mode is only supported for full-frame or sky-freeze-ground scene composition.")
    }

    var paths = imagePaths
    let basePath = options.basePath ?? paths[paths.count / 2]
    if !paths.contains(basePath) {
        paths.insert(basePath, at: 0)
    }

    report(progress, "Preparing calibration frames", 0.02)
    let dark = try medianFrame(options.darkPaths, rawOptions: options.rawOptions)
    let flat = try medianFrame(options.flatPaths, rawOptions: options.rawOptions)

    report(progress, "Loading base frame \(basePath.lastPathComponent)", 0.08)
    let base = try calibrate(loadImage(basePath, rawOptions: options.rawOptions), dark: dark, flat: flat)
    let baseGray = base.luminance()
    report(progress, "Estimated working memory \(formatByteCount(estimateStackWorkingMemoryBytes(width: base.width, height: base.height, frameCount: paths.count, mode: options.mode, sceneMode: options.sceneMode)))", 0.09)

    if options.sceneMode != .fullFrame {
        return try stackSkyGroundImages(
            paths,
            basePath: basePath,
            base: base,
            baseGray: baseGray,
            dark: dark,
            flat: flat,
            options: options,
            progress: progress
        )
    }

    var alignedFrames: [FloatRGBImage] = []
    var masks: [[UInt8]] = []
    var alignments: [AlignmentInfo] = []

    for (index, path) in paths.enumerated() {
        let fraction = 0.1 + 0.68 * (Double(index) / Double(max(paths.count, 1)))
        let frame: FloatRGBImage
        if path == basePath {
            report(progress, "Using base frame \(path.lastPathComponent)", fraction)
            frame = base
        } else {
            report(progress, "Loading \(path.lastPathComponent)", fraction)
            frame = try calibrate(loadImage(path, rawOptions: options.rawOptions), dark: dark, flat: flat)
        }
        guard frame.hasSameShape(as: base) else {
            throw MySequatorError.shapeMismatch("\(path.lastPathComponent) has shape \(frame.width)x\(frame.height), expected \(base.width)x\(base.height).")
        }
        report(progress, "Aligning \(path.lastPathComponent)", min(fraction + 0.04, 0.80))

        let dy: Int
        let dx: Int
        let peak: Float
        let aligned: FloatRGBImage
        let mask: [UInt8]

        if path == basePath || options.mode == .trails {
            dy = 0
            dx = 0
            peak = 1
            aligned = frame
            mask = Array(repeating: 1, count: frame.pixelCount)
            alignments.append(AlignmentInfo(path: path, dy: dy, dx: dx, peak: peak, transform: .identity()))
        } else {
            let transform = try estimateImageTransform(
                reference: baseGray,
                moving: frame.luminance(),
                width: frame.width,
                height: frame.height,
                maxDimension: options.alignmentMaxDimension,
                alignmentModel: options.alignmentModel
            )
            dy = transform.dy
            dx = transform.dx
            peak = transform.peak
            if transform.isIntegerTranslation {
                let translated = translateWithMask(frame, dy: dy, dx: dx)
                aligned = translated.0
                mask = translated.1
            } else {
                let warped = warpImageWithMask(frame, transform: transform)
                aligned = warped.0
                mask = warped.1
            }
            alignments.append(AlignmentInfo(path: path, dy: dy, dx: dx, peak: peak, transform: transform))
        }

        alignedFrames.append(aligned)
        masks.append(mask)
    }

    report(progress, "Stacking aligned frames", 0.82)
    var stacked = try compose(alignedFrames, masks: masks, options: options)

    report(progress, "Applying post-processing", 0.9)
    if options.reduceLightPollution {
        stacked = reduceLightPollution(stacked, strength: options.lightPollutionStrength)
    }
    if options.enhanceStars {
        stacked = enhanceStars(stacked, strength: options.starEnhancementStrength)
    }
    switch options.outputStretch {
    case .none:
        break
    case .auto:
        stacked = applyAutoBrightness(stacked)
    case .hdr:
        stacked = applyHDRStretch(stacked)
    }

    report(progress, "Done", 1.0)
    return StackResult(image: stacked.clipped(), basePath: basePath, alignments: alignments)
}

private func compose(_ frames: [FloatRGBImage], masks: [[UInt8]], options: StackOptions) throws -> FloatRGBImage {
    guard let first = frames.first else {
        throw MySequatorError.invalidOption("No frames to compose.")
    }
    if frames.count == 1 {
        return first
    }
    if options.mode == .trails {
        var out = first
        for frame in frames.dropFirst() {
            out.data.withUnsafeMutableBufferPointer { outBuffer in
                frame.data.withUnsafeBufferPointer { frameBuffer in
                    msq_accumulate_max_rgb(frameBuffer.baseAddress, Int32(frame.data.count), outBuffer.baseAddress)
                }
            }
        }
        return out
    }
    if options.mode == .mean || frames.count < 4 {
        return maskedMean(frames, masks: masks)
    }
    if options.mode == .sigma {
        return sigmaClippedMean(frames, masks: masks, sigma: options.sigma)
    }
    throw MySequatorError.invalidOption("Unknown composition mode.")
}

private func stackSkyGroundImages(
    _ paths: [URL],
    basePath: URL,
    base: FloatRGBImage,
    baseGray: [Float],
    dark: FloatRGBImage?,
    flat: FloatRGBImage?,
    options: StackOptions,
    progress: ProgressCallback?
) throws -> StackResult {
    let initialSkyMask: SkyMask
    if let provided = options.skyMask {
        guard provided.hasSameShape(as: base) else {
            throw MySequatorError.shapeMismatch("Sky mask has shape \(provided.width)x\(provided.height), expected \(base.width)x\(base.height).")
        }
        initialSkyMask = provided
    } else {
        report(progress, "Generating automatic sky mask", 0.10)
        initialSkyMask = try autoSkyMask(for: base, options: options.skyMaskOptions)
    }

    let skyMask: SkyMask
    if options.skyMaskOptions.refineEdges {
        report(progress, "Refining sky mask edges", 0.11)
        skyMask = initialSkyMask.refinedForForegroundEdges(baseImage: base, options: options.skyMaskOptions)
    } else {
        skyMask = initialSkyMask
    }

    let skySourceMask = skyMask.erodedSkyMask(guardPixels: options.skyMaskOptions.skyGuardPixels)
    let groundSourceMask = skyMask.groundMask()
    let baseBlendAlpha = skyMask.inwardFeatheredAlpha(
        guardPixels: options.skyMaskOptions.skyGuardPixels,
        featherPixels: options.skyMaskOptions.featherPixels
    )

    var skyFrames: [FloatRGBImage] = []
    var skyMasks: [[UInt8]] = []
    var groundFrames: [FloatRGBImage] = []
    var groundMasks: [[UInt8]] = []
    var alignments: [AlignmentInfo] = []

    for (index, path) in paths.enumerated() {
        let fraction = 0.12 + 0.64 * (Double(index) / Double(max(paths.count, 1)))
        let frame: FloatRGBImage
        if path == basePath {
            report(progress, "Using base frame \(path.lastPathComponent)", fraction)
            frame = base
        } else {
            report(progress, "Loading \(path.lastPathComponent)", fraction)
            frame = try calibrate(loadImage(path, rawOptions: options.rawOptions), dark: dark, flat: flat)
        }
        guard frame.hasSameShape(as: base) else {
            throw MySequatorError.shapeMismatch("\(path.lastPathComponent) has shape \(frame.width)x\(frame.height), expected \(base.width)x\(base.height).")
        }

        report(progress, "Aligning sky \(path.lastPathComponent)", min(fraction + 0.04, 0.80))
        let transform: ImageTransform
        if path == basePath || options.mode == .trails {
            transform = .identity()
        } else {
            transform = try estimateImageTransform(
                reference: baseGray,
                moving: frame.luminance(),
                width: frame.width,
                height: frame.height,
                maxDimension: options.alignmentMaxDimension,
                skyMask: skyMask,
                alignmentModel: options.alignmentModel
            )
        }

        let skyWarp: (FloatRGBImage, [UInt8])
        if transform.isIntegerTranslation {
            let translated = translateWithMask(frame, dy: transform.dy, dx: transform.dx)
            skyWarp = (translated.0, combineMasks(translated.1, warpMask(skySourceMask, width: frame.width, height: frame.height, transform: transform)))
        } else {
            skyWarp = warpImageWithMask(frame, transform: transform, sourceMask: skySourceMask)
        }
        skyFrames.append(skyWarp.0)
        skyMasks.append(skyWarp.1)
        groundFrames.append(frame)
        groundMasks.append(groundSourceMask)
        alignments.append(AlignmentInfo(path: path, dy: transform.dy, dx: transform.dx, peak: transform.peak, transform: transform))
    }

    report(progress, "Stacking sky layer", 0.82)
    let skyStack = try compose(skyFrames, masks: skyMasks, options: options)
    let skyCoverage = coverageMap(skyMasks, totalFrames: skyMasks.count)

    report(progress, "Stacking ground layer", 0.86)
    let groundStack: FloatRGBImage
    switch options.sceneMode {
    case .fullFrame:
        groundStack = base
    case .skyFreezeGround:
        groundStack = base
    case .skyAndGround:
        groundStack = fillMaskedPixels(try compose(groundFrames, masks: groundMasks, options: options), mask: groundSourceMask, fallback: base)
    }

    report(progress, "Compositing sky and ground", 0.90)
    var finalAlpha = Array(repeating: Float(0), count: base.pixelCount)
    for pixel in 0..<base.pixelCount {
        finalAlpha[pixel] = min(baseBlendAlpha[pixel], skyCoverage[pixel])
    }
    var stacked = blend(sky: skyStack, ground: groundStack, alpha: finalAlpha)

    report(progress, "Applying post-processing", 0.94)
    stacked = applyPostProcessing(stacked, options: options)
    report(progress, "Done", 1.0)
    return StackResult(image: stacked.clipped(), basePath: basePath, alignments: alignments, skyMask: skyMask)
}

private func applyPostProcessing(_ image: FloatRGBImage, options: StackOptions) -> FloatRGBImage {
    var out = image
    if options.reduceLightPollution {
        out = reduceLightPollution(out, strength: options.lightPollutionStrength)
    }
    if options.enhanceStars {
        out = enhanceStars(out, strength: options.starEnhancementStrength)
    }
    switch options.outputStretch {
    case .none:
        break
    case .auto:
        out = applyAutoBrightness(out)
    case .hdr:
        out = applyHDRStretch(out)
    }
    return out
}

private func coverageMap(_ masks: [[UInt8]], totalFrames: Int) -> [Float] {
    guard let first = masks.first else { return [] }
    var out = Array(repeating: Float(0), count: first.count)
    let denominator = Float(max(totalFrames, 1))
    for mask in masks {
        for pixel in mask.indices where mask[pixel] != 0 {
            out[pixel] += 1 / denominator
        }
    }
    return out
}

private func blend(sky: FloatRGBImage, ground: FloatRGBImage, alpha: [Float]) -> FloatRGBImage {
    var out = FloatRGBImage(width: sky.width, height: sky.height)
    for pixel in 0..<sky.pixelCount {
        let a = min(max(alpha[pixel], 0), 1)
        let inv = 1 - a
        let base = pixel * 3
        out.data[base + 0] = sky.data[base + 0] * a + ground.data[base + 0] * inv
        out.data[base + 1] = sky.data[base + 1] * a + ground.data[base + 1] * inv
        out.data[base + 2] = sky.data[base + 2] * a + ground.data[base + 2] * inv
    }
    return out
}

private func fillMaskedPixels(_ image: FloatRGBImage, mask: [UInt8], fallback: FloatRGBImage) -> FloatRGBImage {
    var out = image
    for pixel in 0..<out.pixelCount where mask[pixel] == 0 {
        let base = pixel * 3
        out.data[base + 0] = fallback.data[base + 0]
        out.data[base + 1] = fallback.data[base + 1]
        out.data[base + 2] = fallback.data[base + 2]
    }
    return out
}

private func combineMasks(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    var out = Array(repeating: UInt8(0), count: min(a.count, b.count))
    for index in out.indices where a[index] != 0 && b[index] != 0 {
        out[index] = 1
    }
    return out
}

private func warpMask(_ mask: [UInt8], width: Int, height: Int, transform: ImageTransform) -> [UInt8] {
    var out = Array(repeating: UInt8(0), count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            guard let source = transform.sourcePoint(forDestinationX: Float(x), y: Float(y)) else { continue }
            let sx = Int(source.x.rounded())
            let sy = Int(source.y.rounded())
            guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
            out[y * width + x] = mask[sy * width + sx]
        }
    }
    return out
}

private func maskedMean(_ frames: [FloatRGBImage], masks: [[UInt8]]) -> FloatRGBImage {
    var accumulator = Array(repeating: Float(0), count: frames[0].data.count)
    var weights = Array(repeating: Float(0), count: frames[0].pixelCount)
    for (frame, mask) in zip(frames, masks) {
        accumulator.withUnsafeMutableBufferPointer { accumulatorBuffer in
            weights.withUnsafeMutableBufferPointer { weightsBuffer in
                frame.data.withUnsafeBufferPointer { frameBuffer in
                    mask.withUnsafeBufferPointer { maskBuffer in
                        msq_accumulate_masked_rgb(
                            frameBuffer.baseAddress,
                            maskBuffer.baseAddress,
                            Int32(frame.pixelCount),
                            accumulatorBuffer.baseAddress,
                            weightsBuffer.baseAddress
                        )
                    }
                }
            }
        }
    }
    var out = FloatRGBImage(width: frames[0].width, height: frames[0].height)
    out.data.withUnsafeMutableBufferPointer { outBuffer in
        accumulator.withUnsafeBufferPointer { accumulatorBuffer in
            weights.withUnsafeBufferPointer { weightsBuffer in
                msq_finish_masked_mean(
                    Int32(frames[0].pixelCount),
                    accumulatorBuffer.baseAddress,
                    weightsBuffer.baseAddress,
                    outBuffer.baseAddress
                )
            }
        }
    }
    return out
}

private func sigmaClippedMean(_ frames: [FloatRGBImage], masks: [[UInt8]], sigma: Float) -> FloatRGBImage {
    let fallback = maskedMean(frames, masks: masks)
    var out = FloatRGBImage(width: frames[0].width, height: frames[0].height)

    for pixel in 0..<out.pixelCount {
        for channel in 0..<3 {
            var values: [Float] = []
            values.reserveCapacity(frames.count)
            for frameIndex in frames.indices where masks[frameIndex][pixel] != 0 {
                values.append(frames[frameIndex].data[pixel * 3 + channel])
            }
            guard !values.isEmpty else {
                out.data[pixel * 3 + channel] = fallback.data[pixel * 3 + channel]
                continue
            }

            let median = values.median()
            let deviations = values.map { abs($0 - median) }
            let robustSigma = max(1.4826 * deviations.median(), 1e-5)
            let kept = values.filter { abs($0 - median) <= sigma * robustSigma }
            if kept.isEmpty {
                out.data[pixel * 3 + channel] = fallback.data[pixel * 3 + channel]
            } else {
                out.data[pixel * 3 + channel] = kept.reduce(0, +) / Float(kept.count)
            }
        }
    }
    return out
}

public func estimateStackWorkingMemoryBytes(
    width: Int,
    height: Int,
    frameCount: Int,
    mode: CompositionMode,
    sceneMode: SceneCompositionMode
) -> Int64 {
    let safeWidth = max(width, 0)
    let safeHeight = max(height, 0)
    let safeFrameCount = max(frameCount, 0)
    let pixelCount = Int64(safeWidth) * Int64(safeHeight)
    let imageBytes = pixelCount * 3 * Int64(MemoryLayout<Float>.size)
    let maskBytes = pixelCount * Int64(MemoryLayout<UInt8>.size)
    let layerCount: Int64 = sceneMode == .fullFrame ? 1 : 2
    let storedFrameBytes = Int64(safeFrameCount) * layerCount * (imageBytes + maskBytes)
    let accumulatorBytes = layerCount * (imageBytes + pixelCount * Int64(MemoryLayout<Float>.size))
    let sigmaScratchBytes = mode == .sigma ? imageBytes : 0
    return storedFrameBytes + accumulatorBytes + sigmaScratchBytes
}

private func formatByteCount(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(max(bytes, 0))
    var unitIndex = 0
    while value >= 1024, unitIndex + 1 < units.count {
        value /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(Int(value)) \(units[unitIndex])"
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

private func report(_ progress: ProgressCallback?, _ message: String, _ fraction: Double) {
    progress?(message, min(max(fraction, 0), 1))
}
