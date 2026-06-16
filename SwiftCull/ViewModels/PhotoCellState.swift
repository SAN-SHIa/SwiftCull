import Foundation
import SwiftUI

/// 轻量级照片状态追踪器——单张变更不触发全列表重绘
/// 核心思路：将 Cell 级状态（选中/评分/标记）从 filteredPhotos 数组中剥离，
/// 改用独立的 @Published 字典，key=id，单张变更只触发对应 Cell 的 EquatableView 判断。
@MainActor
final class PhotoCellState: ObservableObject {
    /// 选中的照片 ID 集合（批量操作时整体替换）
    @Published private(set) var selectedIDs: Set<String> = []

    /// 单张照片的 workflowMark 快照（独立于 PhotoEntry，避免数组拷贝）
    @Published private(set) var marks: [String: PhotoWorkflowMark] = [:]

    /// 单张照片的 rating 快照
    @Published private(set) var ratings: [String: Int] = [:]

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setSelection(_ ids: Set<String>) {
        selectedIDs = ids
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    var selectionCount: Int { selectedIDs.count }

    // MARK: - Mark（批量操作时一次性写入）

    func getMark(_ id: String) -> PhotoWorkflowMark {
        marks[id] ?? .none
    }

    func setMark(_ id: String, mark: PhotoWorkflowMark) {
        marks[id] = mark
    }

    /// 批量写入 mark——一次赋值触发一次 objectWillChange
    func batchSetMarks(_ ids: Set<String>, mark: PhotoWorkflowMark) {
        for id in ids { marks[id] = mark }
    }

    // MARK: - Rating

    func getRating(_ id: String) -> Int {
        ratings[id] ?? 0
    }

    func setRating(_ id: String, rating: Int) {
        ratings[id] = rating
    }

    /// 批量写入 rating——一次赋值触发一次 objectWillChange
    func batchSetRatings(_ ids: Set<String>, rating: Int) {
        for id in ids { ratings[id] = rating }
    }

    // MARK: - 从 PhotoEntry 数组同步初始化

    func sync(from photos: [PhotoEntry]) {
        var newMarks: [String: PhotoWorkflowMark] = [:]
        var newRatings: [String: Int] = [:]
        for p in photos {
            if p.workflowMark != .none { newMarks[p.id] = p.workflowMark }
            if p.rating > 0 { newRatings[p.id] = p.rating }
        }
        marks = newMarks
        ratings = newRatings
    }
}

// MARK: - 批量操作防抖器

/// 将短时间内连续的批量操作合并为一次执行，避免高频 UI 重绘
@MainActor
final class BatchThrottler {
    private var pendingWork: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.08) {
        self.delay = delay
    }

    /// 提交一个批量操作，短时间内的后续调用会取消前一个
    func throttle(action: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { action() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancel() {
        pendingWork?.cancel()
        pendingWork = nil
    }
}
