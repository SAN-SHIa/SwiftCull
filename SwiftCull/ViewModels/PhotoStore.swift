import Foundation
import SwiftUI
import Combine

struct PhotoSnapshot {
    let photoId: String
    let rating: Int
    let tags: [String]
}

@MainActor
class PhotoStore: ObservableObject {
    @Published var photos: [PhotoEntry] = []
    @Published var filteredPhotos: [PhotoEntry] = []
    @Published var selectedPhoto: PhotoEntry?
    @Published var selectedPhotos: Set<String> = []
    @Published var filterOptions = FilterOptions()
    @Published var isLoading = false
    @Published var sourcePath: String = "/Volumes/sandi64G/DCIM/100NZ5_2"
    @Published var errorMessage: String?
    @Published var showingDeleteConfirmation = false
    @Published var photosToDelete: [PhotoEntry] = []

    private let fileService = FileService.shared
    private let tagService = TagService.shared
    private let ratingService = RatingService.shared
    private let thumbnailService = ThumbnailService.shared
    let finderTagService = FinderTagService.shared

    private var selectModeSnapshot: [PhotoSnapshot] = []

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
        isLoading = true
        errorMessage = nil

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDir) || !isDir.boolValue {
            errorMessage = "路径不存在或不是文件夹: \(sourcePath)"
            isLoading = false
            return
        }

        let loaded = await fileService.scanDirectory(at: sourcePath)

        var enriched: [PhotoEntry] = []
        for var photo in loaded {
            photo.rating = ratingService.getRating(for: photo.id)
            photo.tags = tagService.getTagsForPhotoPair(photo)
            enriched.append(photo)
        }

        photos = enriched
        applyFilters()
        isLoading = false

        preloadVisibleThumbnails()
    }

    private func preloadVisibleThumbnails() {
        let items = filteredPhotos.prefix(100).map { (id: $0.id, path: $0.primaryFilePath) }
        thumbnailService.preloadThumbnails(paths: items, size: 160)
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
                    _ = tagService.setTagsForPhotoPair(tags, photo: photos[index])
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
            _ = tagService.setTagsForPhotoPair(currentTags, photo: photos[index])
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
        _ = tagService.setTagsForPhotoPair(currentTags, photo: photos[index])
        photos[index].tags = currentTags
        if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
            filteredPhotos[filteredIndex].tags = currentTags
        }
        if selectedPhoto?.id == photo.id {
            selectedPhoto?.tags = currentTags
        }
    }

    func enterSelectMode() {
        selectModeSnapshot = photos.map { PhotoSnapshot(photoId: $0.id, rating: $0.rating, tags: $0.tags) }
    }

    func cancelSelectMode() {
        for snapshot in selectModeSnapshot {
            if let index = photos.firstIndex(where: { $0.id == snapshot.photoId }) {
                ratingService.setRating(snapshot.rating, for: snapshot.photoId)
                photos[index].rating = snapshot.rating
                _ = tagService.setTagsForPhotoPair(snapshot.tags, photo: photos[index])
                photos[index].tags = snapshot.tags
            }
            if let filteredIndex = filteredPhotos.firstIndex(where: { $0.id == snapshot.photoId }) {
                filteredPhotos[filteredIndex].rating = snapshot.rating
                filteredPhotos[filteredIndex].tags = snapshot.tags
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

    func deselectAll() {
        selectedPhotos = []
        selectedPhoto = nil
    }

    func navigateToPrevious() {
        guard let current = selectedPhoto,
              let index = filteredPhotos.firstIndex(where: { $0.id == current.id }),
              index > 0 else { return }
        let prev = filteredPhotos[index - 1]
        selectedPhoto = prev
        selectedPhotos = [prev.id]
    }

    func navigateToNext() {
        guard let current = selectedPhoto,
              let index = filteredPhotos.firstIndex(where: { $0.id == current.id }),
              index < filteredPhotos.count - 1 else { return }
        let next = filteredPhotos[index + 1]
        selectedPhoto = next
        selectedPhotos = [next.id]
    }

    func navigateUp() { navigateToPrevious() }
    func navigateDown() { navigateToNext() }
    func navigateLeft() { navigateToPrevious() }
    func navigateRight() { navigateToNext() }

    func requestDelete(_ photo: PhotoEntry) {
        photosToDelete = [photo]
        showingDeleteConfirmation = true
    }

    func requestDeleteSelected() {
        let entries = selectedPhotoEntries
        guard !entries.isEmpty else { return }
        photosToDelete = entries
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        for photo in photosToDelete {
            if fileService.movePhotoToTrash(photo) {
                if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                    photos[index].isDeleted = true
                }
            }
        }
        photosToDelete = []
        showingDeleteConfirmation = false
        selectedPhotos = []
        selectedPhoto = nil
        applyFilters()
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
}
