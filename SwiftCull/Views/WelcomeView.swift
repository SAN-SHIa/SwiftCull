import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary.opacity(0.7))

                Text("SwiftCull")
                    .font(.title.weight(.bold))

                if store.errorMessage != nil {
                    Text(store.errorMessage!)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    Text("打开一个包含照片的文件夹开始浏览")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                store.selectPath()
            } label: {
                Label("打开文件夹", systemImage: "folder.badge.plus")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !store.detectedVolumes.isEmpty {
                VStack(spacing: 10) {
                    Text("快速访问")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)

                    ForEach(store.detectedVolumes) { volume in
                        Button {
                            store.sourcePath = volume.path
                            Task {
                                await store.loadPhotos()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: volume.icon)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(volume.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(volume.path)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360)
            }

            Text("⌘O 随时打开文件夹")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ShortcutGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("↑ ↓ ← →", "按网格位置选择照片"),
        ("拖拽框选", "鼠标框选多张照片"),
        ("Space", "Quick Look 预览"),
        ("E", "网格 / 大图切换"),
        ("大图缩放", "捏合 / 双击 / ＋ － 缩放，拖拽平移"),
        ("Tab", "切换侧边栏"),
        ("1-5", "设置评分"),
        ("0", "清除评分"),
        ("Delete", "删除所选照片"),
        ("A", "全选当前筛选结果"),
        ("Esc", "退出多选 / 取消输入焦点"),
        ("⌘O", "打开文件夹")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("快捷键手册", systemImage: "keyboard")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut, action in
                    GridRow {
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(action)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

struct ToolbarInfoView: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        if store.selectedCount > 1 {
            Text("已选 \(store.selectedCount) / \(store.totalPhotoCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(store.photoCount) / \(store.totalPhotoCount) 张照片")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoSinglePreviewView: View {
    let photo: PhotoEntry

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 6

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                DetailThumbnailView(photo: photo, targetSize: 1800)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(magnifyGesture(in: geo.size))
                    .simultaneousGesture(panGesture(in: geo.size))
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture(count: 1) { resignFocus() }
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in containerSize = newValue }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .clipped()
        }
        .overlay(alignment: .bottom) { infoBar }
        .overlay(alignment: .topTrailing) { zoomControls }
        .onChange(of: photo.id) { _, _ in resetZoom() }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.74)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var infoBar: some View {
        HStack(spacing: 8) {
            Text(photo.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(photo.fileTypeBadge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(photo.fileTypeBadgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(photo.fileTypeBadgeColor.opacity(0.14), in: Capsule())

            Spacer()

            Text(photo.formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(14)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoomBy(1 / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(scale <= minScale)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { resetZoom() }
            } label: {
                Text("\(Int((scale * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(minWidth: 44)
            }
            .help("重置缩放")

            Button {
                zoomBy(1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(scale >= maxScale)
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .padding(14)
    }

    // MARK: - Zoom & Pan

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value.magnification, minScale), maxScale)
                offset = clampedOffset(offset, in: size)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= minScale {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { resetZoom() }
                } else {
                    steadyOffset = offset
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                let proposed = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: size)
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                steadyOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 2.5
                steadyScale = 2.5
            }
        }
    }

    private func zoomBy(_ factor: CGFloat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            scale = min(max(scale * factor, minScale), maxScale)
            steadyScale = scale
            if scale <= minScale {
                offset = .zero
                steadyOffset = .zero
            } else {
                offset = clampedOffset(offset, in: containerSize)
                steadyOffset = offset
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        steadyScale = minScale
        offset = .zero
        steadyOffset = .zero
    }

    /// 将平移量限制在缩放后图片的可视范围内
    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func resignFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
