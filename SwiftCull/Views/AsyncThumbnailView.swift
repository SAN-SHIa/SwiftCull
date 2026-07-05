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
        loadTask?.cancel()
        let service = ThumbnailService.shared

        if let cached = service.getCached(cacheId) {
            self.image = cached
            return
        }

        guard !imagePath.isEmpty else { return }

        let requestCacheId = cacheId
        let requestPath = imagePath
        let requestSize = size
        loadTask = Task { @MainActor in
            let newImage = await service.thumbnail(path: requestPath, id: requestCacheId, size: requestSize)
            guard !Task.isCancelled else { return }
            guard cacheId == requestCacheId, let newImage else { return }
            self.image = newImage
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
        .id(photo.primaryFilePath)
        .task(id: photo.primaryFilePath) {
            await loadDetailImage()
        }
    }

    private func loadDetailImage() async {
        let path = photo.primaryImagePath.isEmpty ? (photo.movPath ?? "") : photo.primaryImagePath
        guard !path.isEmpty else { return }

        let requestPath = path
        let isVideo = photo.isVideoOnly
        let loaded = await loadDetailImageBackground(path: requestPath, isVideo: isVideo)

        guard !Task.isCancelled else { return }
        self.image = loaded
    }

    /// Background image loading; isolated to avoid NSImage Sendable issues on older SDKs.
    private nonisolated func loadDetailImageBackground(path: String, isVideo: Bool) async -> NSImage? {
        if isVideo {
            let service = ThumbnailService.shared
            // Use withCheckedContinuation to avoid NSImage Sendable requirement in task groups
            return await withCheckedContinuation { continuation in
                service.generateThumbnail(path: path, id: "detail|\(path)", size: 800) { image in
                    continuation.resume(returning: image)
                }
            }
        }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let origW = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 6000
        let origH = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 4000
        let maxDim = max(origW, origH)

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

