import Foundation

@MainActor
class FileService {
    static let shared = FileService()

    private init() {}

    func scanDirectory(at path: String) async -> [PhotoEntry] {
        let fileManager = FileManager.default
        var entries: [PhotoEntry] = []

        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            print("Failed to read directory: \(error)")
            return []
        }

        var photoDict: [String: (jpgPath: String?, nefPath: String?, movPath: String?,
                                 jpgSize: Int64?, nefSize: Int64?, movSize: Int64?, date: Date?)] = [:]

        let imageExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "arw", "dng", "tiff", "tif"]
        let videoExtensions: Set<String> = ["mov", "mp4", "avi"]

        for fileName in contents {
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }

            let baseName = (fileName as NSString).deletingPathExtension
            let fullPath = (path as NSString).appendingPathComponent(fileName)

            let attrs: [FileAttributeKey: Any]? = try? fileManager.attributesOfItem(atPath: fullPath)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value
            let modDate = attrs?[.modificationDate] as? Date

            if photoDict[baseName] == nil {
                photoDict[baseName] = (jpgPath: nil, nefPath: nil, movPath: nil,
                                       jpgSize: nil, nefSize: nil, movSize: nil, date: nil)
            }

            var entry = photoDict[baseName]!

            switch ext {
            case "jpg", "jpeg":
                entry.jpgPath = fullPath
                entry.jpgSize = fileSize
                entry.date = modDate ?? entry.date
            case "nef", "cr2", "arw", "dng":
                entry.nefPath = fullPath
                entry.nefSize = fileSize
                entry.date = modDate ?? entry.date
            case "mov", "mp4", "avi":
                entry.movPath = fullPath
                entry.movSize = fileSize
                entry.date = modDate ?? entry.date
            default:
                break
            }

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
                fileDate: data.date ?? Date()
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
}
