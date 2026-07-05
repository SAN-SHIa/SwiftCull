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
                    dateFilterSection
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

    private var dateFilterSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(icon: "calendar", title: "日期范围")
                    Spacer()
                    Toggle("", isOn: $store.filterOptions.dateFilterEnabled)
                        .labelsHidden()
                        .controlSize(.mini)
                        .onChange(of: store.filterOptions.dateFilterEnabled) { _, enabled in
                            if enabled {
                                applyPreset(.today)
                            } else {
                                store.filterOptions.startDate = nil
                                store.filterOptions.endDate = nil
                                store.filterOptions.activePreset = nil
                            }
                            scheduleFilter()
                        }
                }

                if store.filterOptions.dateFilterEnabled {
                    // 快捷预设按钮
                    presetButtons

                    // 日期输入区
                    dateInputRow

                    // 最近使用
                    if !recentDateRanges.isEmpty {
                        recentSection
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: store.filterOptions.dateFilterEnabled)
    }

    // MARK: - 快捷预设

    private var presetButtons: some View {
        FlowLayout(spacing: 6) {
            ForEach([DatePreset.today, .yesterday, .last7Days, .last30Days, .custom], id: \.self) { preset in
                Button {
                    applyPreset(preset)
                    scheduleFilter()
                } label: {
                    Text(preset.displayName)
                        .font(.system(size: 11, weight: store.filterOptions.activePreset == preset ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(store.filterOptions.activePreset == preset
                                           ? Color.accentColor.opacity(0.15)
                                           : Color.clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                store.filterOptions.activePreset == preset
                                ? Color.accentColor.opacity(0.4)
                                : Color.secondary.opacity(0.2),
                                lineWidth: 0.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 日期输入

    private var dateInputRow: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("开始")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                DatePickerTextField(
                    date: Binding(
                        get: { store.filterOptions.startDate ?? Calendar.current.startOfDay(for: Date()) },
                        set: { newDate in
                            store.filterOptions.startDate = newDate
                            // 自动联动：结束日期不能早于开始日期
                            if let end = store.filterOptions.endDate, end < newDate {
                                store.filterOptions.endDate = newDate
                            }
                            store.filterOptions.activePreset = .custom
                            saveRecentRange()
                            scheduleFilter()
                        }
                    )
                )
            }

            Text("至")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("结束")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                DatePickerTextField(
                    date: Binding(
                        get: { store.filterOptions.endDate ?? Date() },
                        set: { newDate in
                            store.filterOptions.endDate = newDate
                            // 自动联动：开始日期不能晚于结束日期
                            if let start = store.filterOptions.startDate, start > newDate {
                                store.filterOptions.startDate = newDate
                            }
                            store.filterOptions.activePreset = .custom
                            saveRecentRange()
                            scheduleFilter()
                        }
                    )
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 最近使用

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近使用")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                ForEach(recentDateRanges.prefix(3), id: \.self) { range in
                    Button {
                        store.filterOptions.startDate = range.start
                        store.filterOptions.endDate = range.end
                        store.filterOptions.activePreset = .custom
                        scheduleFilter()
                    } label: {
                        Text(range.label)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func applyPreset(_ preset: DatePreset) {
        store.filterOptions.activePreset = preset
        if let range = preset.dateRange {
            store.filterOptions.startDate = range.start
            store.filterOptions.endDate = range.end
        }
        saveRecentRange()
    }

    // MARK: - 最近使用记录

    private struct RecentDateRange: Codable, Hashable, Sendable {
        let start: Date
        let end: Date

        var label: String {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return "\(f.string(from: start))-\(f.string(from: end))"
        }
    }

    @AppStorage("recentDateRanges") private var recentDateRangesData: Data = Data()

    private var recentDateRanges: [RecentDateRange] {
        get {
            guard let decoded = try? JSONDecoder().decode([RecentDateRange].self, from: recentDateRangesData) else { return [] }
            return decoded
        }
    }

    private func saveRecentRange() {
        guard let start = store.filterOptions.startDate, let end = store.filterOptions.endDate else { return }
        let new = RecentDateRange(start: start, end: end)
        var recent = recentDateRanges.filter { $0 != new }
        recent.insert(new, at: 0)
        if recent.count > 5 { recent = Array(recent.prefix(5)) }
        recentDateRangesData = (try? JSONEncoder().encode(recent)) ?? Data()
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
                        VStack(spacing: 5) {
                            HStack(spacing: 6) {
                                if store.isExporting {
                                    Text("导出中 \(Int(store.exportProgress * 100))%")
                                        .font(.system(size: 13, weight: .medium))
                                        .monospacedDigit()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("导出筛选结果")
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }

                            if store.isExporting {
                                ProgressView(value: store.exportProgress)
                                    .progressViewStyle(.linear)
                                    .tint(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isExporting || store.photoCount == 0)
                    .animation(.smooth(duration: 0.2), value: store.isExporting)
                }
            }
        }
    }
}

// MARK: - 日期文本输入框（可编辑 + 日历弹窗）

private struct DatePickerTextField: View {
    @Binding var date: Date
    @State private var text: String = ""
    @State private var isValid: Bool = true
    @State private var showCalendar: Bool = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private static let inputFormatters: [DateFormatter] = {
        let patterns = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy/M/d", "yyyy-MM-d", "yyyy/M/dd"]
        return patterns.map { p in
            let f = DateFormatter()
            f.dateFormat = p
            f.isLenient = true
            return f
        }
    }()

    var body: some View {
        HStack(spacing: 2) {
            TextField("YYYY/MM/DD", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90)
                .foregroundStyle(isValid ? Color.primary : Color.red)
                .onChange(of: text) { _, newValue in
                    parseAndApply(newValue)
                }

            Button {
                showCalendar.toggle()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showCalendar) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 260)
                    .padding(8)
                    .onChange(of: date) { _, _ in
                        text = Self.displayFormatter.string(from: date)
                        showCalendar = false
                    }
            }
        }
        .onAppear {
            text = Self.displayFormatter.string(from: date)
        }
        .onChange(of: date) { _, newDate in
            let newText = Self.displayFormatter.string(from: newDate)
            if newText != text { text = newText }
        }
    }

    private func parseAndApply(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { isValid = false; return }
        for formatter in Self.inputFormatters {
            if let parsed = formatter.date(from: trimmed) {
                isValid = true
                date = parsed
                return
            }
        }
        isValid = false
    }
}
