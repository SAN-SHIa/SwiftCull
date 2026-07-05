import Foundation
import ImageIO

final class FileService: @unchecked Sendable {
    static let shared = FileService()

    private init() {}

    /// 快速扫描：仅列出文件并按文件名分组，使用文件系统日期，立即可用于展示。
    /// EXIF 拍摄日期由 captureDate(for:) 在后台补充。
    func scanFilesFast(at path: String) async -> [PhotoEntry] {
        await Task.detached(priority: .userInitiated) {
            Self.scanFilesFastSync(at: path)
        }.value
    }

    /// 读取单张照片代表文件的 EXIF 拍摄日期（优先 JPG，其次 RAW；视频返回 nil）。
    nonisolated static func captureDate(for photo: PhotoEntry) -> Date? {
        if let jpg = photo.jpgPath {
            return readCaptureDate(from: jpg, fileExtension: (jpg as NSString).pathExtension.lowercased())
        }
        if let nef = photo.nefPath {
            return readCaptureDate(from: nef, fileExtension: (nef as NSString).pathExtension.lowercased())
        }
        return nil
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func scanFilesFastSync(at path: String) -> [PhotoEntry] {
        let fileManager = FileManager.default

        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("Failed to read directory: \(error)")
            return []
        }

        let imageExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "dng", "raf", "tiff", "tif"]
        let videoExtensions: Set<String> = ["mov", "mp4", "avi"]

        // 按文件名分组；仅使用文件系统日期占位，EXIF 拍摄日期稍后在后台补充
        var photoDict: [String: PhotoFileGroup] = [:]
        photoDict.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }

            guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
                  rv.isRegularFile != false else { continue }

            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let fileSize = rv.fileSize.map { Int64($0) }
            let fsDate = rv.creationDate ?? rv.contentModificationDate

            var group = photoDict[baseName] ?? PhotoFileGroup()
            switch ext {
            case "jpg", "jpeg", "tiff", "tif":
                group.jpgPath = fileURL.path
                group.jpgSize = fileSize
            case "nef", "cr2", "arw", "dng", "raf":
                group.nefPath = fileURL.path
                group.nefSize = fileSize
            case "mov", "mp4", "avi":
                group.movPath = fileURL.path
                group.movSize = fileSize
            default:
                break
            }
            group.updateCaptureDate(fsDate, priority: 0)
            group.updateModificationDate(rv.contentModificationDate)
            photoDict[baseName] = group
        }

        var entries: [PhotoEntry] = []
        entries.reserveCapacity(photoDict.count)

        for (baseName, data) in photoDict {
            guard data.jpgPath != nil || data.nefPath != nil || data.movPath != nil else { continue }

            let entry = PhotoEntry(
                baseName: baseName,
                jpgPath: data.jpgPath,
                nefPath: data.nefPath,
                movPath: data.movPath,
                jpgFileSize: data.jpgSize,
                nefFileSize: data.nefSize,
                movFileSize: data.movSize,
                fileDate: data.captureDate ?? data.modificationDate ?? Date(),
                modificationDate: data.modificationDate ?? data.captureDate ?? Date()
            )
            entries.append(entry)
        }

        entries.sort { $0.baseName < $1.baseName }
        return entries
    }

    func movePhotoToTrash(_ photo: PhotoEntry) -> Bool {
        let fileManager = FileManager.default
        var success = true

        if let jpgPath = photo.jpgPath {
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: jpgPath), resultingItemURL: nil)
            } catch {
                print("Failed to trash JPG: \(error)")
                success = false
            }
        }

        if let nefPath = photo.nefPath {
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: nefPath), resultingItemURL: nil)
            } catch {
                print("Failed to trash NEF: \(error)")
                success = false
            }
        }

        if let movPath = photo.movPath {
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: movPath), resultingItemURL: nil)
            } catch {
                print("Failed to trash MOV: \(error)")
                success = false
            }
        }

        return success
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private struct PhotoFileGroup {
        var jpgPath: String?
        var nefPath: String?
        var movPath: String?
        var jpgSize: Int64?
        var nefSize: Int64?
        var movSize: Int64?
        var captureDate: Date?
        var captureDatePriority = 0
        var modificationDate: Date?

        mutating func updateCaptureDate(_ date: Date?, priority: Int) {
            guard let date else { return }
            if captureDate == nil || priority >= captureDatePriority {
                captureDate = date
                captureDatePriority = priority
            }
        }

        mutating func updateModificationDate(_ date: Date?) {
            guard let date else { return }
            if let current = modificationDate {
                modificationDate = max(current, date)
            } else {
                modificationDate = date
            }
        }
    }

    private static func readCaptureDate(from path: String, fileExtension: String) -> Date? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ??
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String ??
            tiff?[kCGImagePropertyTIFFDateTime] as? String

        return parseImageDate(dateString)
    }

    private static func parseImageDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let formatter = exifDateFormatter

        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
