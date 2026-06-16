import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - 配置

private let kConfigDir: String = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/swiftcull").path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}()

private let kConfigFile = (kConfigDir as NSString).appendingPathComponent("llm_config.json")

// MARK: - 自适应限流器（Actor）

actor AdaptiveLimiter {
    private var limit: Int
    private let minLimit = 1
    private let maxLimit: Int
    private var inFlight = 0
    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date?
    private let circuitThreshold = 8           // 连续失败过多时更快进入冷却，避免长时间卡住批量任务
    private let circuitCooldown: TimeInterval = 12
    private var successSinceRateLimit = 0
    private let scaleUpEvery = 8               // 成功恢复更积极，但不会瞬间冲回高并发
    private var lastRateLimit: Date?

    init(initial: Int, max: Int) {
        self.maxLimit = max
        self.limit = Swift.max(1, Swift.min(initial, max))
    }

    func acquire() async {
        while true {
            // 熔断检查
            if let openUntil = circuitOpenUntil, Date() < openUntil {
                let wait = openUntil.timeIntervalSinceNow
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            if circuitOpenUntil != nil {
                circuitOpenUntil = nil
                consecutiveFailures = 0
            }
            if inFlight < limit { break }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
        }
        inFlight += 1
    }

    func release() {
        inFlight = Swift.max(0, inFlight - 1)
    }

    func onSuccess() {
        consecutiveFailures = 0
        circuitOpenUntil = nil
        successSinceRateLimit += 1
        if successSinceRateLimit >= scaleUpEvery, limit < maxLimit,
           (lastRateLimit?.timeIntervalSinceNow ?? -999) < -10 {
            limit = Swift.min(maxLimit, limit + 1)
            successSinceRateLimit = 0
        }
    }

    func onRateLimit() {
        lastRateLimit = Date()
        successSinceRateLimit = 0
        limit = Swift.max(minLimit, limit / 2)
    }

    func onFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= circuitThreshold, circuitOpenUntil == nil {
            circuitOpenUntil = Date().addingTimeInterval(circuitCooldown)
        }
    }

    var currentLimit: Int { limit }
}

// MARK: - LLM 客户端

