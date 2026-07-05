import Foundation
import SwiftUI
import Combine

struct DetectedVolume: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
}

enum PhotoViewMode: Sendable {
    case grid
    case single
}

@MainActor
class PhotoStore: ObservableObject {
    @Published var photos: [PhotoEntry] = []
    @Published var filteredPhotos: [PhotoEntry] = []
    /// 每当 filteredPhotos 的成员或顺序变化时自增，供视图做轻量 onChange 触发（避免全量 map(\.id)）
    @Published private(set) var filteredPhotosVersion = 0
    @Published var selectedPhoto: PhotoEntry?
    @Published var selectedPhotos: Set<String> = []
    @Published var filterOptions = FilterOptions()
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var loadingStatus: String = ""
    @Published var sourcePath: String = ""
    @Published var errorMessage: String?
    @Published var showingDeleteConfirmation = false
    @Published var photosToDelete: [PhotoEntry] = []
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportMessage: String?
    @Published var viewMode: PhotoViewMode = .grid
    @Published var isSidebarVisible = true
    @Published var showingShortcutGuide = false
    @Published var isSelectMode = false
    @Published var detectedVolumes: [DetectedVolume] = []

    private let fileService = FileService.shared
    private let tagService = TagService.shared
    private let ratingService = RatingService.shared
    private let thumbnailService = ThumbnailService.shared
    let finderTagService = FinderTagService.shared
    private let projectMetadata = ProjectMetadataService.shared
    private var sidecarEntries: [String: PhotoMetadata] = [:]

    /// 选择模式下被编辑过的照片在编辑前的原始状态（用于「取消」纯内存回滚，零磁盘 IO）
    private struct OriginalPhotoState {
        let rating: Int
        let tags: [String]
    }
    private var editedOriginals: [String: OriginalPhotoState] = [:]

    private var gridColumnCount = 1
    private var currentLoadID = UUID()
    private var lastPreheatKey: String?
    private var tagColorLookup: [String: Int] {
        finderTagService.tagColorLookup
    }

    init() {}

    private func buildPhotoIndexMap() -> [String: Int] {
        var map: [String: Int] = [:]
        map.reserveCapacity(photos.count)
        for index in photos.indices {
            map[photos[index].id] = index
        }
        return map
    }

    private func buildFilteredIndexMap() -> [String: Int] {
        var map: [String: Int] = [:]
        map.reserveCapacity(filteredPhotos.count)
        for index in filteredPhotos.indices {
            map[filteredPhotos[index].id] = index
        }
        return map
    }

    var photoCount: Int { filteredPhotos.count }
    var totalPhotoCount: Int { photos.count }

