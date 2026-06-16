import Foundation
import AppKit
import Vision
import Accelerate

// MARK: - SSD 缓存路径

enum SwiftCullPaths {
    /// 固态硬盘上的缓存根目录
    static let ssdRoot: String = {
        let ssd = "/Volumes/固态硬盘/SwiftCull"
        try? FileManager.default.createDirectory(atPath: ssd, withIntermediateDirectories: true)
        return ssd
    }()

    static let thumbnailCache: String = {
        let dir = (ssdRoot as NSString).appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let analysisCache: String = {
        let dir = (ssdRoot as NSString).appendingPathComponent("Analysis")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()
}

// MARK: - 本地分析结果

struct LocalAnalysisResult: Hashable, Sendable {
    let qualityScore: Double       // 0-100 综合分
    let blurScore: Double          // 拉普拉斯方差（越高越清晰）
    let exposureScore: Double      // 0-1（1=完美曝光）
    let faceScore: Double          // 0-1（1=脸清晰+眼睛睁开）
    let compositionScore: Double   // 0-1（构图质量）
    let flags: [String]            // 问题标签
    let isReject: Bool
    let rejectReason: String?

    var toAIResult: AIAnalysisResult {
        AIAnalysisResult(
            verdict: isReject ? .reject : .pass,
            reason: rejectReason ?? "本地分析通过",
            provider: "local",
            model: "Vision",
            analyzedAt: Date()
        )
    }
}

// MARK: - 本地 Vision 分析引擎

actor LocalVisionService {
    static let shared = LocalVisionService()
    private init() {}

    // MARK: - 主入口

    func analyze(_ cgImage: CGImage) -> LocalAnalysisResult {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else {
            return emptyResult("无法读取图片")
        }

        // 并行跑所有检测
        let blur = detectBlur(cgImage)
        let exposure = detectExposure(cgImage)
        let faceResult = detectFaces(cgImage)
        let saliencyResult = detectSaliency(cgImage)
        let composition = scoreComposition(saliency: saliencyResult, width: w, height: h)

        // 综合评分
        let blurNorm = min(1.0, blur.score / 200.0)      // 200+ 算清晰
        let faceNorm = faceResult.score
        let exposureNorm = exposure.score
        let compNorm = composition

        let qualityScore = (blurNorm * 30 + faceNorm * 30 + exposureNorm * 25 + compNorm * 15) * 100

        // 收集问题
        var flags: [String] = []
        var rejectReasons: [String] = []

        if blur.isBlurry {
            flags.append("blur")
            rejectReasons.append("主体模糊")
        }
        if exposure.isOverexposed {
            flags.append("overexposed")
            rejectReasons.append("大面积过曝")
        }
        if exposure.isUnderexposed {
            flags.append("underexposed")
            rejectReasons.append("大面积欠曝")
        }
        if faceResult.hasClosedEyes {
            flags.append("eyes_closed")
            rejectReasons.append("闭眼")
        }
        if faceResult.isFaceBlurry {
            flags.append("face_blurry")
            rejectReasons.append("人脸模糊")
        }

        let isReject = rejectReasons.count >= 1
        let reason = isReject ? rejectReasons.joined(separator: "，") : nil

        return LocalAnalysisResult(
            qualityScore: qualityScore,
            blurScore: blur.score,
            exposureScore: exposureNorm,
            faceScore: faceNorm,
            compositionScore: compNorm,
            flags: flags,
            isReject: isReject,
            rejectReason: reason
        )
    }

    // MARK: - 模糊检测（拉普拉斯方差 + FFT 方向性）

    private func detectBlur(_ cgImage: CGImage) -> (score: Double, isBlurry: Bool) {
        guard let gray = toGrayscale(cgImage, maxSide: 512) else { return (0, true) }
        let lapVar = laplacianVariance(gray)
        // 阈值：30 以下算模糊（与 Pianke 一致）
        return (lapVar, lapVar < 30)
    }

    // MARK: - 曝光分析（直方图）

    private func detectExposure(_ cgImage: CGImage) -> (score: Double, isOverexposed: Bool, isUnderexposed: Bool) {
        guard let gray = toGrayscale(cgImage, maxSide: 512) else { return (0.5, false, false) }
        let pixels = gray.data
        let count = pixels.count
        guard count > 0 else { return (0.5, false, false) }

        var overCount = 0
        var underCount = 0
        var sum: Double = 0

        for p in pixels {
            let v = Int(p)
            sum += Double(v)
            if v >= 247 { overCount += 1 }
            if v <= 8 { underCount += 1 }
        }

        let overRatio = Double(overCount) / Double(count)
        let underRatio = Double(underCount) / Double(count)
        let mean = sum / Double(count)

        // 曝光评分：均值越接近 128 越好，过曝/欠曝比例越低越好
        let brightnessScore = 1.0 - abs(mean - 128) / 128
        let overPenalty = min(1.0, overRatio * 3)
        let underPenalty = min(1.0, underRatio * 3)
        let score = max(0, brightnessScore - overPenalty * 0.5 - underPenalty * 0.5)

        return (score, overRatio > 0.25, underRatio > 0.35)
    }

    // MARK: - 人脸检测（Vision 框架）

    private func detectFaces(_ cgImage: CGImage) -> (score: Double, hasClosedEyes: Bool, isFaceBlurry: Bool, count: Int) {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (0.5, false, false, 0)
        }

        guard let faces = request.results, !faces.isEmpty else {
            return (0.5, false, false, 0)  // 无人脸 → 中性分
        }

        var totalScore: Double = 0
        var hasClosedEyes = false
        var isFaceBlurry = false

        for face in faces {
            var faceScore: Double = 0.5

            // 眼睛状态检测
            if let leftEye = face.landmarks?.leftEye, let rightEye = face.landmarks?.rightEye {
                let leftOpen = eyeOpenScore(leftEye)
                let rightOpen = eyeOpenScore(rightEye)
                let eyeScore = (leftOpen + rightOpen) / 2

                if eyeScore < 0.15 {
                    hasClosedEyes = true
                    faceScore -= 0.3
                } else if eyeScore < 0.3 {
                    faceScore -= 0.1
                }
                faceScore += eyeScore * 0.3
            }

            // 人脸区域模糊检测（用 boundingBox 裁剪后算拉普拉斯）
            let bbox = face.boundingBox
            if let faceCG = cropFace(cgImage, bbox: bbox) {
                if let gray = toGrayscale(faceCG, maxSide: 256) {
                    let faceBlur = laplacianVariance(gray)
                    if faceBlur < 20 {
                        isFaceBlurry = true
                        faceScore -= 0.2
                    }
                    faceScore += min(0.2, faceBlur / 500)
                }
            }

            totalScore += max(0, min(1, faceScore))
        }

        let avgScore = totalScore / Double(faces.count)
        return (avgScore, hasClosedEyes, isFaceBlurry, faces.count)
    }

    /// 眼睛开合评分（EAR - Eye Aspect Ratio）
    private func eyeOpenScore(_ eye: VNFaceLandmarkRegion2D) -> Double {
        let points = eye.normalizedPoints
        guard points.count >= 6 else { return 0.5 }

        // 计算眼睛纵横比
        let p1 = points[1], p5 = points[5]  // 上下
        let p2 = points[2], p4 = points[4]  // 上下
        let p0 = points[0], p3 = points[3]  // 左右

        let vertical1 = hypot(p1.x - p5.x, p1.y - p5.y)
        let vertical2 = hypot(p2.x - p4.x, p2.y - p4.y)
        let horizontal = hypot(p0.x - p3.x, p0.y - p3.y)

        guard horizontal > 0 else { return 0.5 }
        let ear = (vertical1 + vertical2) / (2 * horizontal)

        // EAR 正常范围 0.2-0.3，<0.15 算闭眼
        return min(1.0, ear / 0.3)
    }

    /// 裁剪人脸区域
    private func cropFace(_ cgImage: CGImage, bbox: CGRect) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Vision 的 bbox 是归一化的，左下角为原点
        let x = bbox.origin.x * w
        let y = (1 - bbox.origin.y - bbox.height) * h
        let fw = bbox.width * w
        let fh = bbox.height * h

        let rect = CGRect(x: x, y: y, width: fw, height: fh)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard rect.width > 10, rect.height > 10 else { return nil }
        return cgImage.cropping(to: rect)
    }

