import Foundation
import AppKit

/// AI 筛选模式
enum AICullMode: String, CaseIterable, Identifiable, Sendable {
    case local      // 本地 Vision：不调 API，速度快
    case llm        // LLM 远程：调 API，精度高

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地分析"
        case .llm: return "AI 筛选"
        }
    }

    var icon: String {
        switch self {
        case .local: return "desktopcomputer"
        case .llm: return "wand.and.stars"
        }
    }

    var description: String {
        switch self {
        case .local: return "离线·快速"
        case .llm: return "云端·精准"
        }
    }

    /// 面板详情描述
    var detailDescription: String {
        switch self {
        case .local:
            return "使用 Apple Vision 框架在本地分析照片，无需联网。"
        case .llm:
            return "调用远程视觉大模型逐张判定，精度最高，返回中文废片理由。"
        }
    }

    /// 本地模式检测项列表
    var localCheckItems: [(String, String, String)] {
        [
            ("eye.trianglebadge.exclamationmark", "模糊检测", "拉普拉斯方差 + FFT"),
            ("sun.max", "曝光分析", "直方图过曝/欠曝检测"),
            ("face.smiling", "人脸质量", "Vision 闭眼/人脸模糊"),
            ("rectangle.center.inset.filled", "构图评分", "显著区 + 三分法"),
            ("photo.stack", "相似分组", "FeaturePrint 视觉距离"),
        ]
    }
}

/// 筛选速度模式（仅 LLM 模式使用）
enum AICullSpeed: String, CaseIterable, Identifiable, Sendable {
    case fast       // 极速：小图 + 精简 prompt + 高并发
    case standard   // 标准：平衡
    case strict     // 严格：大图 + 完整 prompt + 高精度

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "极速"
        case .standard: return "标准"
        case .strict: return "严格"
        }
    }

    var icon: String {
        switch self {
        case .fast: return "bolt.fill"
        case .standard: return "sparkles"
        case .strict: return "magnifyingglass"
        }
    }

    var description: String {
        switch self {
        case .fast: return "快速粗筛"
        case .standard: return "均衡模式"
        case .strict: return "高精度"
        }
    }

    /// 发送给 LLM 的图片长边像素
    var imageMaxSide: Int {
        switch self {
        case .fast: return 384
        case .standard: return 640
        case .strict: return 960
        }
    }

    /// LLM max_tokens
    var maxTokens: Int {
        switch self {
        case .fast: return 96
        case .standard: return 192
        case .strict: return 192
        }
    }

    /// 并发数
    var concurrency: Int {
        switch self {
        case .fast: return 24
        case .standard: return 16
        case .strict: return 12
        }
    }

    /// 预筛阈值（越低越激进）
    var preScreenBlurThreshold: Double {
        switch self {
        case .fast: return 80      // 更激进：模糊判定更宽
        case .standard: return 30
        case .strict: return 20
        }
    }

    var preScreenOverThreshold: Double {
        switch self {
        case .fast: return 0.20
        case .standard: return 0.30
        case .strict: return 0.35
        }
    }

    var preScreenUnderThreshold: Double {
        switch self {
        case .fast: return 0.30
        case .standard: return 0.40
        case .strict: return 0.45
        }
    }

    var strength: String {
        switch self {
        case .fast, .standard: return "standard"
        case .strict: return "advanced"
        }
    }
}

/// 分析中的单条实时事件（用于 UI 流式展示）
struct AICullEvent: Identifiable, Sendable {
    let id = UUID()
    let photoId: String
    let photoName: String
    let verdict: AIAnalysisResult.Verdict
    let reason: String
    let isPreScreen: Bool
    let timestamp: Date
}

/// AI 快筛进度状态
enum AICullPhase: Sendable {
    case idle
    case preScreening
    case analyzing
    case done
}

/// AI 快筛编排服务
@MainActor
class AICullService: ObservableObject {
    @Published var phase: AICullPhase = .idle
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var currentPhotoName: String = ""
    @Published var currentPhotoPath: String = ""      // 当前分析照片路径（用于缩略图）
    @Published var results: [String: AIAnalysisResult] = [:]
    @Published var preRejects: [String: String] = [:]
    @Published var errorMessage: String?
    @Published var recentEvents: [AICullEvent] = []    // 最近 N 条事件（流式滚动）
    @Published var analyzedPhotos: Set<String> = []    // 已分析的 photoId 集合（用于网格实时标记）
    @Published var speed: AICullSpeed = .standard
    @Published var mode: AICullMode = .local

