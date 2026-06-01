import Foundation
import ImageIO

final class FileService: @unchecked Sendable {
    static let shared = FileService()

    private init() {}

    func scanDirectory(at path: String) async -> [PhotoEntry] {
        await Task.detached(priority: .userInitiated) {
            await Self.scanDirectorySync(at: path)
        }.value
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

    private static func scanDirectorySync(at path: String) async -> [PhotoEntry] {
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
        let metadataExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "dng", "raf", "tiff", "tif"]

        // Phase 1: Fast scan - collect file info using resource values only
        struct FileEntry {
            let baseName: String
            let ext: String
            let path: String
            let fileSize: Int64?
            let creationDate: Date?
            let modDate: Date?
        }

        var fileEntries: [FileEntry] = []
        fileEntries.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }

            guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
                  rv.isRegularFile != false else { continue }

            fileEntries.append(FileEntry(
                baseName: fileURL.deletingPathExtension().lastPathComponent,
                ext: ext,
                path: fileURL.path,
                fileSize: rv.fileSize.map { Int64($0) },
                creationDate: rv.creationDate,
                modDate: rv.contentModificationDate
            ))
        }

        // Phase 2: Parallel EXIF reading for image files only
        struct ExifResult: Sendable {
            let index: Int
            let date: Date?
        }

        let imageIndices = fileEntries.indices.filter { metadataExtensions.contains(fileEntries[$0].ext) }
        let entriesForExif = imageIndices.map { fileEntries[$0] }

        var exifDates: [Int: Date?] = [:]
        exifDates.reserveCapacity(imageIndices.count)

        await withTaskGroup(of: ExifResult.self) { group in
            for (iteration, fileEntry) in entriesForExif.enumerated() {
                let path = fileEntry.path
                let ext = fileEntry.ext
                let originalIndex = imageIndices[iteration]
                group.addTask(priority: .userInitiated) {
                    let date = readCaptureDate(from: path, fileExtension: ext)
                    return ExifResult(index: originalIndex, date: date)
                }
            }
            for await result in group {
                exifDates[result.index] = result.date
            }
        }

        // Phase 3: Build photo dictionary
        var photoDict: [String: PhotoFileGroup] = [:]

        for (index, entry) in fileEntries.enumerated() {
            let captureDate = exifDates[index] ?? nil ?? entry.creationDate ?? entry.modDate

            if photoDict[entry.baseName] == nil {
                photoDict[entry.baseName] = PhotoFileGroup()
            }

            var group = photoDict[entry.baseName]!

            switch entry.ext {
            case "jpg", "jpeg":
                group.jpgPath = entry.path
                group.jpgSize = entry.fileSize
                group.updateCaptureDate(captureDate, priority: 3)
            case "nef", "cr2", "arw", "dng", "raf":
                group.nefPath = entry.path
                group.nefSize = entry.fileSize
                group.updateCaptureDate(captureDate, priority: 2)
            case "tiff", "tif":
                group.jpgPath = entry.path
                group.jpgSize = entry.fileSize
                group.updateCaptureDate(captureDate, priority: 3)
            case "mov", "mp4", "avi":
                group.movPath = entry.path
                group.movSize = entry.fileSize
                group.updateCaptureDate(captureDate, priority: 1)
            default:
                break
            }

            group.updateModificationDate(entry.modDate)
            photoDict[entry.baseName] = group
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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
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
