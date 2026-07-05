import SwiftUI

enum PhotoGroupingMode: String, CaseIterable, Identifiable {
    case all
    case month
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "所有"
        case .month: return "月"
        case .day: return "日"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "photo.stack"
        case .month: return "calendar"
        case .day: return "calendar.day.timeline.left"
        }
    }
}

enum PhotoSelectionScope {
    case all
    case month
    case day
}

struct PhotoGridView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var gridSize: CGFloat = 110
    @State private var lastSelectedPhoto: PhotoEntry?
    @State private var groupingMode: PhotoGroupingMode = .all
    private let minGridSize: CGFloat = 80
    private let maxGridSize: CGFloat = 220

    private var isSelectMode: Bool { store.isSelectMode }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize, maximum: gridSize + 50), spacing: 4)]
    }

    var body: some View {
        VStack(spacing: 0) {
            gridToolbar
                .padding(.horizontal, 22)
                .padding(.vertical, 7)
                .background(.bar)

            Divider()

            if store.isSelectMode {
                selectionCommandPanel
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .transition(.move(edge: .top).combined(with: .opacity))

                Divider()
            }

            photoContent
        }
        .animation(.snappy(duration: 0.24), value: store.isSelectMode)
        .animation(.snappy(duration: 0.2), value: store.selectedCount)
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
                groupingMode: groupingMode,
                isSelectMode: store.isSelectMode,
                lastSelectedPhoto: $lastSelectedPhoto
            )
        }
    }

    private var gridToolbar: some View {
        HStack(spacing: 12) {
            normalToolbar

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                Slider(value: $gridSize, in: minGridSize...maxGridSize)
                    .frame(width: 150)
                    .help("缩略图 \(Int(gridSize))px")

                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .padding(.trailing, 8)
        }
    }

    private var normalToolbar: some View {
        HStack(spacing: 8) {
            Text("\(store.photoCount) 张照片 · \(store.totalSize)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button {
                    beginSelectMode()
                } label: {
                    Label("进入选择模式", systemImage: "checkmark.circle")
                }

                Divider()

                Button {
                    selectPhotos(.all)
                } label: {
                    Label("选择所有照片", systemImage: "photo.stack")
                }

                Button {
                    selectPhotos(.month)
                } label: {
                    Label("选择当前月份", systemImage: "calendar")
                }
                .disabled(selectionReferencePhoto == nil)

                Button {
                    selectPhotos(.day)
                } label: {
                    Label("选择当前日期", systemImage: "calendar.day.timeline.left")
                }
                .disabled(selectionReferencePhoto == nil)
            } label: {
                Label("选择", systemImage: "checkmark.circle")
                    .font(.caption)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Picker("分组", selection: $groupingMode) {
                ForEach(PhotoGroupingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 148)
            .help("按拍摄时间分组")
        }
    }

    private var selectionCommandPanel: some View {
        ViewThatFits(in: .horizontal) {
            regularSelectionPanel
            denseSelectionPanel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 1280, minHeight: 42, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.34))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var regularSelectionPanel: some View {
        HStack(spacing: 10) {
            selectionCommitSection
            PanelDivider(height: 24)
            ratingSection
            PanelDivider(height: 24)
            tagSection
            PanelDivider(height: 24)
            clearSection
            Spacer(minLength: 8)
            deleteSection
        }
    }

    private var denseSelectionPanel: some View {
        HStack(spacing: 8) {
            compactSelectionCommitSection
            PanelDivider(height: 22)
            denseRatingSection
            PanelDivider(height: 22)
            denseTagSection
            PanelDivider(height: 22)
            denseClearSection
            Spacer(minLength: 6)
            deleteSection
        }
    }

    private var selectionCommitSection: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: store.selectedCount > 0 ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.selectedCount > 0 ? Color.accentColor : Color.secondary)
                Text(store.selectedCount > 0 ? "\(store.selectedCount) 张" : "未选")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(width: 64, alignment: .leading)

            Button {
                finishSelectMode()
            } label: {
                Label("完成", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 28)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(SelectionPrimaryButtonStyle())
            .disabled(!isSelectMode)

            Button {
                cancelSelectMode()
            } label: {
                Label("取消", systemImage: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 28)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(SelectionSecondaryButtonStyle())
            .disabled(!isSelectMode)
        }
    }

    private var compactSelectionCommitSection: some View {
        HStack(spacing: 6) {
            Text(store.selectedCount > 0 ? "\(store.selectedCount) 张" : "未选")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)

            Button {
                finishSelectMode()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 28, height: 28))
            .disabled(!isSelectMode)
            .help("完成")

            Button {
                cancelSelectMode()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 28, height: 28))
            .disabled(!isSelectMode)
            .help("取消")
        }
    }

    private var ratingSection: some View {
        HStack(spacing: 6) {
            BatchSectionLabel(title: "评分", systemImage: "star")

            ForEach(1...5, id: \.self) { rating in
                Button(action: { store.batchSetRating(rating) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.3 + Double(rating) * 0.14))
                        Text("\(rating)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(SelectionIconButtonStyle(width: 40, height: 30))
                .disabled(store.selectedCount == 0)
                .help("\(rating)星")
            }
        }
    }

    private var denseRatingSection: some View {
        HStack(spacing: 4) {
            Image(systemName: "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            ForEach(1...5, id: \.self) { rating in
                Button(action: { store.batchSetRating(rating) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.3 + Double(rating) * 0.14))
                        Text("\(rating)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(SelectionIconButtonStyle(width: 34, height: 28))
                .disabled(store.selectedCount == 0)
                .help("\(rating)星")
            }
        }
    }

    private var tagSection: some View {
        HStack(spacing: 6) {
            BatchSectionLabel(title: "标签", systemImage: "tag")

            ForEach(store.availableTags) { tag in
                Button(action: { store.batchAddTag(tag.name) }) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                }
                .buttonStyle(SelectionIconButtonStyle(width: 28, height: 28, cornerRadius: 7))
                .disabled(store.selectedCount == 0)
                .help(tag.displayName)
            }
        }
    }

    private var denseTagSection: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            ForEach(store.availableTags) { tag in
                Button(action: { store.batchAddTag(tag.name) }) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                }
                .buttonStyle(SelectionIconButtonStyle(width: 24, height: 28, cornerRadius: 7))
                .disabled(store.selectedCount == 0)
                .help(tag.displayName)
            }
        }
    }

    private var clearSection: some View {
        HStack(spacing: 6) {
            BatchSectionLabel(title: "清除", systemImage: "eraser")

            Button(action: { store.batchClearRating() }) {
                Image(systemName: "star.slash")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 34, height: 30))
            .disabled(store.selectedCount == 0)
            .help("清除评分")

            Button(action: { store.batchClearTags() }) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 34, height: 30))
            .disabled(store.selectedCount == 0)
            .help("清除标签")
        }
    }

    private var denseClearSection: some View {
        HStack(spacing: 4) {
            Button(action: { store.batchClearRating() }) {
                Image(systemName: "star.slash")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 30, height: 28))
            .disabled(store.selectedCount == 0)
            .help("清除评分")

            Button(action: { store.batchClearTags() }) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SelectionIconButtonStyle(width: 30, height: 28))
            .disabled(store.selectedCount == 0)
            .help("清除标签")
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            store.requestDeleteSelected()
        } label: {
            Label("删除", systemImage: "trash")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(height: 28)
        }
        .buttonStyle(SelectionDestructiveButtonStyle())
        .disabled(store.selectedCount == 0)
    }

    private var selectionReferencePhoto: PhotoEntry? {
        store.selectedPhoto ?? store.selectedPhotoEntries.first ?? store.filteredPhotos.first
    }

    private func selectPhotos(_ scope: PhotoSelectionScope) {
        beginSelectMode()

        switch scope {
        case .all:
            groupingMode = .all
            store.selectAll()
        case .month:
            groupingMode = .month
            selectPhotos(matching: .month)
        case .day:
            groupingMode = .day
            selectPhotos(matching: .day)
        }
    }

    private func selectPhotos(matching component: Calendar.Component) {
        guard let reference = selectionReferencePhoto else { return }
        let calendar = Calendar.current
        let ids = Set(store.filteredPhotos
            .filter { calendar.isDate($0.fileDate, equalTo: reference.fileDate, toGranularity: component) }
            .map(\.id))
        store.selectPhotoIds(ids)
    }

    private func beginSelectMode() {
        guard !store.isSelectMode else { return }
        store.enterSelectMode()
    }

    private func finishSelectMode() {
        store.confirmSelectMode()
        lastSelectedPhoto = nil
    }

    private func cancelSelectMode() {
        store.cancelSelectMode()
        lastSelectedPhoto = nil
    }
}

