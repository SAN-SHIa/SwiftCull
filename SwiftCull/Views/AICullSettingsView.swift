import SwiftUI

/// AI 筛选设置面板（自管理状态版本，供 ContentView sheet 调用）
struct AICullSettingsSheet: View {
    let store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: LLMProvider = .mimo
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "mimo-v2.5"
    @State private var customBaseURL: String = ""
    @State private var strength: String = "standard"
    @State private var enablePreScreen: Bool = true
    @State private var showingKey = false
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 520, height: 600)
        .onAppear {
            // 从 LLMService 加载已保存的配置
            Task {
                let llm = LLMService.shared
                let currentProvider = await llm.currentProvider
                let hasKey = await llm.hasAPIKey
                provider = currentProvider
                if hasKey { apiKey = "••••••" }  // 占位，不暴露
                selectedModel = currentProvider.defaultModels.first ?? ""
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.purple)
            Text("AI 快速筛选")
                .font(.title2.bold())
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingCard(title: "LLM 提供商", icon: "cloud") {
                    Picker("", selection: $provider) {
                        ForEach(LLMProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: provider) { _, new in
                        selectedModel = new.defaultModels.first ?? ""
                    }
                }

                settingCard(title: "API Key", icon: "key") {
                    HStack {
                        if showingKey {
                            TextField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button { showingKey.toggle() } label: {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if provider == .custom {
                    settingCard(title: "API 地址", icon: "link") {
                        TextField("https://api.example.com/v1", text: $customBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                settingCard(title: "模型", icon: "cpu") {
                    if provider.defaultModels.count > 1 {
                        Picker("", selection: $selectedModel) {
                            ForEach(provider.defaultModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .labelsHidden()
                    } else {
                        TextField("模型 ID", text: $selectedModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                settingCard(title: "判定强度", icon: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $strength) {
                            Text("标准").tag("standard")
                            Text("严格").tag("advanced")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(strength == "standard"
                             ? "标准：适合日常选片，对小瑕疵较宽容"
                             : "严格：适合商业样片，对模糊/表情/姿态更敏感")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingCard(title: "本地预筛", icon: "eye.trianglebadge.exclamationmark") {
                    Toggle("先用本地算法过滤明显废片（省 API 费用）", isOn: $enablePreScreen)
                }

                HStack {
                    Button("测试连接") {
                        Task { await testConnection() }
                    }
                    .disabled(apiKey.isEmpty || testStatus == .testing)

                    switch testStatus {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            Text("照片将在本地预筛后发送给 AI 评判")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                // 保存配置
                Task {
                    let llm = LLMService.shared
                    await llm.setProvider(provider)
                    if apiKey != "••••••" { await llm.setAPIKey(apiKey) }
                    if provider == .custom { await llm.setCustomBaseURL(customBaseURL) }
                }
                dismiss()
                store.confirmAICull(
                    provider: provider,
                    model: selectedModel,
                    speed: .standard
                )
            } label: {
                Label("开始筛选", systemImage: "brain.head.profile")
                    .font(.headline)
                    .frame(width: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(apiKey.isEmpty || selectedModel.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private func settingCard<Content: View>(title: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func testConnection() async {
        testStatus = .testing
        let llm = LLMService.shared
        await llm.setProvider(provider)
        if apiKey != "••••••" { await llm.setAPIKey(apiKey) }
        if provider == .custom { await llm.setCustomBaseURL(customBaseURL) }

        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let testImage = ctx.makeImage() else {
            testStatus = .failure("无法创建测试图")
            return
        }
        do {
            _ = try await llm.judgeImage(testImage, model: selectedModel)
            testStatus = .success("连接成功")
        } catch {
            testStatus = .failure(error.localizedDescription)
        }
    }
}
