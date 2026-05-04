import Foundation
import AppKit
import AVFoundation
import CryptoKit
import ImageIO

final class ThumbnailService: @unchecked Sendable {
    static let shared = ThumbnailService()

    private struct PendingRequest {
        let generation: Int
        var completions: [@MainActor @Sendable (NSImage?) -> Void]
    }

    private let cache = NSCache<NSString, NSImage>()
    private let workQueue = DispatchQueue(label: "com.swiftcull.thumbnail.work", qos: .userInitiated, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "com.swiftcull.thumbnail.state")
    private let generationSemaphore = DispatchSemaphore(value: 4)
    private var inProgress: [String: PendingRequest] = [:]
    private var generation = 0

    private let diskCacheDir: URL
    private let fileManager = FileManager.default

    private init() {
        cache.countLimit = 800
        cache.totalCostLimit = 300 * 1024 * 1024

        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = cachesDir.appendingPathComponent("SwiftCull/Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    func getCached(_ id: String) -> NSImage? {
        cache.object(forKey: id as NSString)
    }

    func thumbnail(path: String, id: String, size: CGFloat) async -> NSImage? {
        if let cached = getCached(id) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            generateThumbnail(path: path, id: id, size: size) { image in
                continuation.resume(returning: image)
            }
        }
    }

    func generateThumbnail(path: String, id: String, size: CGFloat, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        if let cached = getCached(id) {
            Task { @MainActor in
                completion(cached)
            }
            return
        }

        var requestGeneration = 0
        let shouldStart = stateQueue.sync {
            if var pending = inProgress[id] {
                pending.completions.append(completion)
                inProgress[id] = pending
                return false
            }

            requestGeneration = generation
            inProgress[id] = PendingRequest(generation: requestGeneration, completions: [completion])
            return true
        }

        guard shouldStart else { return }

        let generationForRequest = requestGeneration
        workQueue.async { [weak self] in
            self?.produceThumbnail(path: path, id: id, size: size, generation: generationForRequest)
        }
    }

    func cancelPending() {
        stateQueue.sync {
            generation += 1
            inProgress.removeAll()
        }
    }

    func clearCache() {
        cancelPending()
        cache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDir)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    func preloadThumbnails(paths: [(id: String, path: String)], size: CGFloat) {
        let items = paths
            .filter { !$0.path.isEmpty && getCached($0.id) == nil }
            .prefix(80)

        for item in items {
            generateThumbnail(path: item.path, id: item.id, size: size) { _ in }
        }
    }

    private func produceThumbnail(path: String, id: String, size: CGFloat, generation requestGeneration: Int) {
        generationSemaphore.wait()
        defer { generationSemaphore.signal() }

        guard isCurrentGeneration(requestGeneration) else {
            return
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mov", "mp4", "avi"]
        var shouldPersist = false

        var image = loadFromDiskCache(id: id)
        if image == nil {
            if videoExtensions.contains(ext) {
                image = Self.createVideoThumbnail(path: path, maxSize: size)
            } else {
                image = Self.createThumbnail(path: path, maxSize: size)
            }
            shouldPersist = image != nil
        }

        if let image {
            cache.setObject(image, forKey: id as NSString, cost: Self.cost(for: image))
            if shouldPersist {
                saveToDiskCache(image: image, id: id)
            }
        }

        let completions = finish(id: id, generation: requestGeneration)
        guard !completions.isEmpty else { return }

        Task { @MainActor in
            for completion in completions {
                completion(image)
            }
        }
    }

    private func isCurrentGeneration(_ requestGeneration: Int) -> Bool {
        stateQueue.sync {
            generation == requestGeneration
        }
    }

    private func finish(id: String, generation requestGeneration: Int) -> [@MainActor @Sendable (NSImage?) -> Void] {
        stateQueue.sync {
            guard inProgress[id]?.generation == requestGeneration else {
                return []
            }
            return inProgress.removeValue(forKey: id)?.completions ?? []
        }
    }

    private func loadFromDiskCache(id: String) -> NSImage? {
        let url = cacheFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, imageOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func saveToDiskCache(image: NSImage, id: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }

        try? data.write(to: cacheFileURL(for: id), options: .atomic)
    }

    private func cacheFileURL(for id: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskCacheDir.appendingPathComponent("\(digest).jpg")
    }

    private static func cost(for image: NSImage) -> Int {
        if let representation = image.representations.first {
            return representation.pixelsWide * representation.pixelsHigh * 4
        }
        return Int(image.size.width * image.size.height * 4)
    }

    private static func createThumbnail(path: String, maxSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let pixelSize = max(64, Int(maxSize * 2.0))
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func createVideoThumbnail(path: String, maxSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
