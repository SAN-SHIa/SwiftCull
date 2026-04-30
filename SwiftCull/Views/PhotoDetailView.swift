import SwiftUI
import Quartz

class QuickLookPreviewItem: NSObject, QLPreviewItem {
    var previewItemURL: URL?
    var previewItemTitle: String?

    init(url: URL, title: String? = nil) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated(unsafe) static let shared = QuickLookHelper()
    private var currentItem: QuickLookPreviewItem?
    private var panel: QLPreviewPanel?

    @MainActor func preview(_ url: URL) {
        currentItem = QuickLookPreviewItem(url: url)

        if let panel = panel {
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let panel = QLPreviewPanel.shared() {
                    panel.dataSource = self
                    panel.delegate = self
                    panel.makeKeyAndOrderFront(nil)
                    self.panel = panel
                }
            }
        }
    }

    @MainActor func closePanel() {
        panel?.close()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        currentItem
    }
}

struct PhotoDetailView: View {
    @EnvironmentObject var store: PhotoStore
    var showsPreview = true

    private var photo: PhotoEntry? {
        store.selectedPhoto
    }

    private let panelPadding: CGFloat = 10

    var body: some View {
        if let photo {
            VStack(spacing: 0) {
                if showsPreview {
                    imageSection(photo)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        infoSection(photo)
                        exifSection(photo)
                        ratingSection(photo)
                        tagSection(photo)
                        actionSection(photo)
                    }
                    .padding(panelPadding)
                }
                .scrollIndicators(.automatic)
            }
            .background(detailBackground)
            .frame(minWidth: 300, idealWidth: 400)
        } else {
            VStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("选择一张照片查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func imageSection(_ photo: PhotoEntry) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black.opacity(0.04))
                .overlay {
                    DetailThumbnailView(photo: photo)
                        .padding(.vertical, 5)
                }
                .frame(height: 220)
                .clipped()

            HStack {
                fileTypePill(photo)
                Spacer()
                Button {
                    openQuickLook(photo)
                } label: {
                    Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5)
            }
        }
    }

    private func openQuickLook(_ photo: PhotoEntry) {
        let path = photo.primaryImagePath
        guard !path.isEmpty else {
            if let movPath = photo.movPath {
                QuickLookHelper.shared.preview(URL(fileURLWithPath: movPath))
            }
            return
        }
        QuickLookHelper.shared.preview(URL(fileURLWithPath: path))
    }

    private func infoSection(_ photo: PhotoEntry) -> some View {
        DetailCard(title: "文件信息", systemImage: "info.circle") {
            VStack(spacing: 5) {
                detailRow("文件名", photo.displayName, canSelect: true)
                detailRow("类型") {
                    fileTypePill(photo)
                }
                detailRow("大小", photo.formattedSize)
                detailRow("日期", photo.formattedDate)
            }
        }
    }

    private func exifSection(_ photo: PhotoEntry) -> some View {
        let exif = photo.exifInfo

        return DetailCard(title: "EXIF 信息", systemImage: "camera.aperture") {
            if exif.hasAnyValue {
                VStack(spacing: 6) {
                    detailRow("相机", exif.camera ?? "未提供", canSelect: true)
                    detailRow("镜头", exif.lens ?? "未提供", canSelect: true)
                    HStack(spacing: 6) {
                        metricPill(title: "焦距", value: exif.focalLength ?? "-")
                        metricPill(title: "光圈", value: exif.aperture ?? "-")
                    }
                    HStack(spacing: 6) {
                        metricPill(title: "快门", value: exif.shutterSpeed ?? "-")
                        metricPill(title: "ISO", value: exif.iso ?? "-")
                    }
                    detailRow("拍摄时间", exif.capturedAt ?? "未提供", canSelect: true)
                }
            } else {
                emptyHint("未读取到 EXIF 信息")
            }
        }
    }

    private func ratingSection(_ photo: PhotoEntry) -> some View {
        DetailCard(title: "评分", systemImage: "star") {
            RatingView(rating: photo.rating) { newRating in
                store.setRating(newRating, for: photo)
            }
        }
    }

    private func tagSection(_ photo: PhotoEntry) -> some View {
        DetailCard(title: "标签", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 8) {
                if !photo.tags.isEmpty {
                    HStack(alignment: .top) {
                        FlowLayout(spacing: 6) {
                            ForEach(photo.tags, id: \.self) { tag in
                                TagChip(tag: tag) {
                                    store.removeTag(tag, from: photo)
                                }
                            }
                        }
                        Spacer(minLength: 6)
                        Button {
                            store.clearTags(for: photo)
                        } label: {
                            Image(systemName: "tag.slash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("清除所有标签")
                    }
                } else {
                    emptyHint("尚未添加标签")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("添加标签")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(store.availableTags.filter { !photo.tags.contains($0.name) }) { tag in
                            Button {
                                store.addTag(tag.name, to: photo)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(tag.color)
                                        .frame(width: 9, height: 9)
                                    Text(tag.displayName)
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tag.color.opacity(0.13), in: Capsule())
                                .overlay(Capsule().stroke(tag.color.opacity(0.18), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func actionSection(_ photo: PhotoEntry) -> some View {
        DetailCard(title: "操作", systemImage: "slider.horizontal.3") {
            VStack(spacing: 6) {
                if photo.hasJpg {
                    Button {
                        NSWorkspace.shared.selectFile(photo.jpgPath, inFileViewerRootedAtPath: "")
                    } label: {
                        actionLabel("在 Finder 中显示 JPG", systemImage: "folder")
                    }
                    .buttonStyle(InspectorActionButtonStyle())
                }

                if photo.hasNef {
                    Button {
                        NSWorkspace.shared.selectFile(photo.nefPath, inFileViewerRootedAtPath: "")
                    } label: {
                        actionLabel("在 Finder 中显示 NEF", systemImage: "folder")
                    }
                    .buttonStyle(InspectorActionButtonStyle())
                }

                if photo.hasMov {
                    Button {
                        NSWorkspace.shared.selectFile(photo.movPath, inFileViewerRootedAtPath: "")
                    } label: {
                        actionLabel("在 Finder 中显示 MOV", systemImage: "folder")
                    }
                    .buttonStyle(InspectorActionButtonStyle())
                }

                Button(role: .destructive) {
                    store.requestDelete(photo)
                } label: {
                    actionLabel("移至废纸篓 (所有格式)", systemImage: "trash")
                }
                .buttonStyle(InspectorActionButtonStyle(isDestructive: true))
            }
        }
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func detailRow(_ title: String, _ value: String, canSelect: Bool = false) -> some View {
        detailRow(title) {
            if canSelect {
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Spacer(minLength: 6)
            content()
        }
        .frame(minHeight: 18)
    }

    private func fileTypePill(_ photo: PhotoEntry) -> some View {
        Text(photo.fileTypeBadge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(photo.fileTypeBadgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(photo.fileTypeBadgeColor.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(photo.fileTypeBadgeColor.opacity(0.2), lineWidth: 0.5))
    }

    private func metricPill(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 28)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
        }
        .labelStyle(.titleAndIcon)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            content
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.035), radius: 6, x: 0, y: 2)
    }
}

struct InspectorActionButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .opacity(configuration.isPressed ? 0.72 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDestructive ? Color.red.opacity(0.16) : Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + rowHeight), positions)
    }
}