    // MARK: - 显著区检测（Vision saliency）

    private func detectSaliency(_ cgImage: CGImage) -> (centerOfInterest: CGPoint?, salientArea: Double) {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (nil, 0.5)
        }

        guard let observation = request.results?.first as? VNSaliencyImageObservation else {
            return (nil, 0.5)
        }

        // 显著区域面积占比
        let salientRect = observation.salientObjects?.first?.boundingBox
        let salientArea = salientRect.map { $0.width * $0.height } ?? 0.5

        // 显著区域中心
        let pixelBuf = observation.pixelBuffer
        let center = estimateSaliencyCenter(pixelBuf)

        return (center, salientArea)
    }

    private func estimateSaliencyCenter(_ pixelBuffer: CVPixelBuffer) -> CGPoint? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard w > 0, h > 0,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var sumX: Double = 0
        var sumY: Double = 0
        var sumWeight: Double = 0

        for y in 0..<h {
            for x in 0..<w {
                let val = Double(ptr[y * bytesPerRow + x])
                if val > 128 {  // 只算显著像素
                    sumX += Double(x) * val
                    sumY += Double(y) * val
                    sumWeight += val
                }
            }
        }

        guard sumWeight > 0 else { return nil }
        return CGPoint(x: sumX / sumWeight / Double(w), y: sumY / sumWeight / Double(h))
    }

    // MARK: - 构图评分（显著区 + 三分法）

    private func scoreComposition(saliency: (centerOfInterest: CGPoint?, salientArea: Double), width: Int, height: Int) -> Double {
        guard let center = saliency.centerOfInterest else { return 0.5 }

        // 三分法交叉点
        let thirds = [
            CGPoint(x: 1.0/3, y: 1.0/3), CGPoint(x: 2.0/3, y: 1.0/3),
            CGPoint(x: 1.0/3, y: 2.0/3), CGPoint(x: 2.0/3, y: 2.0/3),
        ]

        // 显著区中心到最近三分点的距离
        let minDist = thirds.map { hypot($0.x - center.x, $0.y - center.y) }.min() ?? 0.5
        let thirdScore = max(0, 1.0 - minDist * 3)  // 距离越近分越高

        // 显著区大小评分（太大=主体太满，太小=主体太小）
        let areaScore: Double
        if saliency.salientArea > 0.05 && saliency.salientArea < 0.6 {
            areaScore = 0.8
        } else {
            areaScore = 0.4
        }

        return thirdScore * 0.6 + areaScore * 0.4
    }

    // MARK: - FeaturePrint（相似度分组用）

    func generateFeaturePrint(_ cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    func similarity(_ fp1: VNFeaturePrintObservation, _ fp2: VNFeaturePrintObservation) -> Double {
        do {
            var distance: Float = 0
            try fp1.computeDistance(&distance, to: fp2)
            // 距离越小越相似，0=完全相同，转换为 0-1 相似度
            return max(0, 1.0 - Double(distance) / 10.0)
        } catch {
            return 0
        }
    }

    // MARK: - 工具函数

    private func toGrayscale(_ cgImage: CGImage, maxSide: Int) -> (data: [UInt8], width: Int, height: Int)? {
        let w = cgImage.width
        let h = cgImage.height
        let scale = min(1.0, CGFloat(maxSide) / CGFloat(max(w, h)))
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
        return (Array(UnsafeBufferPointer(start: ptr, count: tw * th)), tw, th)
    }

    private func laplacianVariance(_ gray: (data: [UInt8], width: Int, height: Int)) -> Double {
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

    private func emptyResult(_ reason: String) -> LocalAnalysisResult {
        LocalAnalysisResult(
            qualityScore: 0, blurScore: 0, exposureScore: 0,
            faceScore: 0, compositionScore: 0, flags: ["error"],
            isReject: true, rejectReason: reason
        )
    }
}
