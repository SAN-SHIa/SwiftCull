import Foundation

/// LLM 对单张照片的判定结果
struct AIAnalysisResult: Hashable, Sendable {
    enum Verdict: String, Hashable, Sendable {
        case pass
        case reject

        var displayName: String {
            switch self {
            case .pass: return "通过"
            case .reject: return "废片"
            }
        }

        var systemImage: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .reject: return "xmark.circle.fill"
            }
        }
    }

    let verdict: Verdict
    let reason: String          // ≤15 字中文理由
    let provider: String        // "ark" / "mimo" / "custom"
    let model: String
    let analyzedAt: Date
}

/// LLM 提供商定义
enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    case mimo
    case ark
    case minimax
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mimo: return "小米 MiMo"
        case .ark: return "火山引擎 Ark"
        case .minimax: return "MiniMax"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .mimo: return "https://token-plan-cn.xiaomimimo.com/v1"
        case .ark: return "https://ark.cn-beijing.volces.com/api/v3"
        case .minimax: return "https://api.minimaxi.com/v1"
        case .custom: return ""
        }
    }

    var keyEnvName: String {
        switch self {
        case .mimo: return "MIMO_API_KEY"
        case .ark: return "ARK_API_KEY"
        case .minimax: return "MINIMAX_API_KEY"
        case .custom: return "LLM_API_KEY"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .mimo: return ["mimo-v2.5"]
        case .ark: return ["doubao-1.5-vision-pro-32k"]
        case .minimax: return ["MiniMax-VL-01"]
        case .custom: return []
        }
    }

    /// 需要从 API 动态拉取模型列表
    var modelsFromAPI: Bool {
        switch self {
        case .ark: return true
        default: return false
        }
    }
}