    // 统计
    @Published var totalCount = 0
    @Published var passCount = 0
    @Published var rejectCount = 0
    @Published var preRejectCount = 0
    @Published var skipCount = 0

    private var analysisTask: Task<Void, Never>?
    private let maxRecentEvents = 30

    // MARK: - 批量缓冲（避免高并发下 UI 卡顿）

    /// 不触发 objectWillChange 的临时缓冲区
    private var pendingResults: [String: AIAnalysisResult] = [:]
    private var pendingPreRejects: [String: String] = [:]
    private var pendingAnalyzedIds: Set<String> = []
    private var pendingEvents: [AICullEvent] = []
    private var pendingPassCount = 0
    private var pendingRejectCount = 0
    private var pendingPreRejectCount = 0
    private var pendingSkipCount = 0
    private var pendingProgress: Double = 0
    private var pendingStatusText = ""
    private var pendingPhotoName = ""
    private var pendingPhotoPath = ""
    private var flushTimer: Timer?
    private var decodedImageCache: [String: CGImage] = [:]
    private var decodedCacheOrder: [String] = []
    private let decodedCacheLimit = 256
    private let flushInterval: TimeInterval = 1.0 / 6.0  // 6 FPS，降低 UI 刷新频率以缓解卡顿

    var isAnalyzing: Bool {
        phase == .preScreening || phase == .analyzing
    }

    var allRejectCount: Int { rejectCount + preRejectCount }

    // MARK: - 启动分析

    func analyze(photos: [PhotoEntry], mode: AICullMode = .local,
                 provider: LLMProvider = .mimo, model: String = "",
                 speed: AICullSpeed = .standard) {
        cancel()
        reset()
        self.mode = mode
        self.speed = speed

        totalCount = photos.count
        phase = .analyzing
        statusText = mode == .local ? "本地分析中..." : "AI 分析中..."
        errorMessage = nil

        startFlushTimer()

        let capturedPhotos = photos
        let capturedProvider = provider
        let capturedModel = model
        let capturedSpeed = speed
        let capturedMode = mode

        analysisTask = Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                guard let self else { return }
                if capturedMode == .local {
                    await self.runLocalAnalysis(photos: capturedPhotos)
                } else {
                    await self.runLLMAnalysis(photos: capturedPhotos, provider: capturedProvider,
                                              model: capturedModel, speed: capturedSpeed)
                }
            }.value

