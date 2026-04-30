import SwiftUI

struct RatingView: View {
    let rating: Int
    let onRatingChange: (Int) -> Void
    let showClear: Bool

    init(rating: Int, onRatingChange: @escaping (Int) -> Void, showClear: Bool = true) {
        self.rating = rating
        self.onRatingChange = onRatingChange
        self.showClear = showClear
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onRatingChange(rating == star ? 0 : star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(0.32))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(star <= rating ? "点击清除评分" : "评分 \(star) 星")
            }

            if rating > 0 {
                Text("\(rating) 星")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("未评分")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if showClear && rating > 0 {
                Button {
                    onRatingChange(0)
                } label: {
                    Image(systemName: "star.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("清除评分")
            }
        }
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    private var finderTag: FinderTag? {
        FinderTagService.shared.tag(for: tag)
    }

    var body: some View {
        HStack(spacing: 3) {
            if let ft = finderTag {
                Circle()
                    .fill(ft.color)
                    .frame(width: 7, height: 7)
            }

            Text(finderTag?.displayName ?? tag)
                .font(.caption2.weight(.medium))

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tagBackgroundColor, in: Capsule())
        .overlay(Capsule().stroke(tagStrokeColor, lineWidth: 0.5))
    }

    private var tagBackgroundColor: Color {
        if let ft = finderTag {
            return ft.color.opacity(0.14)
        }
        return Color.accentColor.opacity(0.14)
    }

    private var tagStrokeColor: Color {
        if let ft = finderTag {
            return ft.color.opacity(0.2)
        }
        return Color.accentColor.opacity(0.2)
    }
}
