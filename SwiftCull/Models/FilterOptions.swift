import Foundation

enum RatingFilter: Int, CaseIterable, Identifiable, Sendable {
    case all = -1
    case unrated = 0
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .unrated: return "未评分"
        default: return "\(rawValue)★"
        }
    }
}

enum FileTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case jpgOnly = "jpg"
    case nefOnly = "nef"
    case jpgAndNef = "both"
    case movOnly = "mov"
    case hasMov = "hasMov"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .jpgOnly: return "仅 JPG"
        case .nefOnly: return "仅 RAW"
        case .jpgAndNef: return "RAW + JPG"
        case .movOnly: return "仅 MOV"
        case .hasMov: return "含 MOV"
        }
    }
}

enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case date = "date"
    case name = "name"
    case rating = "rating"
    case size = "size"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .date: return "时间"
        case .name: return "文件名"
        case .rating: return "评分"
        case .size: return "大小"
        }
    }
}

enum DatePreset: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        case .custom: return "自定义"
        }
    }

    var dateRange: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .yesterday:
            let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
            return (cal.startOfDay(for: yesterday), cal.date(bySettingHour: 23, minute: 59, second: 59, of: yesterday)!)
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
            return (start, now)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))!
            return (start, now)
        case .custom:
            return nil
        }
    }
}

struct FilterOptions: Sendable {
    var searchText: String = ""
    var ratingFilter: RatingFilter = .all
    var fileTypeFilter: FileTypeFilter = .all
    var tagFilter: String? = nil
    var sortOption: SortOption = .date
    var sortAscending: Bool = false
    var startDate: Date? = nil
    var endDate: Date? = nil
    var dateFilterEnabled: Bool = false
    var activePreset: DatePreset? = nil

    var exportFileNameSuffix: String {
        var parts: [String] = []

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if ratingFilter != .all {
            parts.append(ratingFilter.displayName.replacingOccurrences(of: "★", with: "星"))
        }

        if fileTypeFilter != .all {
            parts.append(fileTypeFilter.displayName)
        }

        if let tag = tagFilter {
            parts.append("标签-\(tag)")
        }

        parts.append(sortOption.displayName)

        let suffix = parts.isEmpty ? "全部" : parts.joined(separator: "_")
        return suffix.replacingOccurrences(of: " ", with: "")
    }
}
