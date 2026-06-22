import Foundation

func applyAutoBrightness(_ image: FloatRGBImage, targetPercentile: Float = 99.7, targetValue: Float = 0.92) -> FloatRGBImage {
    let value = image.luminance().percentile(targetPercentile)
    guard value > 1e-6 else { return image }
    let scale = targetValue / value
    var out = image
    for i in out.data.indices {
        out.data[i] = min(max(out.data[i] * scale, 0), 1)
    }
    return out
}

func applyHDRStretch(_ image: FloatRGBImage) -> FloatRGBImage {
    var lows = [Float](repeating: 0, count: 3)
    var highs = [Float](repeating: 1, count: 3)
    for channel in 0..<3 {
        var values = [Float]()
        values.reserveCapacity(image.pixelCount)
        for pixel in 0..<image.pixelCount {
            values.append(image.data[pixel * 3 + channel])
        }
        lows[channel] = values.percentile(0.2)
        highs[channel] = values.percentile(99.9)
    }

    var out = image
    for pixel in 0..<image.pixelCount {
        for channel in 0..<3 {
            let index = pixel * 3 + channel
            let span = max(highs[channel] - lows[channel], 1e-5)
            out.data[index] = min(max((out.data[index] - lows[channel]) / span, 0), 1)
        }
    }
    return out
}

func reduceLightPollution(_ image: FloatRGBImage, strength: Float = 0.45) -> FloatRGBImage {
    let smallWidth = max(16, min(96, image.width / 24))
    let smallHeight = max(16, min(96, image.height / 24))
    var background = FloatRGBImage(width: image.width, height: image.height)

    for channel in 0..<3 {
        var channelData = Array(repeating: Float(0), count: image.pixelCount)
        for pixel in 0..<image.pixelCount {
            channelData[pixel] = image.data[pixel * 3 + channel]
        }
        let low = resizeChannel(channelData, width: image.width, height: image.height, newWidth: smallWidth, newHeight: smallHeight)
        let blurred = blurChannel(low, width: smallWidth, height: smallHeight, radius: 2)
        let high = resizeChannel(blurred, width: smallWidth, height: smallHeight, newWidth: image.width, newHeight: image.height)
        for pixel in 0..<image.pixelCount {
            background.data[pixel * 3 + channel] = high[pixel]
        }
    }

    var neutral = [Float](repeating: 0, count: 3)
    for channel in 0..<3 {
        var values = [Float]()
        values.reserveCapacity(image.pixelCount)
        for pixel in 0..<image.pixelCount {
            values.append(background.data[pixel * 3 + channel])
        }
        neutral[channel] = values.percentile(5)
    }

    var out = image
    for pixel in 0..<image.pixelCount {
        for channel in 0..<3 {
            let index = pixel * 3 + channel
            out.data[index] = min(max(image.data[index] - strength * (background.data[index] - neutral[channel]), 0), 1)
        }
    }
    return out
}

func enhanceStars(_ image: FloatRGBImage, strength: Float = 0.35) -> FloatRGBImage {
    var out = image
    for channel in 0..<3 {
        var channelData = Array(repeating: Float(0), count: image.pixelCount)
        for pixel in 0..<image.pixelCount {
            channelData[pixel] = image.data[pixel * 3 + channel]
        }
        let blurred = blurChannel(channelData, width: image.width, height: image.height, radius: max(1, min(image.width, image.height) / 900))
        for pixel in 0..<image.pixelCount {
            let index = pixel * 3 + channel
            let detail = max(image.data[index] - blurred[pixel], 0)
            out.data[index] = min(max(image.data[index] + strength * detail, 0), 1)
        }
    }
    return out
}

private func resizeChannel(_ image: [Float], width: Int, height: Int, newWidth: Int, newHeight: Int) -> [Float] {
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

private func blurChannel(_ image: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    let r = max(radius, 1)
    var temp = Array(repeating: Float(0), count: image.count)
    var out = Array(repeating: Float(0), count: image.count)

    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            var count: Float = 0
            for xx in max(0, x - r)...min(width - 1, x + r) {
                sum += image[y * width + xx]
                count += 1
            }
            temp[y * width + x] = sum / count
        }
    }

    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            var count: Float = 0
            for yy in max(0, y - r)...min(height - 1, y + r) {
                sum += temp[yy * width + x]
                count += 1
            }
            out[y * width + x] = sum / count
        }
    }
    return out
}
