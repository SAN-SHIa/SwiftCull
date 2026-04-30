import SwiftUI
import Quartz

@main
struct SwiftCullApp: App {
    @StateObject private var store = PhotoStore()
    @State private var eventMonitor: Any?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    setupKeyboardMonitor()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹...") {
                    store.selectPath()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("照片") {
                Button("评分 1 星") {
                    if let photo = store.selectedPhoto { store.setRating(1, for: photo) }
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("评分 2 星") {
                    if let photo = store.selectedPhoto { store.setRating(2, for: photo) }
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("评分 3 星") {
                    if let photo = store.selectedPhoto { store.setRating(3, for: photo) }
                }
                .keyboardShortcut("3", modifiers: .command)
                Button("评分 4 星") {
                    if let photo = store.selectedPhoto { store.setRating(4, for: photo) }
                }
                .keyboardShortcut("4", modifiers: .command)
                Button("评分 5 星") {
                    if let photo = store.selectedPhoto { store.setRating(5, for: photo) }
                }
                .keyboardShortcut("5", modifiers: .command)
                Divider()
                Button("清除评分") {
                    if let photo = store.selectedPhoto { store.setRating(0, for: photo) }
                }
                .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("移至废纸篓") {
                    if let photo = store.selectedPhoto { store.requestDelete(photo) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandMenu("帮助") {
                Button("快捷键手册") {
                    store.showingShortcutGuide = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }

    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommandModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)

            if Self.isQuickLookVisible {
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
                guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }
                store.navigateDown()
                return nil
            case 126: // Up
                guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }
                store.navigateUp()
                return nil
            case 123: // Left
                guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }
                store.navigateLeft()
                return nil
            case 124: // Right
                guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }
                store.navigateRight()
                return nil
            case 48: // Tab
                guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }
                store.toggleSidebar()
                return nil
            case 51: // Delete / Backspace
                guard !hasCommandModifier else { return event }
                if Self.isTextFieldFocused { return event }
                store.requestDeleteSelected()
                return nil
            default:
                break
            }

            guard !hasCommandModifier, !Self.isTextFieldFocused else { return event }

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

    private static var isTextFieldFocused: Bool {
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

    private static var isQuickLookVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }
}
