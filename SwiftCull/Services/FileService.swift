import Foundation
import ImageIO

final class FileService: @unchecked Sendable {
    static let shared = FileService()

    private init() {}

    func scanDirectory(at path: String) async -> [PhotoEntry] {
        await Task.detached(priority: .userInitiated) {
            Self.scanDirectorySync(at: path)
        }.value
    }

    private static func scanDirectorySync(at path: String) -> [PhotoEntry] {
        let fileManager = FileManager.default
        var entries: [PhotoEntry] = []

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

        var photoDict: [String: PhotoFileGroup] = [:]

        let imageExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "dng", "tiff", "tif"]
        let videoExtensions: Set<String> = ["mov", "mp4", "avi"]

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
            if resourceValues?.isRegularFile == false { continue }

            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let fullPath = fileURL.path
            let fileSize = resourceValues?.fileSize.map { Int64($0) }
            let modDate = resourceValues?.contentModificationDate
            let captureDate = readCaptureDate(from: fileURL, fileExtension: ext) ?? resourceValues?.creationDate ?? modDate

            if photoDict[baseName] == nil {
                photoDict[baseName] = PhotoFileGroup()
            }

            var entry = photoDict[baseName]!

            switch ext {
            case "jpg", "jpeg":
                entry.jpgPath = fullPath
                entry.jpgSize = fileSize
                entry.updateCaptureDate(captureDate, priority: 3)
            case "nef", "cr2", "arw", "dng":
                entry.nefPath = fullPath
                entry.nefSize = fileSize
                entry.updateCaptureDate(captureDate, priority: 2)
            case "tiff", "tif":
                entry.jpgPath = fullPath
                entry.jpgSize = fileSize
                entry.updateCaptureDate(captureDate, priority: 3)
            case "mov", "mp4", "avi":
                entry.movPath = fullPath
                entry.movSize = fileSize
                entry.updateCaptureDate(captureDate, priority: 1)
            default:
                break
            }

            entry.updateModificationDate(modDate)
            photoDict[baseName] = entry
        }

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

    private static func readCaptureDate(from fileURL: URL, fileExtension: String) -> Date? {
        let metadataExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "dng", "tiff", "tif"]
        guard metadataExtensions.contains(fileExtension),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
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

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
