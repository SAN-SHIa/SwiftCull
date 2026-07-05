import SwiftUI

struct PhotoEntry: Identifiable, Hashable, Sendable {
    let id: String
    let baseName: String
    let jpgPath: String?
    let nefPath: String?
    let movPath: String?
    let jpgFileSize: Int64?
    let nefFileSize: Int64?
    let movFileSize: Int64?
    let fileDate: Date
    let modificationDate: Date
    var rating: Int
    var tags: [String]
    var isDeleted: Bool

    init(baseName: String, jpgPath: String?, nefPath: String?, movPath: String?,
         jpgFileSize: Int64?, nefFileSize: Int64?, movFileSize: Int64?, fileDate: Date, modificationDate: Date) {
        self.id = baseName
        self.baseName = baseName
        self.jpgPath = jpgPath
        self.nefPath = nefPath
        self.movPath = movPath
        self.jpgFileSize = jpgFileSize
        self.nefFileSize = nefFileSize
        self.movFileSize = movFileSize
        self.fileDate = fileDate
        self.modificationDate = modificationDate
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
        formattedCaptureDate
    }

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var formattedCaptureDate: String {
        Self.displayDateFormatter.string(from: fileDate)
    }

    var formattedModificationDate: String {
        Self.displayDateFormatter.string(from: modificationDate)
    }

    var primaryImagePath: String {
        jpgPath ?? nefPath ?? ""
    }

    var primaryFilePath: String {
        jpgPath ?? nefPath ?? movPath ?? ""
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