            guard let self else { return }
            await MainActor.run {
                self.stopFlushTimer()
                self.flushPendingBatch()
            }
        }
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        stopFlushTimer()
        flushPendingBatch()  // 取消前 flush 一次
        if phase != .done {
            phase = .idle
            statusText = ""
            currentPhotoPath = ""
        }
    }

    private func reset() {
        progress = 0
        results = [:]
        preRejects = [:]
        recentEvents = []
        analyzedPhotos = []
        passCount = 0
        rejectCount = 0
        preRejectCount = 0
        skipCount = 0
        errorMessage = nil
        clearPendingBuffer()
        decodedImageCache.removeAll()
        decodedCacheOrder.removeAll()
    }

    // MARK: - 批量缓冲 & 定时 Flush

    private func clearPendingBuffer() {
        pendingResults = [:]
        pendingPreRejects = [:]
        pendingAnalyzedIds = []
        pendingEvents = []
        pendingPassCount = 0
        pendingRejectCount = 0
        pendingPreRejectCount = 0
        pendingSkipCount = 0
        pendingProgress = 0
        pendingStatusText = ""
        pendingPhotoName = ""
        pendingPhotoPath = ""
    }

    private func startFlushTimer() {
        stopFlushTimer()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingBatch()
            }
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    /// 将缓冲区累积的更新一次性写入 @Published 属性，只触发一次 objectWillChange
    private func flushPendingBatch() {
        let hasResults = !pendingResults.isEmpty
        let hasPreRejects = !pendingPreRejects.isEmpty
        let hasEvents = !pendingEvents.isEmpty
        let hasAnalyzed = !pendingAnalyzedIds.isEmpty
        let hasStats = pendingPassCount != 0 || pendingRejectCount != 0
                      || pendingPreRejectCount != 0 || pendingSkipCount != 0

        guard hasResults || hasPreRejects || hasEvents || hasAnalyzed || hasStats else { return }

        // 手动抑制 objectWillChange，批量更新完再触发一次
        objectWillChange.send()

        if hasResults {
            for (id, result) in pendingResults { results[id] = result }
        }
        if hasPreRejects {
            for (id, reason) in pendingPreRejects { preRejects[id] = reason }
        }
        if hasAnalyzed {
            analyzedPhotos.formUnion(pendingAnalyzedIds)
        }
        if hasEvents {
            let combined = pendingEvents + recentEvents
            let limit = min(combined.count, maxRecentEvents)
            recentEvents = Array(combined.prefix(limit))
        }

        passCount += pendingPassCount
        rejectCount += pendingRejectCount
        preRejectCount += pendingPreRejectCount
        skipCount += pendingSkipCount

        if pendingProgress > 0 { progress = pendingProgress }
        if !pendingStatusText.isEmpty { statusText = pendingStatusText }
        if !pendingPhotoName.isEmpty { currentPhotoName = pendingPhotoName }
        if !pendingPhotoPath.isEmpty { currentPhotoPath = pendingPhotoPath }

        clearPendingBuffer()
    }

    /// 写入缓冲区，不触发任何 @Published 通知
    private func bufferResult(id: String, result: AIAnalysisResult) {
        pendingResults[id] = result
        pendingAnalyzedIds.insert(id)
    }

    private func bufferPreReject(id: String, reason: String) {
        pendingPreRejects[id] = reason
        pendingAnalyzedIds.insert(id)
    }

    private func bufferEvent(_ event: AICullEvent) {
        if pendingEvents.count >= maxRecentEvents {
            pendingEvents.removeLast()
        }
        pendingEvents.insert(event, at: 0)
    }

    // MARK: - 本地 Vision 分析（纯本地，不调 API）

    private func runLocalAnalysis(photos: [PhotoEntry]) async {
        let vision = LocalVisionService.shared
        let total = photos.count
        var localLookup: [String: PhotoEntry] = [:]
        localLookup.reserveCapacity(photos.count)
        for photo in photos {
            localLookup[photo.id] = photo
        }

        await withTaskGroup(of: (String, LocalAnalysisResult).self) { group in
            var index = 0
            let concurrency = min(6, ProcessInfo.processInfo.activeProcessorCount)

            while index < photos.count && index < concurrency {
                let photo = photos[index]
                group.addTask {
                    guard let cgImage = Self.loadCGImageStatic(from: photo, maxSide: 768) else {
                        return (photo.id, LocalAnalysisResult(
                            qualityScore: 0, blurScore: 0, exposureScore: 0,
                            faceScore: 0, compositionScore: 0, flags: ["error"],
                            isReject: false, rejectReason: nil))
                    }
                    let result = await vision.analyze(cgImage)
                    return (photo.id, result)
                }
                index += 1
            }

            var done = 0
            for await (photoId, localResult) in group {
                if Task.isCancelled { return }

                let matchedPhoto = localLookup[photoId]
                let photoName = matchedPhoto?.baseName ?? ""
                let aiResult = localResult.toAIResult

                // 写入缓冲区，不触发 @Published
                bufferResult(id: photoId, result: aiResult)
                if localResult.isReject { pendingRejectCount += 1 }
                else { pendingPassCount += 1 }
                bufferEvent(AICullEvent(
                    photoId: photoId, photoName: photoName,
                    verdict: aiResult.verdict, reason: aiResult.reason,
                    isPreScreen: false, timestamp: Date()
                ))

                done += 1
                if done % 8 == 0 || done == total {
                    pendingProgress = Double(done) / Double(total)
                    pendingStatusText = "本地分析 \(done)/\(total)"
                    pendingPhotoName = photoName
                    pendingPhotoPath = matchedPhoto?.primaryImagePath ?? ""
                }

                if index < photos.count {
                    let photo = photos[index]
                    group.addTask {
                        guard let cgImage = Self.loadCGImageStatic(from: photo, maxSide: 768) else {
                            return (photo.id, LocalAnalysisResult(
                                qualityScore: 0, blurScore: 0, exposureScore: 0,
                                faceScore: 0, compositionScore: 0, flags: ["error"],
                                isReject: false, rejectReason: nil))
                        }
                        let result = await vision.analyze(cgImage)
                        return (photo.id, result)
                    }
                    index += 1
                }
            }
        }

        if !Task.isCancelled {
            stopFlushTimer()
            flushPendingBatch()  // 最终 flush
            phase = .done
            progress = 1.0
            statusText = "AI 分析完成"
            currentPhotoName = ""
            currentPhotoPath = ""
        }
    }

    // MARK: - LLM 分析（调远程 API）

    private func runLLMAnalysis(photos: [PhotoEntry], provider: LLMProvider,
                             model: String, speed: AICullSpeed) async {
        let llm = LLMService.shared
        await llm.setProvider(provider)

        var toAnalyze: [PhotoEntry] = []
        var photoLookup: [String: PhotoEntry] = [:]
        photoLookup.reserveCapacity(photos.count)
        var preScreened = 0

        for photo in photos {
            photoLookup[photo.id] = photo
        }

        // 阶段 1：本地预筛
        let batchSize = 16
        var nextIndex = 0
        while nextIndex < photos.count {
            if Task.isCancelled { return }
            let end = min(nextIndex + batchSize, photos.count)
            let batch = Array(photos[nextIndex..<end])

            let analyzedBatch = await withTaskGroup(of: (PhotoEntry, FastPreScreenResult?).self) { group in
                for photo in batch {
                    group.addTask {
                        if let cgImage = Self.loadCGImageStatic(from: photo, maxSide: 512) {
                            let result = FastPreScreen.analyze(cgImage,
                                                               blurThreshold: speed.preScreenBlurThreshold,
                                                               overThreshold: speed.preScreenOverThreshold,
                                                               underThreshold: speed.preScreenUnderThreshold)
                            return (photo, result)
                        }
                        return (photo, nil)
                    }
                }

                var outputs: [(PhotoEntry, FastPreScreenResult?)] = []
                outputs.reserveCapacity(batch.count)
                for await item in group {
                    outputs.append(item)
                }
                return outputs
            }

            for (photo, result) in analyzedBatch {
                if Task.isCancelled { return }
                pendingPhotoName = photo.baseName
                pendingPhotoPath = photo.primaryImagePath

                if let result, result.isRejected {
                    bufferPreReject(id: photo.id, reason: result.reason ?? "预筛废片")
                    pendingPreRejectCount += 1
                    bufferEvent(AICullEvent(
                        photoId: photo.id, photoName: photo.baseName,
                        verdict: .reject, reason: result.reason ?? "预筛废片",
                        isPreScreen: true, timestamp: Date()
                    ))
                } else {
                    toAnalyze.append(photo)
                }
            }

            nextIndex = end
            preScreened = nextIndex
            let progress = Double(preScreened) / Double(max(1, photos.count)) * 0.3
            if progress > pendingProgress { pendingProgress = progress }
            pendingStatusText = "预筛 \(preScreened)/\(photos.count)"
        }

        // 阶段 2：LLM 分析
        phase = .analyzing
        let llmTotal = toAnalyze.count
        var llmDone = 0

        await withTaskGroup(of: (String, AIAnalysisResult?).self) { group in
            var index = 0
            var running = 0

            while index < toAnalyze.count && running < speed.concurrency {
                let photo = toAnalyze[index]
                group.addTask { [weak self] in
                    await self?.analyzeOne(photo: photo, llm: llm, model: model,
                                           speed: speed) ?? (photo.id, nil)
                }
                index += 1
                running += 1
            }

            for await (photoId, result) in group {
                if Task.isCancelled { return }

                let matchedPhoto = photoLookup[photoId]
                let photoName = matchedPhoto?.baseName ?? ""

                if let result = result {
                    bufferResult(id: photoId, result: result)
                    if result.verdict == .pass { pendingPassCount += 1 }
                    else { pendingRejectCount += 1 }
                    bufferEvent(AICullEvent(
                        photoId: photoId, photoName: photoName,
                        verdict: result.verdict, reason: result.reason,
                        isPreScreen: false, timestamp: Date()
                    ))
                } else {
                    pendingSkipCount += 1
                }

                llmDone += 1
                if llmDone % 8 == 0 || llmDone == llmTotal {
                    pendingProgress = 0.3 + Double(llmDone) / Double(max(1, llmTotal)) * 0.7
                    pendingStatusText = "AI 分析 \(llmDone)/\(llmTotal)"
                    pendingPhotoName = photoName
                    pendingPhotoPath = matchedPhoto?.primaryImagePath ?? ""
                }

                if index < toAnalyze.count {
                    let photo = toAnalyze[index]
                    group.addTask { [weak self] in
                        await self?.analyzeOne(photo: photo, llm: llm, model: model,
                                               speed: speed) ?? (photo.id, nil)
                    }
                    index += 1
                }
            }
        }

        if !Task.isCancelled {
            stopFlushTimer()
            flushPendingBatch()  // 最终 flush
            phase = .done
            progress = 1.0
            statusText = "AI 分析完成"
            currentPhotoName = ""
            currentPhotoPath = ""
        }
    }

    private func analyzeOne(photo: PhotoEntry, llm: LLMService,
                            model: String, speed: AICullSpeed) async -> (String, AIAnalysisResult?) {
        guard let cgImage = loadCGImage(from: photo, maxSide: speed.imageMaxSide) else {
            return (photo.id, nil)
        }
        do {
            let sourcePath = photo.jpgPath ?? photo.nefPath ?? photo.primaryImagePath
            let result = try await llm.judgeImage(cgImage, model: model,
                                                   strength: speed.strength,
                                                   maxTokens: speed.maxTokens,
                                                   imageMaxSide: speed.imageMaxSide,
                                                   sourcePath: sourcePath.isEmpty ? nil : sourcePath)
            return (photo.id, result)
        } catch {
            if error is CancellationError { return (photo.id, nil) }
            return (photo.id, nil)
        }
    }

    // MARK: - 图片加载

    private func loadCGImage(from photo: PhotoEntry, maxSide: Int = 1200) -> CGImage? {
        let path = photo.jpgPath ?? photo.nefPath ?? photo.primaryImagePath
        guard !path.isEmpty else { return nil }
        let cacheKey = "\(path)|\(maxSide)"
        if let cached = decodedImageCache[cacheKey] {
            return cached
        }
        guard let image = Self.loadCGImageStatic(from: photo, maxSide: maxSide) else { return nil }
        decodedImageCache[cacheKey] = image
        decodedCacheOrder.append(cacheKey)
        if decodedCacheOrder.count > decodedCacheLimit {
            let removeCount = min(decodedCacheOrder.count - decodedCacheLimit, decodedCacheOrder.count)
            let removedKeys = decodedCacheOrder.prefix(removeCount)
            for key in removedKeys { decodedImageCache.removeValue(forKey: key) }
            decodedCacheOrder.removeFirst(removeCount)
        }
        return image
    }

    nonisolated private static func loadCGImageStatic(from photo: PhotoEntry, maxSide: Int = 1200) -> CGImage? {
        let path = photo.jpgPath ?? photo.nefPath ?? photo.primaryImagePath
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - 应用结果

    func applyResults(to photos: inout [PhotoEntry]) {
        for i in photos.indices {
            let id = photos[i].id
            if let result = results[id] {
                photos[i].aiResult = result
            } else if preRejects[id] != nil {
                photos[i].aiResult = AIAnalysisResult(
                    verdict: .reject, reason: preRejects[id] ?? "预筛废片",
                    provider: "local", model: "preScreen", analyzedAt: Date()
                )
            }
        }
    }

    struct Summary {
        let total: Int
        let pass: Int
        let reject: Int
        let preReject: Int
        let skip: Int
        let rejectRate: Double
        let savedSpace: String
    }

    func summary(photos: [PhotoEntry]) -> Summary {
        let rejectPhotos = photos.filter { photo in
            if let r = results[photo.id] { return r.verdict == .reject }
            return preRejects[photo.id] != nil
        }
        let savedBytes = rejectPhotos.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let rate = totalCount > 0 ? Double(allRejectCount) / Double(totalCount) : 0
        return Summary(
            total: totalCount, pass: passCount, reject: rejectCount,
            preReject: preRejectCount, skip: skipCount,
            rejectRate: rate,
            savedSpace: ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
        )
    }
}
