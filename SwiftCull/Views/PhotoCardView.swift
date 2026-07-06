import SwiftUI

struct SelectablePhotoCardView: View {
    let photo: PhotoEntry
    let gridSize: CGFloat
    let isSelected: Bool
    let isPrimary: Bool
    let isSelectMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            cardImage
            infoBar
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(cardBorder)
    }

    private var cardImage: some View {
        ZStack {
            AsyncThumbnailView(
                photoId: photo.id,
                imagePath: photo.primaryFilePath,
                size: gridSize,
                isVideo: photo.isVideoOnly
            )
            .frame(width: gridSize, height: gridSize)

            badgeOverlay

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
