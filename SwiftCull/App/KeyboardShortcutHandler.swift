import SwiftUI
import Quartz

/// 全局键盘快捷键监控处理
enum KeyboardShortcutHandler {

    static func setupMonitor(for store: PhotoStore) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommandModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)

            if isQuickLookVisible {
                if event.keyCode == 49 {
                    QuickLookHelper.shared.closePanel()
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 49: // Space
                guard !hasCommandModifier else { return event }
                if let photo = store.selectedPhoto {
                    let path = photo.primaryImagePath
                    if !path.isEmpty {
                        QuickLookHelper.shared.preview(URL(fileURLWithPath: path))
                    } else if let movPath = photo.movPath {
                        QuickLookHelper.shared.preview(URL(fileURLWithPath: movPath))
                    }
                    return nil
                }
            case 125: // Down
                guard !hasCommandModifier, !isTextFieldFocused else { return event }
                store.navigateDown()
                return nil
            case 126: // Up
                guard !hasCommandModifier, !isTextFieldFocused else { return event }
                store.navigateUp()
                return nil
            case 123: // Left
                guard !hasCommandModifier, !isTextFieldFocused else { return event }
                store.navigateLeft()
                return nil
            case 124: // Right
                guard !hasCommandModifier, !isTextFieldFocused else { return event }
                store.navigateRight()
                return nil
            case 48: // Tab
                guard !hasCommandModifier, !isTextFieldFocused else { return event }
                store.toggleSidebar()
                return nil
            case 51: // Delete / Backspace
                guard !hasCommandModifier else { return event }
                if isTextFieldFocused { return event }
                store.requestDeleteSelected()
                return nil
            case 117: // Forward Delete
                guard !hasCommandModifier else { return event }
                if isTextFieldFocused { return event }
                store.requestDeleteSelected()
                return nil
            case 53: // ESC
                if store.isSelectMode {
                    store.cancelSelectMode()
                    return nil
                }
                return event
            default:
                break
            }

            guard !hasCommandModifier, !isTextFieldFocused else { return event }

            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "1", "2", "3", "4", "5":
                    if let rating = Int(chars) {
                        if store.selectedCount > 1 {
                            store.batchSetRating(rating)
                            return nil
                        } else if let photo = store.selectedPhoto {
                            store.setRating(rating, for: photo)
                            return nil
                        } else {
                            return event
                        }
                    }
                case "0":
                    if store.selectedCount > 1 {
                        store.batchClearRating()
                        return nil
                    } else if let photo = store.selectedPhoto {
                        store.setRating(0, for: photo)
                        return nil
                    }
                case "e":
                    store.toggleSinglePreview()
                    return nil
                case "a":
                    store.selectAll()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    static var isTextFieldFocused: Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        if firstResponder is NSText { return true }
        if firstResponder is NSTextField { return true }
        if let view = firstResponder as? NSView {
            if view is NSTextView { return true }
            var current: NSView? = view.superview
            while let parent = current {
                if parent is NSTextField { return true }
                current = parent.superview
            }
        }
        return false
    }

    static var isQuickLookVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }
}
