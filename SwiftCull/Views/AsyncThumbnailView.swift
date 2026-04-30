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

    private var cacheId: String {
        "\(imagePath)|\(Int(size.rounded()))"
    }

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
        .onChange(of: cacheId) { _, _ in
            loadTask?.cancel()
            image = nil
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let service = ThumbnailService.shared

        if let cached = service.getCached(cacheId) {
            self.image = cached
            return
        }

        guard !imagePath.isEmpty else { return }

        loadTask = Task {
            await withCheckedContinuation { continuation in
                service.generateThumbnail(path: imagePath, id: cacheId, size: size) { newImage in
                    if let newImage {
                        self.image = newImage
                    }
                    continuation.resume()
                }
            }
            guard !Task.isCancelled else { return }
            if let cached = service.getCached(cacheId) {
                self.image = cached
            }
        }
    }
}

struct DetailThumbnailView: View {
    let photo: PhotoEntry
    var targetSize: CGFloat = 1000
    @State private var image: NSImage?

    private var cacheId: String {
        "detail|\(photo.primaryFilePath)|\(Int(targetSize.rounded()))"
    }

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
        .onChange(of: photo.primaryFilePath) { _, _ in
            image = nil
            loadDetailImage()
        }
    }

    private func loadDetailImage() {
        let service = ThumbnailService.shared
        let path = photo.primaryImagePath
        guard !path.isEmpty else {
            if photo.hasMov, let movPath = photo.movPath {
                service.generateThumbnail(path: movPath, id: cacheId, size: targetSize) { newImage in
                    self.image = newImage
                }
            }
            return
        }

        if let cached = service.getCached(cacheId) {
            self.image = cached
        }

        service.generateThumbnail(path: path, id: cacheId, size: targetSize) { newImage in
            self.image = newImage
        }
    }
}
