import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var detailVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            FilterSidebar()
                .navigationSplitViewColumnWidth(260)
        } content: {
            mainContent
        } detail: {
            if store.selectedPhoto != nil {
                PhotoDetailView(showsPreview: store.viewMode == .grid)
                    .navigationSplitViewColumnWidth(store.viewMode == .single ? 460 : 420)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                if store.viewMode == .single {
                                    store.viewMode = .grid
                                } else {
                                    detailVisibility = .detailOnly
                                    store.selectedPhoto = nil
                                }
                            } label: {
                                Label(
                                    store.viewMode == .single ? "返回网格" : "隐藏详情",
                                    systemImage: store.viewMode == .single ? "square.grid.2x2" : "sidebar.right"
                                )
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
                    Label("打开文件夹", systemImage: "folder.badge.plus")
                }
                .tint(.accentColor)

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
        .sheet(isPresented: $store.showingShortcutGuide) {
            ShortcutGuideView()
        }
        .sheet(isPresented: $store.showingAICullReview) {
            AICullReviewView(
                cullService: store.aiCullService,
                photos: store.filteredPhotos.isEmpty ? store.photos : store.filteredPhotos,
                onApply: { marked in store.applyAICullResults(markedPhotos: marked) },
                onCancel: { store.cancelAICull() }
            )
        }
        .task {
            store.detectVolumes()
            await store.loadPhotos()
        }
        .onChange(of: store.selectedPhoto) { _, newValue in
            if newValue != nil {
                detailVisibility = .automatic
            }
        }
        .onChange(of: store.isSidebarVisible) { _, isVisible in
            sidebarVisibility = isVisible ? .all : .doubleColumn
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.isLoading {
            VStack(spacing: 16) {
                ProgressView(value: store.loadingProgress)
                    .frame(width: 220)
                Text(store.loadingStatus.isEmpty ? "正在加载照片..." : store.loadingStatus)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.sourcePath.isEmpty || store.errorMessage != nil {
            WelcomeView()
        } else if store.photos.isEmpty {
            WelcomeView()
        } else if store.viewMode == .single, let photo = store.selectedPhoto {
            PhotoSinglePreviewView(photo: photo)
        } else {
            VStack(spacing: 0) {
                // AI 筛选内嵌面板
                AICullPanelView(cullService: store.aiCullService)
                    .environmentObject(store)

                PhotoGridView()
            }
        }
    }
}
