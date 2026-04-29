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

    func closePanel() {
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

    private var photo: PhotoEntry? {
        store.selectedPhoto
    }

    var body: some View {
        if let photo {
            VStack(spacing: 0) {
                imageSection(photo)
                Divider()
                infoSection(photo)
                Divider()
                ratingSection(photo)
                Divider()
                tagSection(photo)
                Divider()
                actionSection(photo)
            }
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
        ZStack(alignment: .bottomTrailing) {
            DetailThumbnailView(photo: photo)
                .frame(maxHeight: 400)

            Button {
                openQuickLook(photo)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                    Text("查看大图")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(8)
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
        VStack(alignment: .leading, spacing: 6) {
            Label("文件信息", systemImage: "info.circle")
                .font(.subheadline)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("文件名")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(photo.displayName)
                        .font(.caption)
                }
                GridRow {
                    Text("类型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(photo.fileTypeBadge)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(photo.fileTypeBadgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                GridRow {
                    Text("大小")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(photo.formattedSize)
                        .font(.caption)
                }
                GridRow {
                    Text("日期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(photo.formattedDate)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratingSection(_ photo: PhotoEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("评分", systemImage: "star")
                .font(.subheadline)
                .fontWeight(.semibold)

            RatingView(rating: photo.rating) { newRating in
                store.setRating(newRating, for: photo)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagSection(_ photo: PhotoEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("标签", systemImage: "tag")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if !photo.tags.isEmpty {
                    Spacer()
                    Button {
                        store.clearTags(for: photo)
                    } label: {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除所有标签")
                }
            }

            if !photo.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(photo.tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            store.removeTag(tag, from: photo)
                        }
                    }
                }
            }

            Text("添加标签:")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            FlowLayout(spacing: 4) {
                ForEach(store.availableTags.filter { !photo.tags.contains($0.name) }) { tag in
                    Button {
                        store.addTag(tag.name, to: photo)
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 8, height: 8)
                            Text(tag.displayName)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(tag.color.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionSection(_ photo: PhotoEntry) -> some View {
        VStack(spacing: 8) {
            if photo.hasJpg {
                Button {
                    NSWorkspace.shared.selectFile(photo.jpgPath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("在 Finder 中显示 JPG", systemImage: "folder")
                        .font(.caption)
                }
            }

            if photo.hasNef {
                Button {
                    NSWorkspace.shared.selectFile(photo.nefPath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("在 Finder 中显示 NEF", systemImage: "folder")
                        .font(.caption)
                }
            }

            if photo.hasMov {
                Button {
                    NSWorkspace.shared.selectFile(photo.movPath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("在 Finder 中显示 MOV", systemImage: "folder")
                        .font(.caption)
                }
            }

            Button(role: .destructive) {
                store.requestDelete(photo)
            } label: {
                Label("移至废纸篓 (所有格式)", systemImage: "trash")
                    .font(.caption)
            }
        }
        .padding(12)
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
