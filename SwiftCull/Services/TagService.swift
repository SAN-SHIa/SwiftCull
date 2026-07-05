import Foundation

final class TagService: @unchecked Sendable {
    static let shared = TagService()

    private let xattrName = "com.apple.metadata:_kMDItemUserTags"

    private init() {}

    func getTags(for path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        do {
            if let tagNames = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames {
                return tagNames
            }
        } catch {}
        return readTagsViaXattr(path)
    }

    private func readTagsViaXattr(_ path: String) -> [String] {
        let data = getxattr(path, xattrName, nil, 0, 0, 0)
        guard data > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: data)
        let result = getxattr(path, xattrName, &buffer, data, 0, 0)
        guard result > 0 else { return [] }

        buffer.append(0)
        let plistData = Data(bytes: buffer, count: result)

        do {
            if let tags = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String] {
                return tags.map { tag in
                    if let range = tag.range(of: "\n") {
                        return String(tag[..<range.lowerBound])
                    }
                    return tag
                }
            }
        } catch {}
        return []
    }

    func setTags(_ tags: [String], for path: String, colorLookup: [String: Int] = [:]) -> Bool {
        let taggedArray = tags.map { tag in
            let color = colorLookup[tag] ?? Self.defaultColorForTag(tag)
            return "\(tag)\n\(color)"
        }

        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: taggedArray, format: .binary, options: 0)
            let result = setxattr(path, xattrName, (plistData as NSData).bytes, plistData.count, 0, 0)
            if result == 0 {
                syncFS(path)
                return true
            }
        } catch {}
        return false
    }

    private static func defaultColorForTag(_ tag: String) -> Int {
        let colorMap: [String: Int] = [
            "Gray": 1, "Green": 2, "Purple": 3,
            "Blue": 4, "Yellow": 5, "Red": 6, "Orange": 7
        ]
        return colorMap[tag] ?? 0
    }

    private func syncFS(_ path: String) {
        let url = URL(fileURLWithPath: path)
        var resourceValues = URLResourceValues()
        resourceValues.contentModificationDate = Date()
        var mutableUrl = url
        try? mutableUrl.setResourceValues(resourceValues)
    }

    func setTagsForPhotoPair(_ tags: [String], photo: PhotoEntry, colorLookup: [String: Int] = [:]) -> Bool {
        var success = true
        if let jpgPath = photo.jpgPath {
            if !setTags(tags, for: jpgPath, colorLookup: colorLookup) {
                success = false
            }
        }
        if let nefPath = photo.nefPath {
            if !setTags(tags, for: nefPath, colorLookup: colorLookup) {
                success = false
            }
        }
        return success
    }

    func getTagsForPhotoPair(_ photo: PhotoEntry) -> [String] {
        var allTags = Set<String>()
        if let jpgPath = photo.jpgPath {
            allTags.formUnion(getTags(for: jpgPath))
        }
        if let nefPath = photo.nefPath {
            allTags.formUnion(getTags(for: nefPath))
        }
        return Array(allTags).sorted()
    }
}