    var totalSize: String {
        let total = filteredPhotos.reduce(Int64(0)) { $0 + $1.totalFileSize }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var selectedPhotoEntries: [PhotoEntry] {
        guard !selectedPhotos.isEmpty else { return [] }
        return filteredPhotos.filter { selectedPhotos.contains($0.id) }
    }

    var selectedCount: Int { selectedPhotos.count }

    var availableTags: [FinderTag] {
        finderTagService.availableTags
    }

    func loadPhotos() async {
        let loadID = UUID()
        currentLoadID = loadID
        lastPreheatKey = nil
        thumbnailService.cancelPending()
        thumbnailService.clearInMemoryCache()
        thumbnailService.cleanupDiskCache()
        isLoading = true
        loadingProgress = 0
        loadingStatus = "准备读取文件夹..."
        errorMessage = nil
        selectedPhoto = nil
        selectedPhotos = []
        photosToDelete = []
        showingDeleteConfirmation = false
        isSelectMode = false
        editedOriginals = [:]
        viewMode = .grid

        if sourcePath.isEmpty {
            photos = []
            filteredPhotos = []
            filteredPhotosVersion &+= 1
            isLoading = false
            loadingProgress = 0
            loadingStatus = ""
            return
        }

        loadingStatus = "正在扫描照片文件..."
        loadingProgress = 0.08

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDir) || !isDir.boolValue {
            errorMessage = "路径不存在或不是文件夹: \(sourcePath)"
            isLoading = false
            loadingProgress = 0
            loadingStatus = ""
            return
        }

        let loaded = await fileService.scanDirectory(at: sourcePath)
        guard currentLoadID == loadID else {
            isLoading = false
            return
        }

        var enriched: [PhotoEntry] = []
        enriched.reserveCapacity(loaded.count)

        if loaded.isEmpty {
            loadingStatus = "未找到可识别的照片"
            loadingProgress = 1
        } else {
            loadingStatus = "正在读取评分与 Finder 标签..."
            loadingProgress = 0.2

            let chunkSize = 200
            let chunkCount = (loaded.count + chunkSize - 1) / chunkSize
            var chunkResults = Array<[PhotoEntry]?>(repeating: nil, count: chunkCount)
            var completedCount = 0

            await withTaskGroup(of: (Int, [PhotoEntry]).self) { group in
                for chunkIndex in 0..<chunkCount {
                    let startIndex = chunkIndex * chunkSize
                    let endIndex = min(startIndex + chunkSize, loaded.count)
                    let chunk = Array(loaded[startIndex..<endIndex])

                    group.addTask(priority: .userInitiated) {
                        let ratingService = RatingService.shared
                        let tagService = TagService.shared
                        let partial = chunk.map { entry -> PhotoEntry in
                            var photo = entry
                            photo.rating = ratingService.getRating(for: photo.id)
                            photo.tags = tagService.getTagsForPhotoPair(photo)
                            return photo
                        }
                        return (chunkIndex, partial)
                    }
                }

                for await (chunkIndex, partial) in group {
                    guard currentLoadID == loadID else { break }
                    chunkResults[chunkIndex] = partial
                    completedCount += 1
                    loadingProgress = 0.2 + 0.65 * (Double(completedCount) / Double(chunkCount))
                    loadingStatus = "正在读取评分与 Finder 标签 \(min(completedCount * chunkSize, loaded.count))/\(loaded.count)"
                }
            }

            // If load was cancelled during task group, exit early
            guard currentLoadID == loadID else {
                isLoading = false
                return
            }

            for chunk in chunkResults {
                if let chunk { enriched.append(contentsOf: chunk) }
            }
        }

        loadingStatus = "正在加载项目标注..."
        loadingProgress = 0.88

        // 加载 sidecar 标注（星级）
        sidecarEntries = projectMetadata.load(from: sourcePath)
        if !sidecarEntries.isEmpty {
            for i in enriched.indices {
                let id = enriched[i].id
                if let meta = sidecarEntries[id] {
                    if let r = meta.rating, r > 0 {
                        enriched[i].rating = r
                    }
                }
            }
        }

        loadingStatus = "正在整理排序..."
        loadingProgress = 0.9
        photos = enriched
        applyFilters()
        loadingProgress = 1
        loadingStatus = "加载完成"
        isLoading = false
    }

    // MARK: - Sidecar 标注同步

    /// 将当前 photos 中有标注的条目写入 sidecar
    private func syncSidecar() {
        guard !sourcePath.isEmpty else { return }
        var entries: [String: PhotoMetadata] = [:]
        for photo in photos {
            if photo.rating > 0 {
                entries[photo.id] = PhotoMetadata(rating: photo.rating)
            }
        }
        sidecarEntries = entries
        projectMetadata.scheduleSave(entries: entries, folderPath: sourcePath)
    }

    func preloadThumbnails(around photo: PhotoEntry, size: CGFloat) {
        guard let centerIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) else { return }
        let quantizedSize = Int(size.rounded())
        let key = "\(photo.id)|\(quantizedSize)|\(gridColumnCount)"
        guard key != lastPreheatKey else { return }
        lastPreheatKey = key

