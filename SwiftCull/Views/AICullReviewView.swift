import SwiftUI

/// AI 筛选审核视图
struct AICullReviewView: View {
    @ObservedObject var cullService: AICullService
    let photos: [PhotoEntry]
    let onApply: ([PhotoEntry]) -> Void
    let onCancel: () -> Void

    @State private var restoredIDs: Set<String> = []
    @State private var selectedRejectID: String?
    @State private var showDetail = false
    @Namespace private var animation

    private var rejectPhotos: [PhotoEntry] {
        photos.filter { photo in
            if restoredIDs.contains(photo.id) { return false }
            if let r = cullService.results[photo.id] { return r.verdict == .reject }
            return cullService.preRejects[photo.id] != nil
        }
    }

    private var passPhotos: [PhotoEntry] {
        photos.filter { photo in
            if let r = cullService.results[photo.id] { return r.verdict == .pass }
            return cullService.preRejects[photo.id] == nil && !restoredIDs.contains(photo.id)
        }
    }

    private var restoredPhotos: [PhotoEntry] {
        photos.filter { restoredIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)

            Divider()

            GeometryReader { geo in
                HStack(spacing: 0) {
                    rejectPanel
                        .frame(width: geo.size.width * 2 / 6)

                    Divider()

                    passPanel
                        .frame(width: geo.size.width * 4 / 6)
                }
            }

            Divider()

            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showDetail) {
            if let id = selectedRejectID,
               let photo = photos.first(where: { $0.id == id }) {
                RejectDetailView(
                    photo: photo,
                    reason: rejectReason(for: photo),
                    onRestore: {
                        withAnimation { _ = restoredIDs.insert(id) }
                        showDetail = false
                    },
                    onDismiss: { showDetail = false }
                )
            }
        }
    }

    // MARK: - 统计卡片

    private var statsBar: some View {
        HStack(spacing: 20) {
            statPill(icon: "photo.stack", count: cullService.totalCount, label: "总计", color: .primary)
            statPill(icon: "checkmark.circle.fill", count: passPhotos.count + restoredPhotos.count, label: "通过", color: .green)
            statPill(icon: "xmark.circle.fill", count: rejectPhotos.count, label: "废片", color: .red)
            statPill(icon: "arrow.uturn.backward.circle.fill", count: restoredIDs.count, label: "已恢复", color: .orange)

            Spacer()

            if !rejectPhotos.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("废片率")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(Int(Double(rejectPhotos.count) / Double(max(1, cullService.totalCount)) * 100))%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private func statPill(icon: String, count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 废片面板

    private var rejectPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("废片（\(rejectPhotos.count)）")
                    .font(.subheadline.bold())
                Spacer()
                if !rejectPhotos.isEmpty {
                    Button("全部恢复") {
                        withAnimation { _ = restoredIDs.formUnion(rejectPhotos.map(\.id)) }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if rejectPhotos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("没有废片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 10)], spacing: 10) {
                        ForEach(rejectPhotos) { photo in
                            RejectCard(photo: photo, reason: rejectReason(for: photo))
                                .matchedGeometryEffect(id: photo.id, in: animation)
                                .onTapGesture {
                                    selectedRejectID = photo.id
                                    showDetail = true
                                }
                                .contextMenu {
                                    Button("恢复此照片") {
                                        withAnimation { _ = restoredIDs.insert(photo.id) }
                                    }
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.red.opacity(0.02))
    }

    // MARK: - 通过面板

    private var passPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("通过（\(passPhotos.count + restoredPhotos.count)）")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)], spacing: 8) {
                    ForEach(passPhotos + restoredPhotos) { photo in
                        PassCard(photo: photo, isRestored: restoredIDs.contains(photo.id))
                            .matchedGeometryEffect(id: photo.id, in: animation)
                    }
                }
                .padding(12)
            }
        }
        .background(Color.green.opacity(0.015))
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack {
            Button("取消") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Text("标记 \(rejectPhotos.count) 张废片 · 保留 \(passPhotos.count + restoredPhotos.count) 张")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                var marked = photos
                for i in marked.indices {
                    let id = marked[i].id
                    if rejectPhotos.contains(where: { $0.id == id }) {
                        marked[i].workflowMark = .reject
                    } else {
                        marked[i].workflowMark = .pick
                    }
                }
                onApply(marked)
            } label: {
                Label("应用结果", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .frame(width: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.accentColor)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Helper

    private func rejectReason(for photo: PhotoEntry) -> String {
        if let r = cullService.results[photo.id] { return r.reason }
        return cullService.preRejects[photo.id] ?? "未知原因"
    }
}

// MARK: - 废片卡片

private struct RejectCard: View {
    let photo: PhotoEntry
    let reason: String
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottomLeading) {
                AsyncThumbnailView(photoId: photo.id, imagePath: photo.primaryImagePath, size: 220)
                    .aspectRatio(4/3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovering ? Color.red.opacity(0.7) : Color.red.opacity(0.3),
                                    lineWidth: isHovering ? 2 : 1)
                    )

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .shadow(color: .red.opacity(0.8), radius: 5)
                    .padding(5)
            }

            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(.red.opacity(0.1)))

            Text(photo.baseName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.smooth(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - 通过卡片

private struct PassCard: View {
    let photo: PhotoEntry
    let isRestored: Bool

    var body: some View {
        VStack(spacing: 3) {
            AsyncThumbnailView(photoId: photo.id, imagePath: photo.primaryImagePath, size: 140)
                .aspectRatio(4/3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRestored ? Color.orange.opacity(0.5) : Color.green.opacity(0.25), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isRestored {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(2)
                    }
                }

            Text(photo.baseName)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - 废片详情弹窗

private struct RejectDetailView: View {
    let photo: PhotoEntry
    let reason: String
    let onRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 大图预览（自适应窗口宽度）
            DetailThumbnailView(photo: photo, targetSize: 1800)
                .aspectRatio(3/2, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            // 废片原因
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .padding(.top, 16)

            // EXIF 信息
            if photo.exifInfo.hasAnyValue {
                let exif = photo.exifInfo
                HStack(spacing: 14) {
                    if let cam = exif.camera {
                        Label(cam, systemImage: "camera")
                    }
                    if let lens = exif.lens {
                        Label(lens, systemImage: "camera.aperture")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                HStack(spacing: 14) {
                    if let fl = exif.focalLength { Label(fl, systemImage: "ruler") }
                    if let f = exif.aperture { Label(f, systemImage: "f.circle") }
                    if let s = exif.shutterSpeed { Label(s, systemImage: "timer") }
                    if let iso = exif.iso { Label(iso, systemImage: "gauge.medium") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 12) {
                Button("关闭", action: onDismiss)
                    .keyboardShortcut(.cancelAction)

                Button { onRestore() } label: {
                    Label("恢复此照片", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.vertical, 16)
        }
        .frame(minWidth: 500, idealWidth: 620, minHeight: 500, idealHeight: 650)
        .background(.ultraThinMaterial)
    }
}
