import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary.opacity(0.7))

                Text("SwiftCull")
                    .font(.title.weight(.bold))

                if store.errorMessage != nil {
                    Text(store.errorMessage!)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    Text("打开一个包含照片的文件夹开始浏览")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                store.selectPath()
            } label: {
                Label("打开文件夹", systemImage: "folder.badge.plus")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !store.detectedVolumes.isEmpty {
                VStack(spacing: 10) {
                    Text("快速访问")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)

                    ForEach(store.detectedVolumes) { volume in
                        Button {
                            store.sourcePath = volume.path
                            Task {
                                await store.loadPhotos()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: volume.icon)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(volume.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(volume.path)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360)
            }

            Text("⌘O 随时打开文件夹")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ShortcutGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("↑ ↓ ← →", "按网格位置选择照片"),
        ("拖拽框选", "鼠标框选多张照片"),
        ("Space", "Quick Look 预览"),
        ("E", "网格视图 / 详情视图切换"),
        ("Tab", "切换侧边栏"),
        ("1-5", "设置评分"),
        ("0", "清除评分"),
        ("Delete", "删除所选照片"),
        ("A", "全选当前筛选结果"),
        ("⌘O", "打开文件夹")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("快捷键手册", systemImage: "keyboard")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut, action in
                    GridRow {
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(action)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

struct ToolbarInfoView: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        if store.selectedCount > 1 {
            Text("已选 \(store.selectedCount) / \(store.totalPhotoCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(store.photoCount) / \(store.totalPhotoCount) 张照片")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoSinglePreviewView: View {
    let photo: PhotoEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            DetailThumbnailView(photo: photo, targetSize: 1800)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                Text(photo.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(photo.fileTypeBadge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(photo.fileTypeBadgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(photo.fileTypeBadgeColor.opacity(0.14), in: Capsule())

                Spacer()

                Text(photo.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(14)
        }
    }
}