        let before = gridColumnCount * 2
        let after = gridColumnCount * 4
        let lowerBound = max(0, centerIndex - before)
        let upperBound = min(filteredPhotos.count, centerIndex + after + 1)

        let items = filteredPhotos[lowerBound..<upperBound].map { photo in
            (id: "\(photo.primaryFilePath)|\(quantizedSize)", path: photo.primaryFilePath)
        }
        thumbnailService.preloadThumbnails(paths: items, size: size)
    }

    func applyFilters() {
        let trimmedQuery = filterOptions.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedQuery.isEmpty ? nil : trimmedQuery.lowercased()
        let ratingFilter = filterOptions.ratingFilter
        let fileTypeFilter = filterOptions.fileTypeFilter
        let tagFilter = filterOptions.tagFilter

        var result = [PhotoEntry]()
        result.reserveCapacity(photos.count)

        for photo in photos {
            if photo.isDeleted { continue }

            if let query, !photo.baseName.lowercased().contains(query) { continue }

            switch ratingFilter {
            case .all: break
            case .unrated: if photo.rating != 0 { continue }
            default: if photo.rating != ratingFilter.rawValue { continue }
            }

            switch fileTypeFilter {
            case .all: break
            case .jpgOnly: if !(photo.hasJpg && !photo.hasNef && !photo.hasMov) { continue }
            case .nefOnly: if !(photo.hasNef && !photo.hasJpg && !photo.hasMov) { continue }
            case .jpgAndNef: if !(photo.hasJpg && photo.hasNef) { continue }
            case .movOnly: if !photo.isVideoOnly { continue }
            case .hasMov: if !photo.hasMov { continue }
            }

            if let tagFilter, !photo.tags.contains(tagFilter) { continue }

            // 日期范围过滤（仅开启时生效）
            if filterOptions.dateFilterEnabled {
                if let start = filterOptions.startDate, photo.fileDate < start { continue }
                if let end = filterOptions.endDate, photo.fileDate > end { continue }
            }

            result.append(photo)
        }

        filteredPhotos = sortPhotos(result)
        filteredPhotosVersion &+= 1
    }

    private func sortPhotos(_ photos: [PhotoEntry]) -> [PhotoEntry] {
        let sorted: [PhotoEntry]
        switch filterOptions.sortOption {
        case .name:
            sorted = photos.sorted { $0.baseName < $1.baseName }
        case .date:
            sorted = photos.sorted { $0.fileDate < $1.fileDate }
        case .rating:
            sorted = photos.sorted { $0.rating > $1.rating }
        case .size:
            sorted = photos.sorted { $0.totalFileSize > $1.totalFileSize }
        }
        return filterOptions.sortAscending ? sorted : sorted.reversed()
    }

    func setRating(_ rating: Int, for photo: PhotoEntry) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        ratingService.setRating(rating, for: photo.id)
        photos[index].rating = rating
        if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
            filteredPhotos[filteredIndex].rating = rating
        }
        if selectedPhoto?.id == photo.id {
            selectedPhoto?.rating = rating
        }
        syncSidecar()
    }

    func clearTags(for photo: PhotoEntry) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        _ = tagService.setTagsForPhotoPair([], photo: photos[index])
        photos[index].tags = []
        if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
            filteredPhotos[filteredIndex].tags = []
        }
        if selectedPhoto?.id == photo.id {
            selectedPhoto?.tags = []
        }
    }

    func toggleSinglePreview() {
        if viewMode == .single {
            viewMode = .grid
            return
        }
        if selectedPhoto == nil, let first = filteredPhotos.first {
            selectPhoto(first)
        }
        if selectedPhoto != nil {
            viewMode = .single
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    // MARK: - 批量操作（选择模式下仅改内存，落盘延迟到「完成」）

    /// 记录一张照片在本次选择会话中首次被编辑前的原始状态
    private func captureOriginalIfNeeded(_ id: String, index: Int) {
        guard editedOriginals[id] == nil else { return }
        editedOriginals[id] = OriginalPhotoState(rating: photos[index].rating, tags: photos[index].tags)
    }

    func batchSetRating(_ rating: Int) {
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }
        let photoMap = buildPhotoIndexMap()
        let filteredMap = buildFilteredIndexMap()

        for id in ids {
            if let index = photoMap[id] {
                captureOriginalIfNeeded(id, index: index)
                photos[index].rating = rating
            }
            if let filteredIndex = filteredMap[id] {
                filteredPhotos[filteredIndex].rating = rating
            }
        }
        if let selected = selectedPhoto, ids.contains(selected.id) {
            selectedPhoto?.rating = rating
        }
    }

    func batchClearRating() {
        batchSetRating(0)
    }

    func batchAddTag(_ tag: String) {
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }
        let photoMap = buildPhotoIndexMap()
        let filteredMap = buildFilteredIndexMap()

        for id in ids {
            if let index = photoMap[id] {
                captureOriginalIfNeeded(id, index: index)
                if !photos[index].tags.contains(tag) {
                    photos[index].tags.append(tag)
                }
            }
            if let filteredIndex = filteredMap[id], !filteredPhotos[filteredIndex].tags.contains(tag) {
                filteredPhotos[filteredIndex].tags.append(tag)
            }
        }
        if let selected = selectedPhoto, ids.contains(selected.id),
           !(selectedPhoto?.tags.contains(tag) ?? true) {
            selectedPhoto?.tags.append(tag)
        }
    }

    func batchClearTags() {
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }
        let photoMap = buildPhotoIndexMap()
        let filteredMap = buildFilteredIndexMap()

        for id in ids {
            if let index = photoMap[id] {
                captureOriginalIfNeeded(id, index: index)
                photos[index].tags = []
            }
            if let filteredIndex = filteredMap[id] {
                filteredPhotos[filteredIndex].tags = []
            }
        }
        if let selected = selectedPhoto, ids.contains(selected.id) {
            selectedPhoto?.tags = []
        }
    }

    func addTag(_ tag: String, to photo: PhotoEntry) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        var currentTags = photos[index].tags
        if !currentTags.contains(tag) {
            currentTags.append(tag)
            _ = tagService.setTagsForPhotoPair(currentTags, photo: photos[index], colorLookup: tagColorLookup)
            photos[index].tags = currentTags
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
                filteredPhotos[filteredIndex].tags = currentTags
            }
            if selectedPhoto?.id == photo.id {
                selectedPhoto?.tags = currentTags
            }
        }
    }

    func removeTag(_ tag: String, from photo: PhotoEntry) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        var currentTags = photos[index].tags
        currentTags.removeAll { $0 == tag }
        _ = tagService.setTagsForPhotoPair(currentTags, photo: photos[index], colorLookup: tagColorLookup)
        photos[index].tags = currentTags
        if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
            filteredPhotos[filteredIndex].tags = currentTags
        }
        if selectedPhoto?.id == photo.id {
            selectedPhoto?.tags = currentTags
        }
    }

    // MARK: - 选择模式

    func enterSelectMode() {
        editedOriginals = [:]
        isSelectMode = true
    }

    /// 取消：纯内存回滚被编辑过的照片，零磁盘 IO
    func cancelSelectMode() {
        if !editedOriginals.isEmpty {
            let photoMap = buildPhotoIndexMap()
            let filteredMap = buildFilteredIndexMap()
            for (id, original) in editedOriginals {
                if let index = photoMap[id] {
                    photos[index].rating = original.rating
                    photos[index].tags = original.tags
                }
                if let filteredIndex = filteredMap[id] {
                    filteredPhotos[filteredIndex].rating = original.rating
                    filteredPhotos[filteredIndex].tags = original.tags
                }
            }
        }
        editedOriginals = [:]
        selectedPhotos = []
        selectedPhoto = nil
        isSelectMode = false
    }

    /// 完成：把本次会话的改动一次性落盘（标签写盘在后台线程）
    func confirmSelectMode() {
        persistSelectModeEdits()
        editedOriginals = [:]
        selectedPhotos = []
        selectedPhoto = nil
        isSelectMode = false
    }

    private func persistSelectModeEdits() {
        guard !editedOriginals.isEmpty, !sourcePath.isEmpty else { return }
        let photoMap = buildPhotoIndexMap()

        struct PendingWrite: Sendable {
            let photo: PhotoEntry
            let ratingChanged: Bool
            let tagsChanged: Bool
        }
        var pending: [PendingWrite] = []
        var ratingChangedAtAll = false

        for (id, original) in editedOriginals {
            guard let index = photoMap[id] else { continue }
            let current = photos[index]
            let ratingChanged = current.rating != original.rating
            let tagsChanged = current.tags != original.tags
            guard ratingChanged || tagsChanged else { continue }
            if ratingChanged { ratingChangedAtAll = true }
            pending.append(PendingWrite(photo: current, ratingChanged: ratingChanged, tagsChanged: tagsChanged))
        }

        guard !pending.isEmpty else { return }

        // 评分落盘（UserDefaults，很快）；标签写扩展属性（较慢）放后台
        let colorLookup = tagColorLookup
        Task.detached(priority: .utility) {
            let ratingService = RatingService.shared
            let tagService = TagService.shared
            for write in pending {
                if write.ratingChanged {
                    ratingService.setRating(write.photo.rating, for: write.photo.id)
                }
                if write.tagsChanged {
                    _ = tagService.setTagsForPhotoPair(write.photo.tags, photo: write.photo, colorLookup: colorLookup)
                }
            }
        }

        if ratingChangedAtAll {
            syncSidecar()
        }
    }

    func selectPhoto(_ photo: PhotoEntry?) {
        selectedPhoto = photo
        if let photo = photo {
            selectedPhotos = [photo.id]
        } else {
            selectedPhotos = []
        }
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    func toggleSelection(_ photo: PhotoEntry) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
            if selectedPhoto?.id == photo.id {
                selectedPhoto = selectedPhotos.isEmpty ? nil :
                    filteredPhotos.first { selectedPhotos.contains($0.id) }
            }
        } else {
            selectedPhotos.insert(photo.id)
            selectedPhoto = photo
        }
    }

    func selectRange(from start: PhotoEntry, to end: PhotoEntry) {
        guard let startIndex = filteredPhotos.firstIndex(where: { $0.id == start.id }),
              let endIndex = filteredPhotos.firstIndex(where: { $0.id == end.id }) else { return }

        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        for i in range {
            selectedPhotos.insert(filteredPhotos[i].id)
        }
        selectedPhoto = end
    }

    func selectAll() {
        if !isSelectMode {
            enterSelectMode()
        }
        selectedPhotos = Set(filteredPhotos.map { $0.id })
        if let first = filteredPhotos.first {
            selectedPhoto = first
        }
    }

    func selectPhotoIds(_ ids: Set<String>) {
        selectedPhotos = ids
        selectedPhoto = filteredPhotos.first { ids.contains($0.id) }
    }

    func updateGridColumnCount(_ count: Int) {
        gridColumnCount = max(1, count)
    }

    func navigateToPrevious() {
        navigate(offset: -1)
    }

    func navigateToNext() {
        navigate(offset: 1)
    }

    func navigateUp() { navigate(offset: -gridColumnCount) }
    func navigateDown() { navigate(offset: gridColumnCount) }
    func navigateLeft() { navigateToPrevious() }
    func navigateRight() { navigateToNext() }

    private func navigate(offset: Int) {
        guard !filteredPhotos.isEmpty else { return }
        let currentIndex: Int
        if let current = selectedPhoto,
           let index = filteredPhotos.firstIndex(where: { $0.id == current.id }) {
            currentIndex = index
        } else {
            currentIndex = offset >= 0 ? -1 : filteredPhotos.count
        }

        let nextIndex = min(max(currentIndex + offset, 0), filteredPhotos.count - 1)
        let next = filteredPhotos[nextIndex]
        selectedPhoto = next
        selectedPhotos = [next.id]
    }

    func requestDelete(_ photo: PhotoEntry) {
        photosToDelete = [photo]
        showingDeleteConfirmation = true
    }

    func requestDeleteSelected() {
        let entries = selectedPhotoEntries.isEmpty ? selectedPhoto.map { [$0] } ?? [] : selectedPhotoEntries
        guard !entries.isEmpty else { return }
        photosToDelete = entries
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        let deleteRequest = photosToDelete
        let requestedDeleteIds = Set(deleteRequest.map(\.id))
        let previousFilteredPhotos = filteredPhotos
        let selectionAnchorIndex = deletionSelectionAnchorIndex(
            deleteIds: requestedDeleteIds,
            in: previousFilteredPhotos
        )

        // Build lookup dict for O(1) index access
        var photoIndexByID: [String: Int] = [:]
        for index in photos.indices {
            photoIndexByID[photos[index].id] = index
        }

        // Mark as deleted immediately for instant UI update
        var deletedIds: Set<String> = []
        for photo in deleteRequest {
            if let index = photoIndexByID[photo.id] {
                photos[index].isDeleted = true
                deletedIds.insert(photo.id)
            }
        }

        photosToDelete = []
        showingDeleteConfirmation = false

        guard !deletedIds.isEmpty else { return }

        applyFilters()
        selectPhotoAfterDeletion(anchorIndex: selectionAnchorIndex)

        // Perform actual file I/O on background thread
        let fileServiceRef = self.fileService
        let photosToTrash = deleteRequest.filter { deletedIds.contains($0.id) }
        Task.detached(priority: .utility) {
            for photo in photosToTrash {
                _ = fileServiceRef.movePhotoToTrash(photo)
            }
        }
    }

    private func deletionSelectionAnchorIndex(deleteIds: Set<String>, in photos: [PhotoEntry]) -> Int {
        if let selectedPhoto,
           deleteIds.contains(selectedPhoto.id),
           let selectedIndex = photos.firstIndex(where: { $0.id == selectedPhoto.id }) {
            return selectedIndex
        }

        let deletedIndexes = photos.indices.filter { deleteIds.contains(photos[$0].id) }
        if let firstDeletedIndex = deletedIndexes.min() {
            return firstDeletedIndex
        }

        if let selectedPhoto,
           let selectedIndex = photos.firstIndex(where: { $0.id == selectedPhoto.id }) {
            return selectedIndex
        }

        return 0
    }

    private func selectPhotoAfterDeletion(anchorIndex: Int) {
        guard !filteredPhotos.isEmpty else {
            selectedPhotos = []
            selectedPhoto = nil
            return
        }

        let nextIndex = min(anchorIndex, filteredPhotos.count - 1)
        let nextPhoto = filteredPhotos[nextIndex]
        selectedPhoto = nextPhoto
        selectedPhotos = [nextPhoto.id]
    }

    func detectVolumes() {
        let fm = FileManager.default
        let volumesRoot = "/Volumes"
        guard let volumeNames = try? fm.contentsOfDirectory(atPath: volumesRoot) else {
            detectedVolumes = []
            return
        }

        var results: [DetectedVolume] = []

        let homePath = NSHomeDirectory()
        let homePictures = (homePath as NSString).appendingPathComponent("Pictures")
        if fm.fileExists(atPath: homePictures) {
            results.append(DetectedVolume(name: "图片文件夹", path: homePictures, icon: "photo.on.rectangle"))
        }

        let homeDesktop = (homePath as NSString).appendingPathComponent("Desktop")
        if fm.fileExists(atPath: homeDesktop) {
            results.append(DetectedVolume(name: "桌面", path: homeDesktop, icon: "desktopcomputer"))
        }

        for name in volumeNames {
            let volPath = (volumesRoot as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: volPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let dcimPath = (volPath as NSString).appendingPathComponent("DCIM")
            if fm.fileExists(atPath: dcimPath) {
                let dcimSubDirs = scanDCIMSubdirectories(at: dcimPath, volumeName: name)
                if dcimSubDirs.isEmpty {
                    results.append(DetectedVolume(name: "\(name) — DCIM", path: dcimPath, icon: "sdcard"))
                } else {
                    results.append(contentsOf: dcimSubDirs)
                }
                continue
            }

            let hasMediaFiles = containsMediaFiles(at: volPath)
            if hasMediaFiles {
                results.append(DetectedVolume(name: name, path: volPath, icon: "externaldrive"))
            }
        }

        detectedVolumes = results
    }

    private func scanDCIMSubdirectories(at dcimPath: String, volumeName: String) -> [DetectedVolume] {
        let fm = FileManager.default
        guard let subDirs = try? fm.contentsOfDirectory(atPath: dcimPath) else { return [] }

        var results: [DetectedVolume] = []
        for dirName in subDirs {
            let subPath = (dcimPath as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }
            if containsMediaFiles(at: subPath) {
                results.append(DetectedVolume(name: "\(volumeName) — \(dirName)", path: subPath, icon: "sdcard"))
            }
        }
        return results
    }

    private func containsMediaFiles(at path: String) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return false }
        let mediaExts: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "raw", "mov", "mp4", "heic", "png", "tiff"]
        return contents.contains { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return mediaExts.contains(ext)
        }
    }

    func selectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: sourcePath)

        if panel.runModal() == .OK, let url = panel.url {
            sourcePath = url.path
            Task {
                await loadPhotos()
            }
        }
    }

    func exportFilteredPhotos() {
        guard !filteredPhotos.isEmpty else {
            exportMessage = "没有可导出的照片"
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let defaultFileName = "\(dateStr)-\(filterOptions.exportFileNameSuffix)"

        let panel = NSOpenPanel()
        panel.title = "导出筛选照片"
        panel.prompt = "选择保存位置"
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "将在所选位置创建文件夹「\(defaultFileName)」"

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        let destinationDir = (selectedURL.path as NSString).appendingPathComponent(defaultFileName)
        let photosToExport = filteredPhotos
        let total = photosToExport.count
        isExporting = true
        exportProgress = 0

        // 文件拷贝在后台线程执行，避免阻塞主线程冻结 UI；进度回到主线程更新
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var exported = 0
            var failed = 0

            if !fm.fileExists(atPath: destinationDir) {
                try? fm.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)
            }

            for (index, photo) in photosToExport.enumerated() {
                let paths: [String] = [photo.jpgPath, photo.nefPath, photo.movPath].compactMap { $0 }
                for sourcePath in paths {
                    let fileName = (sourcePath as NSString).lastPathComponent
                    let destPath = (destinationDir as NSString).appendingPathComponent(fileName)
                    do {
                        try fm.copyItem(atPath: sourcePath, toPath: destPath)
                        exported += 1
                    } catch {
                        failed += 1
                    }
                }
                let progress = Double(index + 1) / Double(max(total, 1))
                await MainActor.run { [weak self] in self?.exportProgress = progress }
            }

            let finalExported = exported
            let finalFailed = failed
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isExporting = false
                self.exportProgress = 0
                if finalFailed == 0 {
                    self.exportMessage = "已导出 \(total) 张照片（\(finalExported) 个文件）"
                } else {
                    self.exportMessage = "导出完成：\(total) 张照片，\(finalExported) 个成功，\(finalFailed) 个失败"
                }
            }
        }
    }
}
