import Foundation

// MARK: - Sidecar Data Model

struct PhotoMetadata: Codable, Sendable {
    var rating: Int?
}

struct ProjectMetadataFile: Codable {
    static let currentVersion = 1
    let version: Int
    var updatedAt: Date
    var entries: [String: PhotoMetadata]
}

// MARK: - Service

final class ProjectMetadataService: @unchecked Sendable {
    static let shared = ProjectMetadataService()

    private let fileName = "metadata.json"
    private let folderName = ".swiftcull"
    private let saveDelay: TimeInterval = 2.0
    private var pendingWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.swiftcull.project-metadata", qos: .utility)
    private var cachedFolderPath: String?
    private var cachedFileURL: URL?

    private init() {}

    // MARK: - Path Helpers

    private func sidecarDirectoryURL(for folderPath: String) -> URL {
        URL(fileURLWithPath: folderPath).appendingPathComponent(folderName, isDirectory: true)
    }

    private func sidecarFileURL(for folderPath: String) -> URL {
        sidecarDirectoryURL(for: folderPath).appendingPathComponent(fileName)
    }

    // MARK: - Load

    func load(from folderPath: String) -> [String: PhotoMetadata] {
        cachedFolderPath = folderPath
        cachedFileURL = sidecarFileURL(for: folderPath)

        guard let url = cachedFileURL else { return [:] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder.iso8601Decoder.decode(ProjectMetadataFile.self, from: data)
            return file.entries
        } catch {
            print("[ProjectMetadata] 读取失败: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Save (debounced)

    func scheduleSave(entries: [String: PhotoMetadata], folderPath: String) {
        cachedFolderPath = folderPath
        cachedFileURL = sidecarFileURL(for: folderPath)

        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow(entries: entries, folderPath: folderPath)
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func saveNow(entries: [String: PhotoMetadata], folderPath: String) {
        let dirURL = sidecarDirectoryURL(for: folderPath)
        let fileURL = sidecarFileURL(for: folderPath)

        do {
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }

            let file = ProjectMetadataFile(
                version: ProjectMetadataFile.currentVersion,
                updatedAt: Date(),
                entries: entries
            )
            let data = try JSONEncoder.iso8601Encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ProjectMetadata] 写入失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON Encoder/Decoder Helpers

private extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
