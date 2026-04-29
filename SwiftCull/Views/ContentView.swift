import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var detailVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            FilterSidebar()
                .navigationSplitViewColumnWidth(250)
        } content: {
            mainContent
        } detail: {
            if store.selectedPhoto != nil && detailVisibility != .detailOnly || store.selectedPhoto != nil {
                PhotoDetailView()
                    .navigationSplitViewColumnWidth(420)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                detailVisibility = .detailOnly
                                store.selectedPhoto = nil
                            } label: {
                                Label("隐藏详情", systemImage: "sidebar.right")
                            }
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("选择一张照片查看详情")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.selectPath()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }

                Button {
                    Task { await store.loadPhotos() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                if store.selectedPhoto != nil {
                    Button {
                        if detailVisibility == .detailOnly {
                            detailVisibility = .automatic
                        } else {
                            detailVisibility = .detailOnly
                            store.selectedPhoto = nil
                        }
                    } label: {
                        Label(
                            detailVisibility == .detailOnly ? "显示详情" : "隐藏详情",
                            systemImage: "sidebar.right"
                        )
                    }
                }

                ToolbarInfoView()
            }
        }
        .alert("确认删除", isPresented: $store.showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                store.photosToDelete = []
            }
            Button("移至废纸篓", role: .destructive) {
                store.confirmDelete()
            }
        } message: {
            if store.photosToDelete.count == 1 {
                Text("将此照片（所有格式文件）移至废纸篓？此操作可通过废纸篓恢复。")
            } else {
                Text("将 \(store.photosToDelete.count) 张照片（所有格式文件）移至废纸篓？此操作可通过废纸篓恢复。")
            }
        }
        .task {
            await store.loadPhotos()
        }
        .onChange(of: store.selectedPhoto) { _, newValue in
            if newValue != nil {
                detailVisibility = .automatic
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("正在加载照片...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.errorMessage != nil {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(store.errorMessage!)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("选择文件夹") {
                    store.selectPath()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.photos.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("未找到照片")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("请选择包含照片的文件夹")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Button("选择文件夹") {
                    store.selectPath()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PhotoGridView()
        }
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
