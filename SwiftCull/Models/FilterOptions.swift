import Foundation

enum RatingFilter: Int, CaseIterable, Identifiable {
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
        default: return String(repeating: "★", count: rawValue)
        }
    }
}

enum FileTypeFilter: String, CaseIterable, Identifiable {
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

enum SortOption: String, CaseIterable, Identifiable {
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

struct FilterOptions {
    var searchText: String = ""
    var ratingFilter: RatingFilter = .all
    var fileTypeFilter: FileTypeFilter = .all
    var tagFilter: String? = nil
    var sortOption: SortOption = .date
    var sortAscending: Bool = false
}
