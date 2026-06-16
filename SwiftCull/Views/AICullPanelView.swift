import SwiftUI

// MARK: - 主面板

struct AICullPanelView: View {
    @ObservedObject var cullService: AICullService
    @EnvironmentObject var store: PhotoStore

    @State private var selectedMode: AICullMode = .local
    @State private var provider: LLMProvider = .mimo
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "mimo-v2.5"
    @State private var customBaseURL: String = ""
    @State private var selectedSpeed: AICullSpeed = .standard
    @State private var showingKey = false
    @State private var isExpanded = true
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle, testing, success(String), failure(String)
    }

private struct AnalyzingPreviewThumbnail: View {
    let path: String
    @State private var displayPath: String = ""
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if displayPath.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                } else {
                    AsyncThumbnailView(
                        photoId: displayPath,
                        imagePath: displayPath,
                        size: max(200, geo.size.width)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    ScanLineOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .task(id: path) {
            updateTask?.cancel()
            let next = path
            guard !next.isEmpty else {
                displayPath = ""
                return
            }
            if displayPath.isEmpty {
                displayPath = next
                return
            }
            updateTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                displayPath = next
            }
        }
        .onDisappear {
            updateTask?.cancel()
        }
    }
}

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded { content }
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .onAppear { loadSavedConfig() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("AI 筛选")
                .font(.system(size: 13, weight: .semibold))

            if cullService.phase == .done {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            if cullService.isAnalyzing {
                HStack(spacing: 6) {
                    PulsingDot(color: Color.accentColor)
                    Text(cullService.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(cullService.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }

            Button {
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.compact.\(isExpanded ? "up" : "down")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() } }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 10) {
            Divider().padding(.horizontal, 12)

            switch cullService.phase {
            case .idle: configSection
            case .preScreening, .analyzing: analyzingSection
            case .done: resultSection
            }
        }
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Config（macOS 26 玻璃风格）

    private var configSection: some View {
        VStack(spacing: 10) {
            // 模式切换（玻璃滑块效果）
            GlassSegmentedPicker(
                selection: $selectedMode,
                items: AICullMode.allCases
            ) { mode in
                Label(mode.displayName, systemImage: mode.icon)
            }
            .padding(.horizontal, 12)

            // 说明区
            modeDescription
                .padding(.horizontal, 12)

            // LLM 速度 + 配置
            if selectedMode == .llm {
                llmConfigSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 开始按钮
            HStack {
                Spacer()
                let count = store.filteredPhotos.isEmpty ? store.totalPhotoCount : store.filteredPhotos.count
                Button { startAnalysis() } label: {
                    Label("筛选 \(count) 张", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.accentColor)
                .disabled(selectedMode == .llm && (apiKey.isEmpty || selectedModel.isEmpty))
            }
            .padding(.horizontal, 12)
        }
        .animation(.smooth(duration: 0.25), value: selectedMode)
    }

    // 模式说明 + 本地检测项
    @ViewBuilder
    private var modeDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedMode.detailDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if selectedMode == .local {
                // 检测项列表
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(selectedMode.localCheckItems.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Image(systemName: item.0)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)
                            Text(item.1)
                                .font(.system(size: 12, weight: .medium))
                            Text(item.2)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // LLM 配置
    private var llmConfigSection: some View {
        VStack(spacing: 6) {
            // 速度切换
            GlassSegmentedPicker(
                selection: $selectedSpeed,
                items: AICullSpeed.allCases
            ) { speed in
                Text(speed.displayName)
            }
            .padding(.horizontal, 12)
            .help("极速：快速粗筛 · 标准：均衡 · 严格：高精度")

            // API 配置
            HStack(spacing: 6) {
                Picker("", selection: $provider) {
                    ForEach(LLMProvider.allCases) { p in Text(p.displayName).tag(p) }
                }
                .labelsHidden().frame(width: 110).controlSize(.small)
                .onChange(of: provider) { _, new in selectedModel = new.defaultModels.first ?? "" }

                if provider.defaultModels.count > 1 {
                    Picker("", selection: $selectedModel) {
                        ForEach(provider.defaultModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden().frame(width: 150).controlSize(.small)
                } else {
                    TextField("模型", text: $selectedModel)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                }

                Group {
                    if showingKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder).font(.caption)

                Button { showingKey.toggle() } label: {
                    Image(systemName: showingKey ? "eye.slash" : "eye").font(.caption2)
                }
                .buttonStyle(.borderless)

                if provider == .custom {
                    TextField("地址", text: $customBaseURL)
                        .textFieldStyle(.roundedBorder).frame(width: 140)
                }

                Spacer()

                Button("测试") { Task { await testConnection() } }
                    .controlSize(.small)
                    .disabled(apiKey.isEmpty || testStatus == .testing)

                switch testStatus {
                case .idle: EmptyView()
                case .testing: ProgressView().controlSize(.mini)
                case .success(let m):
                    Label(m, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption2)
                case .failure(let m):
                    Label(m, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red).font(.caption2).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Analyzing

    private var analyzingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulsingDot(color: Color.accentColor)
                Text(cullService.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(cullService.progress * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
            }

            ProgressView(value: cullService.progress)
                .tint(Color.accentColor)

            HStack(spacing: 12) {
                PopCounter(value: cullService.passCount, color: .green, icon: "checkmark.circle.fill")
                PopCounter(value: cullService.allRejectCount, color: .red, icon: "xmark.circle.fill")
                Spacer()
                Button("取消") { store.cancelAICull() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    private var eventStream: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(cullService.recentEvents.prefix(20).enumerated()), id: \.element.id) { idx, event in
                        EventChip(event: event)
                            .id(event.id)
                            .opacity(max(0.3, 1.0 - Double(idx) * 0.04))
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: cullService.recentEvents.first?.id) { _, newId in
                if let newId {
                    withAnimation(.smooth(duration: 0.2)) {
                        proxy.scrollTo(newId, anchor: .leading)
                    }
                }
            }
        }
        .frame(height: 24)
    }

    // MARK: - Result

    private var resultSection: some View {
        let s = cullService.summary(
            photos: store.filteredPhotos.isEmpty ? store.photos : store.filteredPhotos
        )
        return HStack(spacing: 10) {
            ResultPill(icon: "photo.stack", value: "\(s.total)", label: "总计")
            ResultPill(icon: "checkmark.circle.fill", value: "\(s.pass)", label: "通过", color: .green)
            ResultPill(icon: "xmark.circle.fill", value: "\(s.reject + s.preReject)", label: "废片", color: .red)
            ResultPill(icon: "arrow.down.circle.fill", value: s.savedSpace, label: "释放", color: .orange)

            Spacer()

            Text("废片率 \(Int(s.rejectRate * 100))%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
                .contentTransition(.numericText())

            Button { store.showingAICullReview = true } label: {
                Label("详情", systemImage: "eye")
            }
            .controlSize(.small)

            Button { applyResults() } label: {
                Label("应用标记", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.accentColor)

            Button { resetCull() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("重新筛选")
        }
        .padding(.horizontal, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Actions

    private func loadSavedConfig() {
        Task {
            let llm = LLMService.shared
            let cp = await llm.currentProvider
            let hk = await llm.hasAPIKey
            provider = cp
            if hk { apiKey = "saved" }
            selectedModel = cp.defaultModels.first ?? ""
        }
    }

    private func startAnalysis() {
        let photos = store.filteredPhotos.isEmpty ? store.photos : store.filteredPhotos
        if selectedMode == .local {
            cullService.analyze(photos: photos, mode: .local)
        } else {
            Task {
                let llm = LLMService.shared
                await llm.setProvider(provider)
                if apiKey != "saved" { await llm.setAPIKey(apiKey) }
                if provider == .custom { await llm.setCustomBaseURL(customBaseURL) }
                cullService.analyze(photos: photos, mode: .llm,
                                    provider: provider, model: selectedModel,
                                    speed: selectedSpeed)
            }
        }
    }

    private func applyResults() {
        let photos = store.filteredPhotos.isEmpty ? store.photos : store.filteredPhotos
        store.applyAICullResults(markedPhotos: photos)
    }

    private func resetCull() {
        cullService.phase = .idle
        cullService.progress = 0
        cullService.results = [:]
        cullService.preRejects = [:]
        cullService.recentEvents = []
        cullService.analyzedPhotos = []
    }

    private func testConnection() async {
        testStatus = .testing
        let llm = LLMService.shared
        await llm.setProvider(provider)
        if apiKey != "saved" { await llm.setAPIKey(apiKey) }
        if provider == .custom { await llm.setCustomBaseURL(customBaseURL) }
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage() else {
            testStatus = .failure("测试图创建失败"); return
        }
        do {
            _ = try await llm.judgeImage(img, model: selectedModel)
            testStatus = .success("OK")
        } catch {
            testStatus = .failure(error.localizedDescription)
        }
    }
}

// MARK: - 玻璃分段选择器（macOS 26 风格）

private struct GlassSegmentedPicker<T: Hashable & CaseIterable & Identifiable, Content: View>: View {
    @Binding var selection: T
    let items: [T]
    @ViewBuilder let label: (T) -> Content

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.smooth(duration: 0.35)) {
                        selection = item
                    }
                } label: {
                    label(item)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                                    )
                                    .transition(.opacity.animation(.smooth(duration: 0.3)))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Components

private struct PulsingDot: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(on ? 1.6 : 0.7)
            .opacity(on ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private struct PopCounter: View {
    let value: Int
    let color: Color
    let icon: String
    @State private var pop = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(pop ? color : .primary)
                .contentTransition(.numericText())
                .scaleEffect(pop ? 1.35 : 1.0)
                .animation(.interpolatingSpring(stiffness: 400, damping: 10), value: pop)
        }
        .onChange(of: value) { _, _ in
            pop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pop = false }
        }
    }
}

private struct ScanLineOverlay: View {
    @State private var y: CGFloat = -0.2
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(height: max(4, geo.size.height * 0.12))
                .offset(y: y * geo.size.height)
                .blur(radius: 1)
        }
        .compositingGroup()
        .opacity(0.7)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                y = 1.3
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EventChip: View {
    let event: AICullEvent
    var body: some View {
        HStack(spacing: 4) {
            if event.verdict == .reject {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(event.photoName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(event.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                Text(event.photoName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(event.verdict == .reject
                           ? Color.red.opacity(0.08)
                           : Color.green.opacity(0.05))
        )
    }
}

private struct ResultPill: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
