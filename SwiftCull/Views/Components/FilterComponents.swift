import SwiftUI

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 1.5, y: 1)
    }
}

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TagFilterChip: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        color ?? .accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? accentColor : (color ?? .secondary))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SortChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