actor LLMService {
    static let shared = LLMService()

    private var provider: LLMProvider = .mimo
    private var apiKey: String = ""
    private var baseURL: String = ""
    private var customBaseURL: String = ""
    private let limiter = AdaptiveLimiter(initial: 40, max: 120)
    private let session = URLSession.shared
    private var encodeCache: [String: (dataURL: String, bytes: Int, size: CGSize)] = [:]
    private var encodeCacheOrder: [String] = []
    private let encodeCacheLimit = 256

    private init() {
        // 同步加载配置（不涉及 actor 隔离状态的复杂操作）
        if let data = try? Data(contentsOf: URL(fileURLWithPath: kConfigFile)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let p = json["provider"] as? String, let prov = LLMProvider(rawValue: p) {
                self.provider = prov
            }
            let provKey = self.provider.rawValue
            if let providers = json["providers"] as? [String: [String: String]],
               let key = providers[provKey]?["api_key"], !key.isEmpty {
                self.apiKey = key
            }
            if let url = json["custom_base_url"] as? String {
                self.customBaseURL = url
            }
        }
    }

    // MARK: - 配置

    func setProvider(_ provider: LLMProvider) {
        self.provider = provider
    }

    func setAPIKey(_ key: String) {
        self.apiKey = key
        saveConfig()
    }

    func setCustomBaseURL(_ url: String) {
        self.customBaseURL = url
    }

    var currentProvider: LLMProvider { provider }
    var hasAPIKey: Bool { !apiKey.isEmpty }

    func resolveBaseURL() -> String {
        if provider == .custom { return customBaseURL }
        return provider.defaultBaseURL
    }

    // MARK: - 持久化

    private func saveConfig() {
        var providers: [String: [String: String]] = [:]
        providers[provider.rawValue] = ["api_key": apiKey]
        let json: [String: Any] = [
            "provider": provider.rawValue,
            "providers": providers,
            "custom_base_url": customBaseURL,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: kConfigFile))
        }
    }

    // MARK: - 图片编码

    func encodeImage(_ cgImage: CGImage, maxSide: Int = 640, maxBytes: Int = 384 * 1024, cacheKey: String? = nil) -> (dataURL: String, bytes: Int, size: CGSize)? {
        if let key = cacheKey, let cached = encodeCache[key] {
            return cached
        }
        let w = cgImage.width
        let h = cgImage.height
        let scale: CGFloat = CGFloat(maxSide) / CGFloat(max(w, h))
        let targetW = max(1, Int(CGFloat(w) * min(1.0, scale)))
        let targetH = max(1, Int(CGFloat(h) * min(1.0, scale)))

        guard let ctx = CGContext(data: nil, width: targetW, height: targetH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let resized = ctx.makeImage() else { return nil }

        // 尝试不同质量
        let qualities: [CGFloat] = [0.78, 0.68, 0.58, 0.48]
        var jpegData: Data?
        for q in qualities {
            let rep = NSBitmapImageRep(cgImage: resized)
            rep.size = NSSize(width: targetW, height: targetH)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: q]) else { continue }
            if data.count <= maxBytes || q == qualities.last {
                jpegData = data
                break
            }
        }

        guard let data = jpegData else { return nil }
        let b64 = data.base64EncodedString()
        let encoded = (
            "data:image/jpeg;base64,\(b64)",
            data.count,
            CGSize(width: targetW, height: targetH)
        )
        if let key = cacheKey {
            encodeCache[key] = encoded
            encodeCacheOrder.append(key)
            if encodeCacheOrder.count > encodeCacheLimit {
                let removeCount = min(encodeCacheOrder.count - encodeCacheLimit, encodeCacheOrder.count)
                for oldKey in encodeCacheOrder.prefix(removeCount) {
                    encodeCache.removeValue(forKey: oldKey)
                }
                encodeCacheOrder.removeFirst(removeCount)
            }
        }
        return encoded
    }

    // MARK: - Prompt

    /// 极速模式：精简 prompt，只关注最明显的废片特征
    private let promptFast = """
    快速判断这张照片是否是废片。
    废片特征：主体模糊/失焦、大面积过曝或欠曝、闭眼、严重构图问题（断头断手）、表情极度不自然。
    大光圈浅景深不算模糊。高ISO噪点不算模糊。
    只输出一行JSON：{"verdict":"pass"或"reject","reason":"≤10字"}
    """

    /// 标准/严格模式 prompt
    private let promptStandard = """
    ## 你是谁
    你是一位照片质检员。用户让你筛照片，把废片剔掉。
    **正确的做法是：先找问题，找完了再决定这张图值不值得留。**
    但你也不是来找茬的。一张骨架没毛病的照片，不要因为一根碎发就杀掉。

    ## 判断流程

    ### 第一步：检查骨架（任何一条命中 → reject）
    **焦点 / 清晰度**
      - 主体跑焦（对焦点明显不在主体上）
      - 抖动、运动拖影导致主体不清晰
      - **注意区分"失焦"和"浅景深"**：
        - 大光圈（f/1.4–f/2.8）拍人，五官清晰但耳朵/头发略柔 → 正常浅景深，不算失焦
        - 高 ISO 噪点 → 不是模糊
        - 只有主体关键部位（眼睛、面部）明显发糊时才算失焦
      - **不要用 100% 放大判断**：按正常观看距离看，主体清晰即可

    **曝光（大面积的）**
      - 主体大面积过曝纯白，五官或关键细节丢失
      - 主体大面积欠曝死黑

    **构图硬伤**
      - 主体被严重裁切：断头、断手、半张脸出画
      - 头顶紧贴画框上沿

    **表情**
      - 任何主要人物闭眼、半闭眼
      - 翻白眼、斗鸡眼
      - 嘴张到一半（说话中间嘴型）
      - 假笑：嘴在笑但眼睛没笑

    **姿态 / 时机**
      - 动作的中间帧：手抬到一半、转身转到一半
      - 严重驼背缩肩

    ### 第二步：骨架没问题 → 检查皮肤（可修复 → pass）
    碎发、痘、背景路人、衣服褶皱 → pass，写进 reason 说明哪里好

    ### 第三步：骨架好 + 皮肤干净 → pass

    ## 设计感豁免
    故意的背景虚化、黑白/暗调风格、纪实抓拍 → 不算缺陷

    ## 风光 / 小景
    没有"人物状态"维度，只看清晰度 + 曝光 + 基本构图。找不到具体技术缺陷 → pass。

    【输出格式】
    只输出一行 JSON，不要 markdown 代码块：
    {"verdict":"pass" 或 "reject", "reason":"≤15 字具体观察"}
    """

    private func buildJudgeRequest(encodedData: String, model: String, promptText: String, maxTokens: Int) throws -> URLRequest {
        let baseURL = resolveBaseURL()
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw LLMError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let contentItems: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": encodedData]],
            ["type": "text", "text": promptText],
        ]
        let message: [String: Any] = ["role": "user", "content": contentItems]
        let body: [String: Any] = [
            "model": model,
            "messages": [message],
            "temperature": 0.0,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - 核心判定

    func judgeImage(_ cgImage: CGImage, model: String,
                    strength: String = "standard",
                    maxTokens: Int = 192,
                    imageMaxSide: Int = 896,
                    sourcePath: String? = nil) async throws -> AIAnalysisResult {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        guard !model.isEmpty else {
            throw LLMError.noModel
        }

        let encodeCacheKey: String? = {
            guard let sourcePath, !sourcePath.isEmpty else { return nil }
            return sourcePath + "|" + String(imageMaxSide)
        }()
        guard let encoded = encodeImage(cgImage, maxSide: imageMaxSide, cacheKey: encodeCacheKey) else {
            throw LLMError.imageEncodingFailed
        }

        let promptText = strength == "fast" ? promptFast : promptStandard
        let request = try buildJudgeRequest(encodedData: encoded.dataURL,
                                            model: model,
                                            promptText: promptText,
                                            maxTokens: maxTokens)

        let backoffs: [TimeInterval] = [0.6, 1.5, 4, 10]
        var lastError: Error?

        await limiter.acquire()
        defer { Task { await limiter.release() } }

        var retryRequest = request
        for (attempt, backoff) in backoffs.enumerated() {
            do {
                let (data, response) = try await session.data(for: retryRequest)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 429 {
                    await limiter.onRateLimit()
                    let wait = backoff * 2
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    continue
                }

                guard statusCode == 200 else {
                    throw LLMError.httpError(statusCode, String(data: data, encoding: .utf8) ?? "")
                }

                let result = try parseResponse(data)
                await limiter.onSuccess()
                return AIAnalysisResult(
                    verdict: result.verdict,
                    reason: result.reason,
                    provider: provider.rawValue,
                    model: model,
                    analyzedAt: Date()
                )
            } catch {
                lastError = error
                if error is CancellationError { throw error }
                if attempt < backoffs.count - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }

        await limiter.onFailure()
        throw lastError ?? LLMError.allRetriesFailed
    }

    // MARK: - 响应解析（三级容错）

    private func parseResponse(_ data: Data) throws -> (verdict: AIAnalysisResult.Verdict, reason: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              var content = message["content"] as? String else {
            throw LLMError.invalidResponse("无法解析 API 响应")
        }

        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去除 markdown 代码块
        if content.hasPrefix("```") {
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("```") }
            content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 第一级：精确 JSON 解析
        if let data = content.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = obj["verdict"] as? String {
            let verdict = v.lowercased().trimmingCharacters(in: .whitespaces)
            let reason = (obj["reason"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if let ver = AIAnalysisResult.Verdict(rawValue: verdict) {
                return (ver, reason.isEmpty ? defaultReason(ver) : truncate(reason))
            }
        }

        // 第二级：正则提取
        if let vMatch = content.range(of: #""verdict"\s*:\s*"(pass|reject)""#, options: .regularExpression),
           let rMatch = content.range(of: #""reason"\s*:\s*"([^"]{1,60})""#, options: .regularExpression) {
            let vStr = String(content[vMatch]).components(separatedBy: "\"").last(where: { $0 == "pass" || $0 == "reject" }) ?? ""
            let rStr = String(content[rMatch]).components(separatedBy: "\"").dropLast().last ?? ""
            if let ver = AIAnalysisResult.Verdict(rawValue: vStr) {
                return (ver, rStr.isEmpty ? defaultReason(ver) : truncate(rStr))
            }
        }

        // 第三级：关键字兜底
        let lower = content.lowercased()
        if lower.contains("\"reject\"") || lower.contains("reject") {
            let reason = extractReason(from: content) ?? defaultReason(.reject)
            return (.reject, truncate(reason))
        }
        if lower.contains("\"pass\"") || lower.contains("pass") {
            let reason = extractReason(from: content) ?? defaultReason(.pass)
            return (.pass, truncate(reason))
        }

        throw LLMError.invalidResponse("无法解析判定结果: \(content.prefix(200))")
    }

    private func extractReason(from content: String) -> String? {
        if let rMatch = content.range(of: #""reason"\s*:\s*"([^"]{1,60})""#, options: .regularExpression) {
            let str = String(content[rMatch])
            if let start = str.range(of: "\"", range: str.index(str.startIndex, offsetBy: 8)..<str.endIndex),
               let end = str.range(of: "\"", range: start.upperBound..<str.endIndex) {
                return String(str[start.upperBound..<end.lowerBound])
            }
        }
        return nil
    }

    private func defaultReason(_ verdict: AIAnalysisResult.Verdict) -> String {
        verdict == .pass ? "各项无明显问题" : "AI 判定为废片"
    }

    private func truncate(_ s: String) -> String {
        s.count > 15 ? String(s.prefix(14)) + "…" : s
    }
}

// MARK: - 错误类型

enum LLMError: LocalizedError {
    case noAPIKey
    case noModel
    case imageEncodingFailed
    case invalidBaseURL
    case httpError(Int, String)
    case invalidResponse(String)
    case allRetriesFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "未配置 API Key"
        case .noModel: return "未选择模型"
        case .imageEncodingFailed: return "图片编码失败"
        case .invalidBaseURL: return "无效的 API 地址"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg.prefix(100))"
        case .invalidResponse(let msg): return msg
        case .allRetriesFailed: return "重试 4 次均失败"
        }
    }
}
