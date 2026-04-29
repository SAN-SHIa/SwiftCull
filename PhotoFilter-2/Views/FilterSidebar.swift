import SwiftUI

struct FilterSidebar: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("筛选")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchSection
                    ratingSection
                    tagSection
                    fileTypeSection
                    sortSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func scheduleFilter() {
        DispatchQueue.main.async {
            store.applyFilters()
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("搜索", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("文件名...", text: $store.filterOptions.searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: store.filterOptions.searchText) { _, _ in
                    scheduleFilter()
                }
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("评分", systemImage: "star")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("评分", selection: $store.filterOptions.ratingFilter) {
                ForEach(RatingFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: store.filterOptions.ratingFilter) { _, _ in
                scheduleFilter()
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("标签", systemImage: "tag")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    store.filterOptions.tagFilter = nil
                    scheduleFilter()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.filterOptions.tagFilter == nil ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(store.filterOptions.tagFilter == nil ? .blue : .secondary)
                        Text("全部")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                ForEach(store.availableTags) { tag in
                    Button {
                        store.filterOptions.tagFilter = store.filterOptions.tagFilter == tag.name ? nil : tag.name
                        scheduleFilter()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.filterOptions.tagFilter == tag.name ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(store.filterOptions.tagFilter == tag.name ? tag.color : .secondary)
                            Circle()
                                .fill(tag.color)
                                .frame(width: 10, height: 10)
                            Text(tag.displayName)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var fileTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("文件类型", systemImage: "doc")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("文件类型", selection: $store.filterOptions.fileTypeFilter) {
                ForEach(FileTypeFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: store.filterOptions.fileTypeFilter) { _, _ in
                scheduleFilter()
            }
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("排序", systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("排序方式", selection: $store.filterOptions.sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Picker("顺序", selection: $store.filterOptions.sortAscending) {
                    Text("正序").tag(true)
                    Text("逆序").tag(false)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }

            if store.filterOptions.sortAscending {
                Text("↑ 从小到大 / 从旧到新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("↓ 从大到小 / 从新到旧")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: store.filterOptions.sortOption) { _, _ in
            scheduleFilter()
        }
        .onChange(of: store.filterOptions.sortAscending) { _, _ in
            scheduleFilter()
        }
    }
}
