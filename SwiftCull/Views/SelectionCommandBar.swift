import SwiftUI

struct BatchSectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct PanelDivider: View {
    var height: CGFloat = 24

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: height)
    }
}

/// 单个按键的键帽样式
struct KeycapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .frame(minWidth: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
            )
    }
}

private struct ShortcutHintItem: Identifiable {
    var id: String { label }
    let keys: [String]
    let label: String
}

/// 依据当前选择/浏览状态智能推荐快捷键的提示横条
struct ShortcutHintBar: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        HStack(spacing: 14) {
            Label(contextTitle, systemImage: contextIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(store.isSelectMode ? Color.accentColor : .secondary)
                .labelStyle(.titleAndIcon)

            ForEach(hints) { hint in
                HStack(spacing: 4) {
                    ForEach(Array(hint.keys.enumerated()), id: \.offset) { _, key in
                        KeycapView(label: key)
                    }
                    Text(hint.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var contextTitle: String {
        if store.viewMode == .single { return "大图浏览" }
        if store.isSelectMode { return "批量操作" }
        if store.selectedPhoto != nil { return "浏览" }
        return "提示"
    }

    private var contextIcon: String {
        if store.viewMode == .single { return "photo.fill" }
        if store.isSelectMode { return "checkmark.circle.fill" }
        if store.selectedPhoto != nil { return "hand.point.up.left.fill" }
        return "lightbulb.fill"
    }

    private var hints: [ShortcutHintItem] {
        if store.viewMode == .single {
            return [
                ShortcutHintItem(keys: ["E"], label: "退出大图浏览"),
                ShortcutHintItem(keys: ["Space"], label: "快速预览"),
                ShortcutHintItem(keys: ["←", "→"], label: "上一张 / 下一张")
            ]
        }
        if store.isSelectMode {
            return [
                ShortcutHintItem(keys: ["Q"], label: "完成并退出"),
                ShortcutHintItem(keys: ["Esc"], label: "取消"),
                ShortcutHintItem(keys: ["1–5"], label: "评分"),
                ShortcutHintItem(keys: ["⌫"], label: "删除")
            ]
        } else if store.selectedPhoto != nil {
            return [
                ShortcutHintItem(keys: ["E"], label: "大图浏览"),
                ShortcutHintItem(keys: ["Space"], label: "快速预览"),
                ShortcutHintItem(keys: ["↑", "↓", "←", "→"], label: "切换"),
                ShortcutHintItem(keys: ["拖拽"], label: "框选多张")
            ]
        } else {
            return [
                ShortcutHintItem(keys: ["拖拽"], label: "框选多张"),
                ShortcutHintItem(keys: ["E"], label: "大图浏览"),
                ShortcutHintItem(keys: ["A"], label: "全选")
            ]
        }
    }
}

/// 秒显示后，后台补充拍摄日期/标签时的细粒度进度条
struct EnrichProgressBar: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)

            Text(store.enrichStatus.isEmpty ? "正在读取拍摄信息…" : store.enrichStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: store.enrichProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 180)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
