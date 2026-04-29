import SwiftUI

struct FinderTag: Identifiable, Hashable {
    let name: String
    let colorIndex: Int

    var id: String { name }

    var color: Color {
        switch colorIndex {
        case 1: return Color(red: 142/255, green: 142/255, blue: 147/255)
        case 2: return Color(red: 52/255, green: 199/255, blue: 89/255)
        case 3: return Color(red: 175/255, green: 82/255, blue: 222/255)
        case 4: return Color(red: 0/255, green: 122/255, blue: 255/255)
        case 5: return Color(red: 255/255, green: 204/255, blue: 0/255)
        case 6: return Color(red: 255/255, green: 59/255, blue: 48/255)
        case 7: return Color(red: 255/255, green: 149/255, blue: 0/255)
        default: return Color(red: 142/255, green: 142/255, blue: 147/255)
        }
    }

    var displayName: String {
        let colorNames: [Int: String] = [
            1: "灰色", 2: "绿色", 3: "紫色",
            4: "蓝色", 5: "黄色", 6: "红色", 7: "橙色"
        ]
        if let colorName = colorNames[colorIndex] {
            return "\(name) (\(colorName))"
        }
        return name
    }
}

@MainActor
class FinderTagService {
    static let shared = FinderTagService()

    private(set) var availableTags: [FinderTag] = []

    private init() {
        loadTags()
    }

    func loadTags() {
        var tagDict: [String: Int] = [:]

        let discoveredNames = discoverSystemTagNames()
        for (name, index) in discoveredNames {
            tagDict[name] = index
        }

        if tagDict.isEmpty {
            let fallback: [(String, Int)] = [
                ("Gray", 1), ("Green", 2), ("Purple", 3),
                ("Blue", 4), ("Yellow", 5), ("Red", 6), ("Orange", 7)
            ]
            for (name, idx) in fallback {
                tagDict[name] = idx
            }
        }

        availableTags = tagDict.map { FinderTag(name: $0.key, colorIndex: $0.value) }
        availableTags.sort { ($0.colorIndex > 0 ? $0.colorIndex : 99) < ($1.colorIndex > 0 ? $1.colorIndex : 99) }
    }

    private func discoverSystemTagNames() -> [(String, Int)] {
        var result: [String: Int] = [:]

        let dirs = [
            "/Users/sanshi/Desktop",
            "/Users/sanshi/Documents",
            "/Users/sanshi/Downloads"
        ]

        for dir in dirs {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let path = (dir as NSString).appendingPathComponent(item)
                let tags = readTagsFromXattr(path: path)
                for (name, colorIdx) in tags {
                    if result[name] == nil {
                        result[name] = colorIdx
                    }
                }
            }
        }

        return result.sorted { $0.value < $1.value }
    }

    private func readTagsFromXattr(path: String) -> [(String, Int)] {
        let xattrName = "com.apple.metadata:_kMDItemUserTags"
        let length = getxattr(path, xattrName, nil, 0, 0, 0)
        guard length > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: length)
        let result = getxattr(path, xattrName, &buffer, length, 0, 0)
        guard result > 0 else { return [] }

        let data = Data(bytes: buffer, count: result)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] else {
            return []
        }

        var tags: [(String, Int)] = []
        for item in plist {
            let parts = item.split(separator: "\n")
            let name = String(parts[0])
            let colorIdx = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            tags.append((name, colorIdx))
        }
        return tags
    }

    func tag(for name: String) -> FinderTag? {
        availableTags.first { $0.name == name }
    }

    func colorForTag(_ name: String) -> Color {
        tag(for: name)?.color ?? Color(red: 142/255, green: 142/255, blue: 147/255)
    }

    func displayNameForTag(_ name: String) -> String {
        tag(for: name)?.displayName ?? name
    }
}

struct PhotoEntry: Identifiable, Hashable {
    let id: String
    let baseName: String
    let jpgPath: String?
    let nefPath: String?
    let movPath: String?
    let jpgFileSize: Int64?
    let nefFileSize: Int64?
    let movFileSize: Int64?
    let fileDate: Date
    var rating: Int
    var tags: [String]
    var isDeleted: Bool

    init(baseName: String, jpgPath: String?, nefPath: String?, movPath: String?,
         jpgFileSize: Int64?, nefFileSize: Int64?, movFileSize: Int64?, fileDate: Date) {
        self.id = baseName
        self.baseName = baseName
        self.jpgPath = jpgPath
        self.nefPath = nefPath
        self.movPath = movPath
        self.jpgFileSize = jpgFileSize
        self.nefFileSize = nefFileSize
        self.movFileSize = movFileSize
        self.fileDate = fileDate
        self.rating = 0
        self.tags = []
        self.isDeleted = false
    }

    var hasJpg: Bool { jpgPath != nil }
    var hasNef: Bool { nefPath != nil }
    var hasMov: Bool { movPath != nil }
    var isVideoOnly: Bool { hasMov && !hasJpg && !hasNef }

    var displayName: String { baseName }

    var totalFileSize: Int64 {
        (jpgFileSize ?? 0) + (nefFileSize ?? 0) + (movFileSize ?? 0)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: fileDate)
    }

    var primaryImagePath: String {
        jpgPath ?? nefPath ?? ""
    }

    var primaryFilePath: String {
        jpgPath ?? nefPath ?? movPath ?? ""
    }

    var fileTypeDescription: String {
        var types: [String] = []
        if hasJpg { types.append("JPG") }
        if hasNef { types.append("NEF") }
        if hasMov { types.append("MOV") }
        return types.joined(separator: " + ")
    }

    var fileTypeBadge: String {
        if hasMov && hasNef && hasJpg { return "RAW+JPG+MOV" }
        if hasMov && hasNef { return "RAW+MOV" }
        if hasMov && hasJpg { return "JPG+MOV" }
        if hasNef && hasJpg { return "RAW+JPG" }
        if hasNef { return "RAW" }
        if hasMov { return "MOV" }
        return "JPG"
    }

    var fileTypeBadgeColor: Color {
        if hasMov && (hasNef || hasJpg) { return .teal }
        if hasMov { return .cyan }
        if hasNef && hasJpg { return .purple }
        if hasNef { return .indigo }
        return .blue
    }

    var hasAnyMark: Bool {
        rating > 0 || !tags.isEmpty
    }
}
