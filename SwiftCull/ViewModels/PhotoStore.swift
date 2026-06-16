import Foundation
import SwiftUI
import Combine

struct PhotoSnapshot: Sendable {
    let photoId: String
    let rating: Int
    let tags: [String]
    let workflowMark: PhotoWorkflowMark
}

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
    @Published var exportMessage: String?
    @Published var viewMode: PhotoViewMode = .grid
    @Published var isSidebarVisible = true
    @Published var showingShortcutGuide = false
    @Published var isSelectMode = false
    @Published var detectedVolumes: [DetectedVolume] = []
    @Published var showingAICullReview = false
    @Published var aiCullService = AICullService()
    let cellState = PhotoCellState()
    private let batchThrottler = BatchThrottler()
    private var cancellables = Set<AnyCancellable>()
    /// 批量同步中，抑制 objectWillChange
    private var suppressPublish = false

    private let fileService = FileService.shared
    private let tagService = TagService.shared
    private let ratingService = RatingService.shared
    private let thumbnailService = ThumbnailService.shared
    let finderTagService = FinderTagService.shared
    private let projectMetadata = ProjectMetadataService.shared
    private var sidecarEntries: [String: PhotoMetadata] = [:]

    private var selectModeSnapshot: [PhotoSnapshot] = []
    private var gridColumnCount = 1
    private var currentLoadID = UUID()
    private var lastPreheatKey: String?
    private var tagColorLookup: [String: Int] {
        finderTagService.tagColorLookup
    }

    init() {}

    /// 同步选中状态到 cellState（必须在每次 selectedPhotos 变更后调用）
    private func syncSelectionToCellState() {
        cellState.setSelection(selectedPhotos)
    }

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
        viewMode = .grid

        if sourcePath.isEmpty {
            photos = []
            filteredPhotos = []
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

        // 加载 sidecar 标注（星级、workflowMark、AI 结果）
        sidecarEntries = projectMetadata.load(from: sourcePath)
        if !sidecarEntries.isEmpty {
            for i in enriched.indices {
                let id = enriched[i].id
                if let meta = sidecarEntries[id] {
                    if let r = meta.rating, r > 0 {
                        enriched[i].rating = r
                    }
                    if let mark = meta.workflowMark, let wm = PhotoWorkflowMark(rawValue: mark) {
                        enriched[i].workflowMark = wm
                    }
                    if let ai = meta.aiResult {
                        enriched[i].aiResult = AIAnalysisResult(
                            verdict: AIAnalysisResult.Verdict(rawValue: ai.verdict) ?? .pass,
                            reason: ai.reason,
                            provider: ai.provider ?? "unknown",
                            model: ai.model ?? "unknown",
                            analyzedAt: ai.analyzedAt ?? Date()
                        )
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
            var meta = PhotoMetadata()
            var hasData = false

            if photo.rating > 0 {
                meta.rating = photo.rating
                hasData = true
            }
            if photo.workflowMark != .none {
                meta.workflowMark = photo.workflowMark.rawValue
                hasData = true
            }
            if let ai = photo.aiResult {
                meta.aiResult = PhotoMetadata.AIMetadata(
                    verdict: ai.verdict.rawValue,
                    reason: ai.reason,
                    provider: ai.provider,
                    model: ai.model,
                    analyzedAt: ai.analyzedAt
                )
                hasData = true
            }

            if hasData {
                entries[photo.id] = meta
            }
        }
        sidecarEntries = entries
        projectMetadata.scheduleSave(entries: entries, folderPath: sourcePath)
    }

        func preloadThumbnails(around photo: PhotoEntry, size: CGFloat) {
        guard !aiCullService.isAnalyzing else { return }
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

            // AI 筛选过滤
            switch filterOptions.aiFilter {
            case .all: break
            case .aiReject:
                if let r = photo.aiResult { if r.verdict != .reject { continue } }
                else { continue }
            case .aiPass:
                if let r = photo.aiResult { if r.verdict != .pass { continue } }
                else { continue }
            case .aiNotAnalyzed:
                if photo.aiResult != nil { continue }
            }

            // 日期范围过滤（仅开启时生效）
            if filterOptions.dateFilterEnabled {
                if let start = filterOptions.startDate, photo.fileDate < start { continue }
                if let end = filterOptions.endDate, photo.fileDate > end { continue }
            }

            result.append(photo)
        }

        filteredPhotos = sortPhotos(result)
        cellState.sync(from: photos)
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

    func clearRating(for photo: PhotoEntry) {
        setRating(0, for: photo)
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

    func toggleSelectedPickMark() {
        toggleActiveMark(.pick)
    }

    func toggleSelectedRejectMark() {
        toggleActiveMark(.reject)
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

    private func markActivePhotos(_ mark: PhotoWorkflowMark) {
        defer { syncSidecar() }
        let ids = activePhotoIds
        guard !ids.isEmpty else { return }

        // 1️⃣ cellState 写入 → Cell 即时刷新（无数组拷贝）
        cellState.batchSetMarks(ids, mark: mark)

        // 2️⃣ 延迟单次同步数组（合并多次操作为一次写入）
        batchThrottler.throttle { [weak self] in
            self?.flushCellStateToArrays()
        }
    }

    private func toggleActiveMark(_ mark: PhotoWorkflowMark) {
        defer { syncSidecar() }
        let ids = activePhotoIds
        guard !ids.isEmpty else { return }
        // 读 cellState 判断是否需要清除
        let allAlreadyMarked = ids.allSatisfy { cellState.getMark($0) == mark }
        markActivePhotos(allAlreadyMarked ? .none : mark)
    }

    func batchSetRating(_ rating: Int) {
        defer { syncSidecar() }
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }

        cellState.batchSetRatings(ids, rating: rating)

        batchThrottler.throttle { [weak self] in
            self?.flushCellStateToArrays()
        }
    }

    /// 将 cellState 中的 mark/rating 一次性写回 photos/filteredPhotos 数组
    private func flushCellStateToArrays() {
        var changed = false
        for i in photos.indices {
            let id = photos[i].id
            let csMark = cellState.getMark(id)
            if photos[i].workflowMark != csMark {
                photos[i].workflowMark = csMark
                changed = true
            }
            let csRating = cellState.getRating(id)
            if photos[i].rating != csRating {
                ratingService.setRating(csRating, for: id)
                photos[i].rating = csRating
                changed = true
            }
        }
        for i in filteredPhotos.indices {
            let id = filteredPhotos[i].id
            let csMark = cellState.getMark(id)
            if filteredPhotos[i].workflowMark != csMark {
                filteredPhotos[i].workflowMark = csMark
                changed = true
            }
            let csRating = cellState.getRating(id)
            if filteredPhotos[i].rating != csRating {
                filteredPhotos[i].rating = csRating
                changed = true
            }
        }
        if changed, let selected = selectedPhoto {
            selectedPhoto?.workflowMark = cellState.getMark(selected.id)
            selectedPhoto?.rating = cellState.getRating(selected.id)
        }
    }

    func batchClearRating() {
        defer { syncSidecar() }
        batchSetRating(0)
    }

    func batchAddTag(_ tag: String) {
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }
        batchThrottler.throttle { [weak self] in
            guard let self else { return }
            let photoMap = self.buildPhotoIndexMap()
            let filteredMap = self.buildFilteredIndexMap()
            self.suppressPublish = true
            for photoId in ids {
                if let index = photoMap[photoId] {
                    var tags = self.photos[index].tags
                    if !tags.contains(tag) {
                        tags.append(tag)
                        _ = self.tagService.setTagsForPhotoPair(tags, photo: self.photos[index], colorLookup: self.tagColorLookup)
                        self.photos[index].tags = tags
                    }
                }
                if let filteredIndex = filteredMap[photoId] {
                    var tags = self.filteredPhotos[filteredIndex].tags
                    if !tags.contains(tag) {
                        tags.append(tag)
                        self.filteredPhotos[filteredIndex].tags = tags
                    }
                }
            }
            if let selected = self.selectedPhoto, ids.contains(selected.id),
               !selected.tags.contains(tag) {
                self.selectedPhoto?.tags.append(tag)
            }
            self.suppressPublish = false
            self.objectWillChange.send()
        }
    }

    func batchClearTags() {
        let ids = selectedPhotos
        guard !ids.isEmpty else { return }
        batchThrottler.throttle { [weak self] in
            guard let self else { return }
            let photoMap = self.buildPhotoIndexMap()
            let filteredMap = self.buildFilteredIndexMap()
            self.suppressPublish = true
            for photoId in ids {
                if let index = photoMap[photoId] {
                    _ = self.tagService.setTagsForPhotoPair([], photo: self.photos[index])
                    self.photos[index].tags = []
                }
                if let filteredIndex = filteredMap[photoId] {
                    self.filteredPhotos[filteredIndex].tags = []
                }
            }
            if let selected = self.selectedPhoto, ids.contains(selected.id) {
                self.selectedPhoto?.tags = []
            }
            self.suppressPublish = false
            self.objectWillChange.send()
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

    func enterSelectMode() {
        selectModeSnapshot = photos.map {
            PhotoSnapshot(photoId: $0.id, rating: $0.rating, tags: $0.tags, workflowMark: $0.workflowMark)
        }
        isSelectMode = true
    }

    func exitSelectMode() {
        if isSelectMode {
            confirmSelectMode()
        }
    }

    func cancelSelectMode() {
        let photoMap = buildPhotoIndexMap()
        let filteredMap = buildFilteredIndexMap()

        for snapshot in selectModeSnapshot {
            if let index = photoMap[snapshot.photoId] {
                ratingService.setRating(snapshot.rating, for: snapshot.photoId)
                photos[index].rating = snapshot.rating
                _ = tagService.setTagsForPhotoPair(snapshot.tags, photo: photos[index], colorLookup: tagColorLookup)
                photos[index].tags = snapshot.tags
                photos[index].workflowMark = snapshot.workflowMark
            }
            if let filteredIndex = filteredMap[snapshot.photoId] {
                filteredPhotos[filteredIndex].rating = snapshot.rating
                filteredPhotos[filteredIndex].tags = snapshot.tags
                filteredPhotos[filteredIndex].workflowMark = snapshot.workflowMark
            }
        }
        selectModeSnapshot = []
        selectedPhotos = []
        selectedPhoto = nil
        isSelectMode = false
    }

    func confirmSelectMode() {
        selectModeSnapshot = []
        selectedPhotos = []
        selectedPhoto = nil
        isSelectMode = false
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

    func deselectAll() {
        selectedPhotos = []
        selectedPhoto = nil
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
        isExporting = true

        Task {
            var exported = 0
            var failed = 0
            let fm = FileManager.default

            if !fm.fileExists(atPath: destinationDir) {
                try? fm.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)
            }

            for photo in filteredPhotos {
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
            }

            let total = filteredPhotos.count
            isExporting = false
            if failed == 0 {
                exportMessage = "已导出 \(total) 张照片（\(exported) 个文件）"
            } else {
                exportMessage = "导出完成：\(total) 张照片，\(exported) 个成功，\(failed) 个失败"
            }
        }
    }

    private var activePhotoIds: Set<String> {
        if !selectedPhotos.isEmpty {
            return selectedPhotos
        }
        if let selectedPhoto {
            return [selectedPhoto.id]
        }
        return []
    }

    // MARK: - AI 快筛

    private var aiProvider: LLMProvider = .mimo
    private var aiModel: String = "mimo-v2.5"

    func confirmAICull(provider: LLMProvider, model: String, speed: AICullSpeed) {
        aiProvider = provider
        aiModel = model

        aiCullService.analyze(
            photos: filteredPhotos.isEmpty ? photos : filteredPhotos,
            mode: .llm,
            provider: provider,
            model: model,
            speed: speed
        )
    }

    func applyAICullResults(markedPhotos: [PhotoEntry]) {
        // 把标记结果写回主数组
        var markedLookup: [String: PhotoEntry] = [:]
        markedLookup.reserveCapacity(markedPhotos.count)
        for marked in markedPhotos {
            markedLookup[marked.id] = marked
        }

        for i in photos.indices {
            if let marked = markedLookup[photos[i].id] {
                photos[i].workflowMark = marked.workflowMark
                photos[i].aiResult = marked.aiResult
            }
        }
        // 也写入 AI 分析结果
        aiCullService.applyResults(to: &photos)
        showingAICullReview = false
        applyFilters()
        syncSidecar()
    }

    func cancelAICull() {
        aiCullService.cancel()
        showingAICullReview = false
    }
}
