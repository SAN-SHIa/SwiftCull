import SwiftUI
import AVKit

struct AsyncThumbnailView: View {
    let photoId: String
    let imagePath: String
    let size: CGFloat
    let isVideo: Bool

    init(photoId: String, imagePath: String, size: CGFloat, isVideo: Bool = false) {
        self.photoId = photoId
        self.imagePath = imagePath
        self.size = size
        self.isVideo = isVideo
    }

    @State private var image: NSImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = image {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    if isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .padding(4)
                            }
                        }
                    }
                }
            } else if isVideo {
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .drawingGroup()
        .onAppear {
            loadThumbnail()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: imagePath) { _, _ in
            loadTask?.cancel()
            image = nil
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let service = ThumbnailService.shared

        if let cached = service.getCached(photoId) {
            self.image = cached
            return
        }

        guard !imagePath.isEmpty else { return }

        loadTask = Task {
            await withCheckedContinuation { continuation in
                service.generateThumbnail(path: imagePath, id: photoId, size: size) { newImage in
                    continuation.resume()
                }
            }
            guard !Task.isCancelled else { return }
            if let cached = service.getCached(photoId) {
                self.image = cached
            }
        }
    }
}

struct DetailThumbnailView: View {
    let photo: PhotoEntry
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if photo.isVideoOnly {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.8)
                }
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            loadDetailImage()
        }
        .onChange(of: photo.id) { _, _ in
            image = nil
            loadDetailImage()
        }
    }

    private func loadDetailImage() {
        let service = ThumbnailService.shared
        let path = photo.primaryImagePath
        guard !path.isEmpty else {
            if photo.hasMov, let movPath = photo.movPath {
                service.generateThumbnail(path: movPath, id: "detail_\(photo.id)", size: 800) { newImage in
                    self.image = newImage
                }
            }
            return
        }

        if let cached = service.getCached("detail_\(photo.id)") {
            self.image = cached
        }

        service.generateThumbnail(path: path, id: "detail_\(photo.id)", size: 800) { newImage in
            self.image = newImage
        }
    }
}
