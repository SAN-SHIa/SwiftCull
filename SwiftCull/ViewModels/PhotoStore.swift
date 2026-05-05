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
    @Published var detectedVolumes: [DetectedVolume] = []

    private let fileService = FileService.shared
    private let tagService = TagService.shared
    private let ratingService = RatingService.shared
    private let thumbnailService = ThumbnailService.shared
    let finderTagService = FinderTagService.shared

    private var selectModeSnapshot: [PhotoSnapshot] = []
    private var gridColumnCount = 1
    private var currentLoadID = UUID()
    private var lastPreheatKey: String?
    private var tagColorLookup: [String: Int] {
        finderTagService.tagColorLookup
    }

    var photoCount: Int { filteredPhotos.count }
    var totalPhotoCount: Int { photos.count }

    var totalSize: String {
        let total = filteredPhotos.reduce(Int64(0)) { $0 + $1.totalFileSize }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var selectedPhotoEntries: [PhotoEntry] {
        filteredPhotos.filter { selectedPhotos.contains($0.id) }
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
        guard currentLoadID == loadID else { return }

        var enriched: [PhotoEntry] = []
        enriched.reserveCapacity(loaded.count)

        if loaded.isEmpty {
            loadingStatus = "未找到可识别的照片"
            loadingProgress = 1
        } else {
            loadingStatus = "正在读取评分与 Finder 标签..."
            loadingProgress = 0.2

            let chunkSize = 200
            for startIndex in stride(from: 0, to: loaded.count, by: chunkSize) {
                let endIndex = min(startIndex + chunkSize, loaded.count)
                let chunk = Array(loaded[startIndex..<endIndex])

                let partial = await Task.detached(priority: .userInitiated) {
                    let ratingService = RatingService.shared
                    let tagService = TagService.shared
                    return chunk.map { entry in
                        var photo = entry
                        photo.rating = ratingService.getRating(for: photo.id)
                        photo.tags = tagService.getTagsForPhotoPair(photo)
                        return photo
                    }
                }.value

                guard currentLoadID == loadID else { return }

                enriched.append(contentsOf: partial)
                loadingProgress = 0.2 + 0.65 * (Double(enriched.count) / Double(loaded.count))
                loadingStatus = "正在读取评分与 Finder 标签 \(enriched.count)/\(loaded.count)"
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
        var result = photos.filter { !$0.isDeleted }

        let trimmedQuery = filterOptions.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            let query = trimmedQuery.lowercased()
            result = result.filter { photo in
                photo.baseName.lowercased().contains(query)
            }
        }

        switch filterOptions.ratingFilter {
        case .all:
            break
        case .unrated:
            result = result.filter { $0.rating == 0 }
        default:
            result = result.filter { $0.rating == filterOptions.ratingFilter.rawValue }
        }

        switch filterOptions.fileTypeFilter {
        case .all:
            break
        case .jpgOnly:
            result = result.filter { $0.hasJpg && !$0.hasNef && !$0.hasMov }
        case .nefOnly:
            result = result.filter { $0.hasNef && !$0.hasJpg && !$0.hasMov }
        case .jpgAndNef:
            result = result.filter { $0.hasJpg && $0.hasNef }
        case .movOnly:
            result = result.filter { $0.isVideoOnly }
        case .hasMov:
            result = result.filter { $0.hasMov }
        }

        if let tagFilter = filterOptions.tagFilter {
            result = result.filter { $0.tags.contains(tagFilter) }
        }

        result = sortPhotos(result)

        filteredPhotos = result
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
        let ids = activePhotoIds
        guard !ids.isEmpty else { return }

        for id in ids {
            if let index = photos.firstIndex(where: { $0.id == id }) {
                photos[index].workflowMark = mark
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == id }) {
                filteredPhotos[filteredIndex].workflowMark = mark
            }
        }
        if let selected = selectedPhoto, ids.contains(selected.id) {
            selectedPhoto?.workflowMark = mark
        }
    }

    private func toggleActiveMark(_ mark: PhotoWorkflowMark) {
        let ids = activePhotoIds
        guard !ids.isEmpty else { return }
        let shouldClear = ids.allSatisfy { id in
            filteredPhotos.first { $0.id == id }?.workflowMark == mark ||
            photos.first { $0.id == id }?.workflowMark == mark
        }
        markActivePhotos(shouldClear ? .none : mark)
    }

    func batchSetRating(_ rating: Int) {
        for photoId in selectedPhotos {
            if let index = photos.firstIndex(where: { $0.id == photoId }) {
                ratingService.setRating(rating, for: photoId)
                photos[index].rating = rating
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photoId }) {
                filteredPhotos[filteredIndex].rating = rating
            }
        }
        if let selected = selectedPhoto, selectedPhotos.contains(selected.id) {
            selectedPhoto?.rating = rating
        }
        objectWillChange.send()
    }

    func batchClearRating() {
        batchSetRating(0)
    }

    func batchAddTag(_ tag: String) {
        for photoId in selectedPhotos {
            if let index = photos.firstIndex(where: { $0.id == photoId }) {
                var tags = photos[index].tags
                if !tags.contains(tag) {
                    tags.append(tag)
                    _ = tagService.setTagsForPhotoPair(tags, photo: photos[index], colorLookup: tagColorLookup)
                    photos[index].tags = tags
                }
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photoId }) {
                var tags = filteredPhotos[filteredIndex].tags
                if !tags.contains(tag) {
                    tags.append(tag)
                    filteredPhotos[filteredIndex].tags = tags
                }
            }
        }
        if let selected = selectedPhoto, selectedPhotos.contains(selected.id) {
            if !selectedPhoto!.tags.contains(tag) {
                selectedPhoto?.tags.append(tag)
            }
        }
        objectWillChange.send()
    }

    func batchClearTags() {
        for photoId in selectedPhotos {
            if let index = photos.firstIndex(where: { $0.id == photoId }) {
                _ = tagService.setTagsForPhotoPair([], photo: photos[index])
                photos[index].tags = []
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photoId }) {
                filteredPhotos[filteredIndex].tags = []
            }
        }
        if let selected = selectedPhoto, selectedPhotos.contains(selected.id) {
            selectedPhoto?.tags = []
        }
        objectWillChange.send()
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
    }

    func cancelSelectMode() {
        for snapshot in selectModeSnapshot {
            if let index = photos.firstIndex(where: { $0.id == snapshot.photoId }) {
                ratingService.setRating(snapshot.rating, for: snapshot.photoId)
                photos[index].rating = snapshot.rating
                _ = tagService.setTagsForPhotoPair(snapshot.tags, photo: photos[index], colorLookup: tagColorLookup)
                photos[index].tags = snapshot.tags
                photos[index].workflowMark = snapshot.workflowMark
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == snapshot.photoId }) {
                filteredPhotos[filteredIndex].rating = snapshot.rating
                filteredPhotos[filteredIndex].tags = snapshot.tags
                filteredPhotos[filteredIndex].workflowMark = snapshot.workflowMark
            }
        }
        selectModeSnapshot = []
        selectedPhotos = []
        selectedPhoto = nil
    }

    func confirmSelectMode() {
        selectModeSnapshot = []
        selectedPhotos = []
        selectedPhoto = nil
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
        selectedPhotos = Set(filteredPhotos.map { $0.id })
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
        var deletedIds: Set<String> = []

        for photo in deleteRequest {
            if fileService.movePhotoToTrash(photo) {
                if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                    photos[index].isDeleted = true
                    deletedIds.insert(photo.id)
                }
            }
        }

        photosToDelete = []
        showingDeleteConfirmation = false

        guard !deletedIds.isEmpty else { return }

        applyFilters()
        selectPhotoAfterDeletion(anchorIndex: selectionAnchorIndex)
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
}
