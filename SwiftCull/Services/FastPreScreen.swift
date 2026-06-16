import Foundation
import AppKit

/// 本地快速预筛：模糊 + 曝光检测，跳过明显废片省 LLM 费用
struct FastPreScreenResult {
    let isRejected: Bool
    let reason: String?
    let blurScore: Double
    let overexposedRatio: Double
    let underexposedRatio: Double
}

enum FastPreScreen {

    static func analyze(_ cgImage: CGImage,
                        blurThreshold: Double = 30,
                        overThreshold: Double = 0.30,
                        underThreshold: Double = 0.40) -> FastPreScreenResult {
        guard let gray = toGrayscale(cgImage) else {
            return FastPreScreenResult(isRejected: false, reason: nil,
                                       blurScore: 0, overexposedRatio: 0, underexposedRatio: 0)
        }

        let blur = laplacianVariance(gray)
        let (over, under) = exposureRatios(gray)

        var reasons: [String] = []
        if blur < blurThreshold { reasons.append("严重模糊") }
        if over > overThreshold { reasons.append("大面积过曝") }
        if under > underThreshold { reasons.append("大面积欠曝") }

        return FastPreScreenResult(
            isRejected: !reasons.isEmpty,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: "，"),
            blurScore: blur,
            overexposedRatio: over,
            underexposedRatio: under
        )
    }

    // MARK: - 灰度转换

    private static func toGrayscale(_ cgImage: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let maxDim = 512
        let w = cgImage.width
        let h = cgImage.height
        let scale = min(1.0, CGFloat(maxDim) / CGFloat(max(w, h)))
        let tw = max(1, Int(CGFloat(w) * scale))
        let th = max(1, Int(CGFloat(h) * scale))

        guard let ctx = CGContext(data: nil, width: tw, height: th,
                                  bitsPerComponent: 8, bytesPerRow: tw,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let data = ctx.data else { return nil }

        let ptr = data.bindMemory(to: UInt8.self, capacity: tw * th)
        let pixels = Array(UnsafeBufferPointer(start: ptr, count: tw * th))
        return (pixels, tw, th)
    }

    // MARK: - 拉普拉斯方差

    private static func laplacianVariance(_ gray: (data: [UInt8], width: Int, height: Int)) -> Double {
        let w = gray.width
        let h = gray.height
        guard w >= 3, h >= 3 else { return 0 }
        let src = gray.data

        var sum: Double = 0
        var sumSq: Double = 0
        let count = (w - 2) * (h - 2)

        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let idx = y * w + x
                let val = Double(-Int(src[idx - w]) - Int(src[idx - 1])
                               + 4 * Int(src[idx]) - Int(src[idx + 1]) - Int(src[idx + w]))
                sum += val
                sumSq += val * val
            }
        }

        let mean = sum / Double(count)
        return sumSq / Double(count) - mean * mean
    }

    // MARK: - 曝光比率

    private static func exposureRatios(_ gray: (data: [UInt8], width: Int, height: Int)) -> (over: Double, under: Double) {
        let pixels = gray.data
        let count = pixels.count
        guard count > 0 else { return (0, 0) }

        var overCount = 0
        var underCount = 0

        for p in pixels {
            if p >= 247 { overCount += 1 }
            if p <= 8 { underCount += 1 }
        }

        let total = Double(count)
        return (Double(overCount) / total, Double(underCount) / total)
    }
}
