import SwiftUI
import Quartz

/// 全局键盘快捷键监控处理
enum KeyboardShortcutHandler {

    @MainActor
    static func setupMonitor(for store: PhotoStore) -> Any? {
        // 本地按键监视器的回调在主线程被调用。NSEvent 非 Sendable，故先在此提取
        // 出所需的可发送原始值，再进入 MainActor 隔离上下文处理，返回是否吞掉该事件。
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommandModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
            let chars = event.charactersIgnoringModifiers?.lowercased()

            let consumed = MainActor.assumeIsolated {
                handleKey(keyCode: keyCode, hasCommandModifier: hasCommandModifier, chars: chars, store: store)
            }
            return consumed ? nil : event
        }
    }

    /// 返回 true 表示事件被消费（吞掉），false 表示放行
    @MainActor
    private static func handleKey(keyCode: UInt16, hasCommandModifier: Bool, chars: String?, store: PhotoStore) -> Bool {
        if isQuickLookVisible {
            if keyCode == 49 {
                QuickLookHelper.shared.closePanel()
                return true
            }
            return false
        }

        switch keyCode {
        case 49: // Space
            guard !hasCommandModifier else { return false }
            if let photo = store.selectedPhoto {
                let path = photo.primaryImagePath
                if !path.isEmpty {
                    QuickLookHelper.shared.preview(URL(fileURLWithPath: path))
                } else if let movPath = photo.movPath {
                    QuickLookHelper.shared.preview(URL(fileURLWithPath: movPath))
                }
                return true
            }
        case 125: // Down
            guard !hasCommandModifier, !isTextFieldFocused else { return false }
            store.navigateDown()
            return true
        case 126: // Up
            guard !hasCommandModifier, !isTextFieldFocused else { return false }
            store.navigateUp()
            return true
        case 123: // Left
            guard !hasCommandModifier, !isTextFieldFocused else { return false }
            store.navigateLeft()
            return true
        case 124: // Right
            guard !hasCommandModifier, !isTextFieldFocused else { return false }
            store.navigateRight()
            return true
        case 48: // Tab
            guard !hasCommandModifier, !isTextFieldFocused else { return false }
            store.toggleSidebar()
            return true
        case 51: // Delete / Backspace
            guard !hasCommandModifier else { return false }
            if isTextFieldFocused { return false }
            store.requestDeleteSelected()
            return true
        case 117: // Forward Delete
            guard !hasCommandModifier else { return false }
            if isTextFieldFocused { return false }
            store.requestDeleteSelected()
            return true
        case 53: // ESC
            if isTextFieldFocused {
                NSApp.keyWindow?.makeFirstResponder(nil)
                return true
            }
            if store.isSelectMode {
                store.cancelSelectMode()
                return true
            }
            return false
        default:
            break
        }

        guard !hasCommandModifier, !isTextFieldFocused else { return false }

        if let chars {
            switch chars {
            case "1", "2", "3", "4", "5":
                if let rating = Int(chars) {
                    if store.selectedCount > 1 {
                        store.batchSetRating(rating)
                        return true
                    } else if let photo = store.selectedPhoto {
                        store.setRating(rating, for: photo)
                        return true
                    } else {
                        return false
                    }
                }
            case "0":
                if store.selectedCount > 1 {
                    store.batchClearRating()
                    return true
                } else if let photo = store.selectedPhoto {
                    store.setRating(0, for: photo)
                    return true
                }
            case "e":
                store.toggleSinglePreview()
                return true
            case "q":
                if store.isSelectMode {
                    store.confirmSelectMode()
                    return true
                }
                return false
            case "a":
                store.selectAll()
                return true
            default:
                break
            }
        }

        return false
    }

    @MainActor
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

    @MainActor
    static var isQuickLookVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }
}
