import Foundation

func medianFrame(_ paths: [URL]) throws -> FloatRGBImage? {
    guard !paths.isEmpty else { return nil }
    let frames = try paths.map(loadImage)
    try assertSameShape(frames)

    var output = FloatRGBImage(width: frames[0].width, height: frames[0].height)
    var values = Array(repeating: Float(0), count: frames.count)
    for index in output.data.indices {
        for frameIndex in frames.indices {
            values[frameIndex] = frames[frameIndex].data[index]
        }
        output.data[index] = values.median()
    }
    return output
}

func calibrate(_ image: FloatRGBImage, dark: FloatRGBImage?, flat: FloatRGBImage?) throws -> FloatRGBImage {
    var out = image
    if let dark {
        guard image.hasSameShape(as: dark) else {
            throw MySequatorError.shapeMismatch("Dark frame shape does not match image.")
        }
        for i in out.data.indices {
            out.data[i] = max(out.data[i] - dark.data[i], 0)
        }
    }

    if let flat {
        guard image.hasSameShape(as: flat) else {
            throw MySequatorError.shapeMismatch("Flat frame shape does not match image.")
        }
        var medians = [Float](repeating: 0, count: 3)
        for channel in 0..<3 {
            var values = [Float]()
            values.reserveCapacity(flat.pixelCount)
            for pixel in 0..<flat.pixelCount {
                values.append(max(flat.data[pixel * 3 + channel], 0.0001))
            }
            medians[channel] = values.median()
        }
        for pixel in 0..<out.pixelCount {
            for channel in 0..<3 {
                let idx = pixel * 3 + channel
                let safeFlat = max(flat.data[idx], 0.0001)
                out.data[idx] = out.data[idx] * medians[channel] / safeFlat
            }
        }
    }

    return out.clipped()
}

func assertSameShape(_ frames: [FloatRGBImage]) throws {
    guard let first = frames.first else { return }
    for frame in frames.dropFirst() where !frame.hasSameShape(as: first) {
        throw MySequatorError.shapeMismatch("Images must have the same dimensions.")
    }
}
