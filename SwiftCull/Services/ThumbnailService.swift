import Foundation
import AppKit
import AVFoundation

@MainActor
final class ThumbnailService: Sendable {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.swiftcull.thumbnail", qos: .userInteractive, attributes: .concurrent)
    private var inProgress: Set<String> = []
    private let lock = NSLock()

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
        if let cached = cache.object(forKey: id as NSString) {
            return cached
        }
        return loadFromDiskCache(id: id)
    }

    private func loadFromDiskCache(id: String) -> NSImage? {
        let safeId = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let path = diskCacheDir.appendingPathComponent("\(safeId).png").path
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: id as NSString, cost: cost)
        return image
    }

    func generateThumbnail(path: String, id: String, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        lock.lock()
        if inProgress.contains(id) {
            lock.unlock()
            return
        }
        inProgress.insert(id)
        lock.unlock()

        queue.async { [weak self] in
            let ext = (path as NSString).pathExtension.lowercased()
            let videoExtensions: Set<String> = ["mov", "mp4", "avi"]
            let image: NSImage?

            if videoExtensions.contains(ext) {
                image = self?.createVideoThumbnail(path: path, maxSize: size)
            } else {
                image = self?.createThumbnail(path: path, maxSize: size)
            }

            self?.lock.lock()
            self?.inProgress.remove(id)
            self?.lock.unlock()

            if let image = image {
                let cost = Int(image.size.width * image.size.height * 4)
                self?.cache.setObject(image, forKey: id as NSString, cost: cost)
                self?.saveToDiskCache(image: image, id: id)
                DispatchQueue.main.async {
                    completion(image)
                }
            }
        }
    }

    private func saveToDiskCache(image: NSImage, id: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let safeId = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let path = diskCacheDir.appendingPathComponent("\(safeId).png").path
        try? pngData.write(to: URL(fileURLWithPath: path))
    }

    private func createThumbnail(path: String, maxSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return fallbackThumbnail(path: path, maxSize: maxSize)
        }

        let pixelSize = maxSize * 2.0
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return fallbackThumbnail(path: path, maxSize: maxSize)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func createVideoThumbnail(path: String, maxSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return createVideoPlaceholder(maxSize: maxSize)
        }
    }

    private func createVideoPlaceholder(maxSize: CGFloat) -> NSImage? {
        let size = NSSize(width: maxSize, height: maxSize)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: maxSize * 0.3, weight: .light),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let text = "🎬"
        let textRect = text.boundingRect(with: size, options: [], attributes: attrs)
        let textPoint = CGPoint(
            x: (size.width - textRect.width) / 2,
            y: (size.height - textRect.height) / 2
        )
        text.draw(at: textPoint, withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    private func fallbackThumbnail(path: String, maxSize: CGFloat) -> NSImage? {
        guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let targetSize = NSSize(width: maxSize, height: maxSize)
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDir)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    func preloadThumbnails(paths: [(id: String, path: String)], size: CGFloat) {
        let batchSize = 30
        let items = paths.filter { getCached($0.id) == nil }
        let batches = stride(from: 0, to: items.count, by: batchSize)

        for (batchIndex, startIndex) in batches.enumerated() {
            let endIndex = min(startIndex + batchSize, items.count)
            let batch = Array(items[startIndex..<endIndex])

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(batchIndex) * 0.15) {
                for item in batch {
                    self.generateThumbnail(path: item.path, id: item.id, size: size) { _ in }
                }
            }
        }
    }
}
