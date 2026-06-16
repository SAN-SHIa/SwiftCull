import SwiftUI

struct SelectablePhotoCardView: View {
    let photo: PhotoEntry
    let gridSize: CGFloat
    let isSelected: Bool
    let isPrimary: Bool
    let isSelectMode: Bool
    @EnvironmentObject var store: PhotoStore

    /// 定时刷新的分析状态，避免每次 analyzedPhotos 变化都重绘全部卡片
    @State private var isScanningThisCard = false

    var body: some View {
        VStack(spacing: 0) {
            cardImage
            infoBar
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(cardBorder)
        .onAppear { updateScanningState() }
        .task(id: store.aiCullService.isAnalyzing) {
            // 分析进行中时，每 1500ms 刷新一次扫描状态，进一步降低批量重绘频率
            while store.aiCullService.isAnalyzing && !Task.isCancelled {
                updateScanningState()
                try? await Task.sleep(for: .milliseconds(1500))
            }
            isScanningThisCard = false
        }
    }

    private func updateScanningState() {
        let svc = store.aiCullService
        isScanningThisCard = svc.isAnalyzing && !svc.analyzedPhotos.contains(photo.id)
    }

    private var cardImage: some View {
        let analyzing = store.aiCullService.isAnalyzing
        return ZStack {
            AsyncThumbnailView(
                photoId: photo.id,
                imagePath: photo.primaryFilePath,
                size: gridSize,
                isVideo: photo.isVideoOnly
            )
            .frame(width: gridSize, height: gridSize)

            if !analyzing {
                badgeOverlay

                // AI 废片遮罩（暗角 + 原因标签）
                if let aiResult = photo.aiResult, aiResult.verdict == .reject {
                    AIResultBadge(result: aiResult)
                        .frame(width: gridSize, height: gridSize)
                }
            }

            // 分析中扫描线（使用节流后的状态，避免高频重绘）
            if isScanningThisCard {
                AIScanningOverlay()
                    .frame(width: gridSize, height: gridSize)
            }

            if !analyzing {
                // 星级标记（右下角，不遮挡画面主体）
                if photo.rating > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(String(repeating: "★", count: photo.rating))
                                .font(.system(size: min(10, gridSize * 0.07), weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                                .padding(3)
                        }
                    }
                }

                if isSelected && !isPrimary {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                }

                if isSelectMode {
                    selectCheckOverlay
                }
            }
        }
        .frame(width: gridSize, height: gridSize)
        .clipped()
    }

    private var selectCheckOverlay: some View {
        VStack {
            HStack {
                Spacer()
                selectCheck
            }
            Spacer()
        }
        .padding(4)
    }

    private var selectCheck: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.black.opacity(0.4))
                .frame(width: 20, height: 20)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var badgeOverlay: some View {
        VStack {
            HStack {
                topLeftBadge
                Spacer()
                if !isSelectMode {
                    topRightBadge
                }
            }
            Spacer()
        }
        .padding(4)
    }

    private var cardBackground: Color {
        if isPrimary { return Color.accentColor.opacity(0.15) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        return Color.clear
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(
                isPrimary ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.5) : Color.clear),
                lineWidth: isPrimary ? 2 : 1
            )
    }

    private var topLeftBadge: some View {
        Group {
            if photo.hasAnyMark {
                HStack(spacing: 3) {
                    if photo.workflowMark != .none {
                        workflowBadge
                    }
                    if photo.rating > 0 {
                        ratingBadge
                    }
                    ForEach(photo.tags.prefix(3), id: \.self) { tagName in
                        Circle()
                            .fill(FinderTagService.shared.colorForTag(tagName))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
            }
        }
    }

    private var workflowBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: photo.workflowMark == .pick ? "flag.fill" : "xmark")
                .font(.system(size: 8, weight: .bold))
            Text(photo.workflowMark == .pick ? "P" : "X")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(photo.workflowMark == .pick ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
        .clipShape(Capsule())
    }

    private var ratingBadge: some View {
        HStack(spacing: 1) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("\(photo.rating)")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.9))
        .clipShape(Capsule())
    }

    private var topRightBadge: some View {
        Text(photo.fileTypeBadge)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(photo.fileTypeBadgeColor.opacity(0.85))
            .clipShape(Capsule())
    }

    private var infoBar: some View {
        VStack(spacing: 2) {
            Text(photo.displayName)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Text(photo.formattedCaptureDate)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)

                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: gridSize)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}
