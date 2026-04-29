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
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onRatingChange(rating == star ? 0 : star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(star <= rating ? "点击清除评分" : "评分 \(star) 星")
            }

            if rating > 0 {
                Text("\(rating) 星")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("未评分")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if showClear && rating > 0 {
                Button {
                    onRatingChange(0)
                } label: {
                    Image(systemName: "star.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
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
                    .frame(width: 8, height: 8)
            }

            Text(finderTag?.displayName ?? tag)
                .font(.caption)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tagBackgroundColor)
        .clipShape(Capsule())
    }

    private var tagBackgroundColor: Color {
        if let ft = finderTag {
            return ft.color.opacity(0.15)
        }
        return Color.accentColor.opacity(0.15)
    }
}