// MARK: - Grid Content & Drag Selection

struct PhotoGridSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let photos: [PhotoEntry]
}

private struct PhotoGroupHeader: View {
    let group: PhotoGridSection
    let isSelectMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(group.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelectMode {
                Button(action: onToggleSelection) {
                    Label(isSelected ? "取消本组" : "选择本组", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                }
                .buttonStyle(SelectionSecondaryButtonStyle())
                .help(isSelected ? "取消选择本组照片" : "选择本组照片")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PhotoGridContent: View {
    @ObservedObject var store: PhotoStore
    let gridSize: CGFloat
    let columns: [GridItem]
    let groupingMode: PhotoGroupingMode
    let isSelectMode: Bool
    @Binding var lastSelectedPhoto: PhotoEntry?
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragBaselineSelection: Set<String> = []
    @State private var dragSelectionMode: DragSelectionMode = .replace
    @State private var cachedPhotoIds: Set<String> = []
    @State private var lastDragUpdateTime: CFAbsoluteTime = 0

    private let gridCoordinateSpace = "photo-grid-space"

    private func selectionOverlay(for rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.14))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1)
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    private var photoGroups: [PhotoGridSection] {
        switch groupingMode {
        case .all:
            return [PhotoGridSection(id: "all", title: "所有照片", subtitle: "\(store.filteredPhotos.count) 张", photos: store.filteredPhotos)]
        case .month:
            return makePhotoGroups(granularity: .month)
        case .day:
            return makePhotoGroups(granularity: .day)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        if groupingMode == .all {
                            ForEach(store.filteredPhotos) { photo in
                                photoCard(photo)
                            }
                        } else {
                            ForEach(photoGroups) { group in
                                Section {
                                    ForEach(group.photos) { photo in
                                        photoCard(photo)
                                    }
                                } header: {
                                    PhotoGroupHeader(
                                        group: group,
                                        isSelectMode: isSelectMode,
                                        isSelected: isGroupSelected(group)
                                    ) {
                                        toggleGroupSelection(group)
                                    }
                                }
                            }
                        }
                    }
                    .padding(4)
                    .coordinateSpace(name: gridCoordinateSpace)
                    .overlay(alignment: .topLeading) {
                        if let selectionRect {
                            selectionOverlay(for: selectionRect)
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(selectionDragGesture)
                    .onPreferenceChange(PhotoItemFramePreferenceKey.self) { frames in
                        if dragStart == nil {
                            itemFrames = frames
                        } else {
                            itemFrames.merge(frames, uniquingKeysWith: { _, new in new })
                            updateDragSelection()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .onAppear {
                    updateGridColumnCount(width: geometry.size.width)
                    cachedPhotoIds = Set(store.filteredPhotos.map(\.id))
                }
                .onChange(of: geometry.size.width) { _, width in
                    itemFrames = [:]
                    updateGridColumnCount(width: width)
                }
                .onChange(of: gridSize) { _, _ in
                    itemFrames = [:]
                    updateGridColumnCount(width: geometry.size.width)
                }
                .onChange(of: store.filteredPhotosVersion) { _, _ in
                    itemFrames = [:]
                    cachedPhotoIds = Set(store.filteredPhotos.map(\.id))
                }
            }
            .onChange(of: store.selectedPhoto?.id) { _, newId in
                guard dragStart == nil else { return }
                if let newId = newId {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
            .task(id: store.viewMode) {
                guard store.viewMode == .grid, let selectedId = store.selectedPhoto?.id else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(selectedId, anchor: .center)
            }
        }
    }

    private func photoCard(_ photo: PhotoEntry) -> some View {
        SelectablePhotoCardView(
            photo: photo,
            gridSize: gridSize,
            isSelected: store.selectedPhotos.contains(photo.id),
            isPrimary: store.selectedPhoto?.id == photo.id,
            isSelectMode: isSelectMode
        )
        .environmentObject(store)
        .id(photo.id)
        .onAppear {
            store.preloadThumbnails(around: photo, size: gridSize)
        }
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

    private func makePhotoGroups(granularity: Calendar.Component) -> [PhotoGridSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredPhotos) { photo in
            let components: Set<Calendar.Component> = granularity == .month ? [.year, .month] : [.year, .month, .day]
            return calendar.date(from: calendar.dateComponents(components, from: photo.fileDate)) ?? photo.fileDate
        }

        let ascending = store.filterOptions.sortAscending
        return grouped.keys.sorted(by: ascending ? (<) : (>)).map { date in
            let photos = (grouped[date] ?? []).sorted {
                ascending ? $0.fileDate < $1.fileDate : $0.fileDate > $1.fileDate
            }
            let title = groupTitle(for: date, granularity: granularity)
            let subtitle = groupSubtitle(for: date, photos: photos, granularity: granularity)
            return PhotoGridSection(
                id: "\(granularity)-\(date.timeIntervalSince1970)",
                title: title,
                subtitle: subtitle,
                photos: photos
            )
        }
    }

    private func groupTitle(for date: Date, granularity: Calendar.Component) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = granularity == .month ? "yyyy年M月" : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func groupSubtitle(for date: Date, photos: [PhotoEntry], granularity: Calendar.Component) -> String {
        guard granularity == .day else { return "\(photos.count) 张" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: date)) · \(photos.count) 张"
    }

    private func isGroupSelected(_ group: PhotoGridSection) -> Bool {
        let ids = Set(group.photos.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: store.selectedPhotos)
    }

    private func toggleGroupSelection(_ group: PhotoGridSection) {
        let ids = Set(group.photos.map(\.id))
        guard !ids.isEmpty else { return }

        if ids.isSubset(of: store.selectedPhotos) {
            store.selectPhotoIds(store.selectedPhotos.subtracting(ids))
        } else {
            store.selectPhotoIds(store.selectedPhotos.union(ids))
        }

        activateSelectModeIfNeeded()
        if let selected = store.selectedPhoto {
            lastSelectedPhoto = selected
        }
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(gridCoordinateSpace))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    dragBaselineSelection = store.selectedPhotos
                    dragSelectionMode = currentDragSelectionMode
                    lastDragUpdateTime = 0
                }
                dragCurrent = value.location
                updateDragSelection()
            }
            .onEnded { _ in
                updateDragSelection()
                dragStart = nil
                dragCurrent = nil
                dragBaselineSelection = []
                dragSelectionMode = .replace
            }
    }

    private var currentDragSelectionMode: DragSelectionMode {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            return .toggle
        }
        if flags.contains(.shift) {
            return .add
        }
        return .replace
    }

    private func updateDragSelection() {
        guard let selectionRect else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDragUpdateTime >= 0.016 else { return }
        lastDragUpdateTime = now

        let rectSelectedIds = itemFrames.reduce(into: Set<String>()) { result, item in
            guard cachedPhotoIds.contains(item.key) else { return }
            if item.value.intersects(selectionRect) {
                result.insert(item.key)
            }
        }

        let selectedIds: Set<String>
        switch dragSelectionMode {
        case .replace:
            selectedIds = rectSelectedIds
        case .add:
            selectedIds = dragBaselineSelection.union(rectSelectedIds)
        case .toggle:
            selectedIds = dragBaselineSelection.symmetricDifference(rectSelectedIds)
        }

        store.selectPhotoIds(selectedIds)
        activateSelectModeIfNeeded()
        if let selected = store.selectedPhoto {
            lastSelectedPhoto = selected
        }
    }

    private func updateGridColumnCount(width: CGFloat) {
        // 必须与 .adaptive 网格实际排布的列数一致，否则上/下键跨行跳转会错位。
        // 可用宽度 = 总宽 - ScrollView 水平内边距(14×2) - LazyVGrid 内边距(4×2)
        let horizontalInset: CGFloat = 14 * 2 + 4 * 2
        let columnSpacing: CGFloat = 4
        let available = max(0, width - horizontalInset)
        let count = max(1, Int((available + columnSpacing) / (gridSize + columnSpacing)))
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
                activateSelectModeIfNeeded()
            } else if isCommandPressed {
                store.toggleSelection(photo)
                lastSelectedPhoto = photo
                activateSelectModeIfNeeded()
            } else {
                store.selectPhoto(photo)
                lastSelectedPhoto = photo
            }
        }
    }

    private func activateSelectModeIfNeeded() {
        guard !store.isSelectMode, store.selectedCount > 1 else { return }
        store.enterSelectMode()
    }
}

private enum DragSelectionMode {
    case replace
    case add
    case toggle
}

struct PhotoItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
