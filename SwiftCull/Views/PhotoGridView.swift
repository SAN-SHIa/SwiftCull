import SwiftUI

struct PhotoGridView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var gridSize: CGFloat = 160
    @State private var lastSelectedPhoto: PhotoEntry?
    @State private var isSelectMode = false
    private let minGridSize: CGFloat = 100
    private let maxGridSize: CGFloat = 300

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize, maximum: gridSize + 50), spacing: 4)]
    }

    var body: some View {
        VStack(spacing: 0) {
            gridToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            if isSelectMode && store.selectedCount > 0 {
                batchActionBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.08))
            }

            Divider()

            photoContent
    }
    }

    @ViewBuilder
    private var photoContent: some View {
        if store.filteredPhotos.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("没有匹配的照片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PhotoGridContent(
                store: store,
                gridSize: gridSize,
                columns: columns,
                isSelectMode: isSelectMode,
                lastSelectedPhoto: $lastSelectedPhoto
            )
        }
    }

    private var gridToolbar: some View {
        HStack {
            if isSelectMode {
                selectModeToolbar
            } else {
                normalToolbar
            }

            Spacer()

            Slider(value: $gridSize, in: minGridSize...maxGridSize, step: 20)
                .frame(width: 120)
                .help("调整缩略图大小")

            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
        }
    }

    private var normalToolbar: some View {
        HStack(spacing: 8) {
            Text("\(store.photoCount) 张照片 · \(store.totalSize)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isSelectMode = true
                store.enterSelectMode()
            } label: {
                Label("选择", systemImage: "checkmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    private var selectModeToolbar: some View {
        HStack(spacing: 8) {
            Button {
                store.confirmSelectMode()
                isSelectMode = false
            } label: {
                Label("完成", systemImage: "checkmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button(role: .destructive) {
                store.cancelSelectMode()
                isSelectMode = false
            } label: {
                Label("取消", systemImage: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Text("已选 \(store.selectedCount) 张")
                .font(.caption)
                .foregroundStyle(store.selectedCount > 0 ? .primary : .secondary)

            Button("全选") { store.selectAll() }
                .font(.caption)
        }
    }

    private var batchActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ratingSection
                Divider().frame(height: 20)
                tagSection
                Divider().frame(height: 20)
                clearSection
                Divider().frame(height: 20)
                deleteSection
            }
        }
    }

    private var ratingSection: some View {
        HStack(spacing: 2) {
            Text("评分")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(1...5, id: \.self) { rating in
                Button(action: { store.batchSetRating(rating) }) {
                    VStack(spacing: 1) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange.opacity(0.3 + Double(rating) * 0.14))
                        Text("\(rating)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help("\(rating)星")
            }
        }
    }

    private var tagSection: some View {
        HStack(spacing: 4) {
            Text("标签")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(store.availableTags) { tag in
                Button(action: { store.batchAddTag(tag.name) }) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help(tag.displayName)
            }
        }
    }

    private var clearSection: some View {
        HStack(spacing: 4) {
            Text("清除")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: { store.batchClearRating() }) {
                VStack(spacing: 1) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 10))
                    Text("评分")
                        .font(.system(size: 7))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("清除评分")

            Button(action: { store.batchClearTags() }) {
                VStack(spacing: 1) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 10))
                    Text("标签")
                        .font(.system(size: 7))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("清除标签")
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            store.requestDeleteSelected()
        } label: {
            Label("删除", systemImage: "trash")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

struct PhotoGridContent: View {
    @ObservedObject var store: PhotoStore
    let gridSize: CGFloat
    let columns: [GridItem]
    let isSelectMode: Bool
    @Binding var lastSelectedPhoto: PhotoEntry?
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var selectionBeforeDrag: Set<String> = []

    private let gridCoordinateSpace = "photo-grid-space"

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(store.filteredPhotos) { photo in
                            SelectablePhotoCardView(
                                photo: photo,
                                gridSize: gridSize,
                                isSelected: store.selectedPhotos.contains(photo.id),
                                isPrimary: store.selectedPhoto?.id == photo.id,
                                isSelectMode: isSelectMode
                            )
                            .id(photo.id)
                            .onTapGesture {
                                handleTap(photo: photo)
                            }
                            .background(
                                GeometryReader { itemGeometry in
                                    Color.clear.preference(
                                        key: PhotoItemFramePreferenceKey.self,
                                        value: [photo.id: itemGeometry.frame(in: .named(gridCoordinateSpace))]
                                    )
                                }
                            )
                        }
                    }
                    .padding(4)
                }
                .coordinateSpace(name: gridCoordinateSpace)
                .overlay(alignment: .topLeading) {
                    if let selectionRect {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .offset(x: selectionRect.minX, y: selectionRect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(selectionDragGesture)
                .onPreferenceChange(PhotoItemFramePreferenceKey.self) { frames in
                    itemFrames = frames
                }
                .onAppear {
                    updateGridColumnCount(width: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, width in
                    updateGridColumnCount(width: width)
                }
                .onChange(of: gridSize) { _, _ in
                    updateGridColumnCount(width: geometry.size.width)
                }
            }
            .onChange(of: store.selectedPhoto?.id) { _, newId in
                if let newId = newId {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(gridCoordinateSpace))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    selectionBeforeDrag = NSEvent.modifierFlags.contains(.shift) ? store.selectedPhotos : []
                }
                dragCurrent = value.location
                updateDragSelection()
            }
            .onEnded { _ in
                updateDragSelection()
                dragStart = nil
                dragCurrent = nil
                selectionBeforeDrag = []
            }
    }

    private func updateDragSelection() {
        guard let selectionRect else { return }
        let selectedIds = itemFrames.reduce(into: selectionBeforeDrag) { result, item in
            if item.value.intersects(selectionRect) {
                result.insert(item.key)
            }
        }
        store.selectPhotoIds(selectedIds)
        if let selected = store.selectedPhoto {
            lastSelectedPhoto = selected
        }
    }

    private func updateGridColumnCount(width: CGFloat) {
        let columnWidth = gridSize + 4
        let count = max(1, Int((width + 4) / columnWidth))
        store.updateGridColumnCount(count)
    }

    private func handleTap(photo: PhotoEntry) {
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)

        if isSelectMode {
            if isShiftPressed, let last = lastSelectedPhoto {
                store.selectRange(from: last, to: photo)
            } else {
                store.toggleSelection(photo)
                lastSelectedPhoto = photo
            }
        } else {
            if isShiftPressed, let last = lastSelectedPhoto {
                store.selectRange(from: last, to: photo)
            } else if isCommandPressed {
                store.toggleSelection(photo)
                lastSelectedPhoto = photo
            } else {
                store.selectPhoto(photo)
                lastSelectedPhoto = photo
            }
        }
    }
}

struct PhotoItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SelectablePhotoCardView: View {
    let photo: PhotoEntry
    let gridSize: CGFloat
    let isSelected: Bool
    let isPrimary: Bool
    let isSelectMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            cardImage
            infoBar
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(cardBorder)
    }

    private var cardImage: some View {
        ZStack {
            AsyncThumbnailView(
                photoId: photo.id,
                imagePath: photo.primaryFilePath,
                size: gridSize,
                isVideo: photo.isVideoOnly
            )
            .frame(width: gridSize, height: gridSize)

            badgeOverlay

            if isSelected && !isPrimary {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
            }

            if isSelectMode {
                selectCheckOverlay
            }
        }
        .frame(width: gridSize, height: gridSize)
        .clipped()
    }

    private var selectCheckOverlay: some View {
        VStack {
            HStack {
                Spacer()
                selectCheck
            }
            Spacer()
        }
        .padding(4)
    }

    private var selectCheck: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.black.opacity(0.4))
                .frame(width: 20, height: 20)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var badgeOverlay: some View {
        VStack {
            HStack {
                topLeftBadge
                Spacer()
                if !isSelectMode {
                    topRightBadge
                }
            }
            Spacer()
        }
        .padding(4)
    }

    private var cardBackground: Color {
        if isPrimary { return Color.accentColor.opacity(0.15) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        return Color.clear
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(
                isPrimary ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.5) : Color.clear),
                lineWidth: isPrimary ? 2 : 1
            )
    }

    private var topLeftBadge: some View {
        Group {
            if photo.hasAnyMark {
                HStack(spacing: 3) {
                    if photo.workflowMark != .none {
                        workflowBadge
                    }
                    if photo.rating > 0 {
                        ratingBadge
                    }
                    ForEach(photo.tags.prefix(3), id: \.self) { tagName in
                        Circle()
                            .fill(FinderTagService.shared.colorForTag(tagName))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
            }
        }
    }

    private var workflowBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: photo.workflowMark == .pick ? "flag.fill" : "xmark")
                .font(.system(size: 8, weight: .bold))
            Text(photo.workflowMark == .pick ? "P" : "X")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(photo.workflowMark == .pick ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
        .clipShape(Capsule())
    }

    private var ratingBadge: some View {
        HStack(spacing: 1) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("\(photo.rating)")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.9))
        .clipShape(Capsule())
    }

    private var topRightBadge: some View {
        Text(photo.fileTypeBadge)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(photo.fileTypeBadgeColor.opacity(0.85))
            .clipShape(Capsule())
    }

    private var infoBar: some View {
        VStack(spacing: 2) {
            Text(photo.displayName)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Text(photo.formattedDate)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)

                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: gridSize)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}
