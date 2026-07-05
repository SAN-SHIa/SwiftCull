import SwiftUI

@MainActor
class FinderTagService {
    static let shared = FinderTagService()

    private(set) var availableTags: [FinderTag] = []

    private init() {
        loadTags()
    }

    private let finderSidebarColorOrder = [0, 6, 7, 5, 2, 4, 3, 1]

    private func readFinderTagPreferences() -> [String: Int] {
        guard let tagNames = CFPreferencesCopyAppValue(
            "FavoriteTagNames" as CFString,
            "com.apple.finder" as CFString
        ) as? [String] else {
            return [:]
        }

        var result: [String: Int] = [:]
        for (index, name) in tagNames.enumerated() {
            guard !name.isEmpty else { continue }
            if index < finderSidebarColorOrder.count {
                result[name] = finderSidebarColorOrder[index]
            }
        }
        return result
    }

    func loadTags() {
        var tagDict: [String: Int] = [:]

        let finderPrefs = readFinderTagPreferences()
        for (name, index) in finderPrefs {
            tagDict[name] = index
        }

        // Use fallback tags immediately; discover system tags in background
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

        // Discover system tags in background to avoid blocking main thread
        Task(priority: .utility) { @MainActor in
            let discovered = await Self.discoverSystemTagsBackground()
            guard !discovered.isEmpty else { return }
            var merged = [String: Int]()
            for tag in availableTags {
                merged[tag.name] = tag.colorIndex
            }
            for (name, index) in discovered {
                if merged[name] == nil {
                    merged[name] = index
                }
            }
            availableTags = merged.map { FinderTag(name: $0.key, colorIndex: $0.value) }
            availableTags.sort { ($0.colorIndex > 0 ? $0.colorIndex : 99) < ($1.colorIndex > 0 ? $1.colorIndex : 99) }
        }
    }

    private func discoverSystemTagNames() -> [(String, Int)] {
        var result: [String: Int] = [:]

        let dirs: [String] = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
            .flatMap { FileManager.default.urls(for: $0, in: .userDomainMask) }
            .map(\.path)

        for dir in dirs {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let path = (dir as NSString).appendingPathComponent(item)
                let tags = readTagsFromXattr(path: path)
                for (name, colorIdx) in tags {
                    if result[name] == nil || (result[name]! <= 1 && colorIdx > 1) {
                        result[name] = colorIdx
                    }
                }
            }
        }

        return result.sorted { $0.value < $1.value }
    }

    /// Non-isolated background discovery to avoid blocking main thread
    private static func discoverSystemTagsBackground() -> [(String, Int)] {
        var result: [String: Int] = [:]

        let dirs: [String] = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
            .flatMap { FileManager.default.urls(for: $0, in: .userDomainMask) }
            .map(\.path)

        for dir in dirs {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.prefix(200) {  // Limit to avoid long scans
                let path = (dir as NSString).appendingPathComponent(item)
                let xattrName = "com.apple.metadata:_kMDItemUserTags"
                let length = getxattr(path, xattrName, nil, 0, 0, 0)
                guard length > 0 else { continue }
                var buffer = [CChar](repeating: 0, count: length)
                let res = getxattr(path, xattrName, &buffer, length, 0, 0)
                guard res > 0 else { continue }
                let data = Data(bytes: buffer, count: res)
                guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] else { continue }
                for tagStr in plist {
                    let parts = tagStr.split(separator: "\n")
                    let name = String(parts[0])
                    let colorIdx = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    if result[name] == nil || (result[name]! <= 1 && colorIdx > 1) {
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

    var tagColorLookup: [String: Int] {
        Dictionary(uniqueKeysWithValues: availableTags.map { ($0.name, $0.colorIndex) })
    }

    func colorForTag(_ name: String) -> Color {
        tag(for: name)?.color ?? Color(red: 142/255, green: 142/255, blue: 147/255)
    }

    func displayNameForTag(_ name: String) -> String {
        tag(for: name)?.displayName ?? name
    }
}
