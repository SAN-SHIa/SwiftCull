import SwiftUI

struct FilterSidebar: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    searchSection
                    ratingSection
                    tagSection
                    fileTypeSection
                    sortSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            exportSection
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .alert("导出结果", isPresented: .constant(store.exportMessage != nil)) {
            Button("好的") {
                store.exportMessage = nil
            }
        } message: {
            Text(store.exportMessage ?? "")
        }
    }

    private func scheduleFilter() {
        DispatchQueue.main.async {
            store.applyFilters()
        }
    }

    private var searchSection: some View {
        GlassCard {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("搜索文件名...", text: $store.filterOptions.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onChange(of: store.filterOptions.searchText) { _, _ in
                        scheduleFilter()
                    }

                if !store.filterOptions.searchText.isEmpty {
                    Button {
                        store.filterOptions.searchText = ""
                        scheduleFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ratingSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "star", title: "评分")

                FlowLayout(spacing: 6) {
                    FilterChip(
                        title: "全部",
                        icon: "line.3.horizontal.decrease",
                        isSelected: store.filterOptions.ratingFilter == .all
                    ) {
                        store.filterOptions.ratingFilter = .all
                        scheduleFilter()
                    }

                    FilterChip(
                        title: "未评分",
                        icon: "star.slash",
                        isSelected: store.filterOptions.ratingFilter == .unrated
                    ) {
                        store.filterOptions.ratingFilter = .unrated
                        scheduleFilter()
                    }

                    ForEach([RatingFilter.one, .two, .three, .four, .five], id: \.self) { filter in
                        FilterChip(
                            title: filter.displayName,
                            isSelected: store.filterOptions.ratingFilter == filter
                        ) {
                            store.filterOptions.ratingFilter = filter
                            scheduleFilter()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: store.filterOptions.ratingFilter) { _, _ in
            scheduleFilter()
        }
    }

    private var tagSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "tag", title: "标签")

                if store.availableTags.isEmpty {
                    Text("暂无标签")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        TagFilterChip(
                            title: "全部",
                            color: nil,
                            isSelected: store.filterOptions.tagFilter == nil
                        ) {
                            store.filterOptions.tagFilter = nil
                            scheduleFilter()
                        }

                        ForEach(store.availableTags) { tag in
                            TagFilterChip(
                                title: tag.displayName,
                                color: tag.color,
                                isSelected: store.filterOptions.tagFilter == tag.name
                            ) {
                                store.filterOptions.tagFilter = store.filterOptions.tagFilter == tag.name ? nil : tag.name
                                scheduleFilter()
                            }
                        }
                    }
                }
            }
        }
    }

    private var fileTypeSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "doc", title: "文件类型")

                FlowLayout(spacing: 6) {
                    ForEach(FileTypeFilter.allCases) { filter in
                        FilterChip(
                            title: filter.displayName,
                            icon: fileTypeIcon(filter),
                            isSelected: store.filterOptions.fileTypeFilter == filter
                        ) {
                            store.filterOptions.fileTypeFilter = filter
                            scheduleFilter()
                        }
                    }
                }
            }
        }
        .onChange(of: store.filterOptions.fileTypeFilter) { _, _ in
            scheduleFilter()
        }
    }

    private var sortSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "arrow.up.arrow.down", title: "排序")

                HStack(spacing: 6) {
                    ForEach(SortOption.allCases) { option in
                        SortChip(
                            title: option.displayName,
                            icon: sortOptionIcon(option),
                            isSelected: store.filterOptions.sortOption == option
                        ) {
                            store.filterOptions.sortOption = option
                            scheduleFilter()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        store.filterOptions.sortAscending.toggle()
                        scheduleFilter()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.filterOptions.sortAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                            Text(store.filterOptions.sortAscending ? "正序" : "逆序")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(store.filterOptions.sortAscending ? "从小到大 / 从旧到新" : "从大到小 / 从新到旧")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .onChange(of: store.filterOptions.sortOption) { _, _ in
            scheduleFilter()
        }
        .onChange(of: store.filterOptions.sortAscending) { _, _ in
            scheduleFilter()
        }
    }

    private func fileTypeIcon(_ filter: FileTypeFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .jpgOnly: return "photo"
        case .nefOnly: return "camera.raw"
        case .jpgAndNef: return "photo.stack"
        case .movOnly: return "video"
        case .hasMov: return "video.badge.checkmark"
        }
    }

    private func sortOptionIcon(_ option: SortOption) -> String {
        switch option {
        case .date: return "calendar"
        case .name: return "textformat.abc"
        case .rating: return "star"
        case .size: return "arrow.down.doc"
        }
    }

    private var exportSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "square.and.arrow.up", title: "导出")

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(store.photoCount) 张照片")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if store.photoCount > 0 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(store.totalSize)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        store.exportFilteredPhotos()
                    } label: {
                        HStack {
                            if store.isExporting {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            Text(store.isExporting ? "导出中..." : "导出筛选结果")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isExporting || store.photoCount == 0)
                    .opacity(store.isExporting ? 0.6 : 1.0)
                }
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TagFilterChip: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        color ?? .accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? accentColor : (color ?? .secondary))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SortChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
