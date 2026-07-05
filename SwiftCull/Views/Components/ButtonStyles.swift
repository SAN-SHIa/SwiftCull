import SwiftUI

struct SelectionIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var width: CGFloat = 34
    var height: CGFloat = 30
    var cornerRadius: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: width, height: height)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.85 : 0.58))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07), lineWidth: 0.7)
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct SelectionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .white : Color.secondary.opacity(0.55))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.78 : 0.94) : Color(nsColor: .controlBackgroundColor).opacity(0.58))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isEnabled ? .white.opacity(0.18) : Color.primary.opacity(0.06), lineWidth: 0.7)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct SelectionSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : Color.secondary.opacity(0.55))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.9 : 0.66))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08), lineWidth: 0.7)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct SelectionDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.red : Color.secondary.opacity(0.5))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.15 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.red.opacity(isEnabled ? 0.16 : 0.06), lineWidth: 0.7)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct InspectorActionButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .opacity(configuration.isPressed ? 0.72 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDestructive ? Color.red.opacity(0.16) : Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
