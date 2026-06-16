import SwiftUI

/// 网格卡片废片标记（只标废片，通过的不显示）
struct AIResultBadge: View {
    let result: AIAnalysisResult?

    var body: some View {
        if let result, result.verdict == .reject {
            rejectOverlay(reason: result.reason)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7).combined(with: .opacity).animation(.interpolatingSpring(stiffness: 300, damping: 15)),
                    removal: .opacity.animation(.easeOut(duration: 0.2))
                ))
        }
    }

    @ViewBuilder
    private func rejectOverlay(reason: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 暗角遮罩（更强对比）
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.6), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 左侧红色色条（更粗更亮）
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 3)
                Spacer()
            }

            // 底部原因标签（更大更醒目）
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(reason)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(.red.opacity(0.9)))
            .shadow(color: .red.opacity(0.5), radius: 4, y: 2)
            .padding(4)
        }
        .overlay(
            // 红色边框（更醒目）
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.red.opacity(0.6), lineWidth: 2)
        )
        .allowsHitTesting(false)
    }
}

/// 扫描线覆盖层（分析中使用）
struct AIScanningOverlay: View {
    @State private var y: CGFloat = -0.2

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: max(3, geo.size.height * 0.1))
                .offset(y: y * geo.size.height)
                .blur(radius: 0.5)
        }
        .compositingGroup()
        .opacity(0.6)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                y = 1.3
            }
        }
        .allowsHitTesting(false)
    }
}

/// 废片原因标签
struct RejectReasonTag: View {
    let reason: String
    @State private var visible = false

    var body: some View {
        Text(reason)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.red))
            .shadow(color: .red.opacity(0.25), radius: 4, y: 2)
            .offset(y: visible ? 0 : 16)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.85)
            .onAppear {
                withAnimation(.interpolatingSpring(stiffness: 350, damping: 14).delay(0.08)) {
                    visible = true
                }
            }
    }
}
