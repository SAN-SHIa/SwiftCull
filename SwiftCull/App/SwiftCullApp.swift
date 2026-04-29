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
        }
    }

    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isEmpty else { return event }

            if Self.isQuickLookVisible {
                if event.keyCode == 49 {
                    QuickLookHelper.shared.closePanel()
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 49: // Space
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
                store.navigateToNext()
                return nil
            case 126: // Up
                store.navigateToPrevious()
                return nil
            case 123: // Left
                store.navigateToPrevious()
                return nil
            case 124: // Right
                store.navigateToNext()
                return nil
            case 51: // Delete / Backspace
                if Self.isTextFieldFocused { return event }
                store.requestDeleteSelected()
                return nil
            default:
                break
            }

            if let chars = event.characters, chars == "a" {
                if Self.isTextFieldFocused { return event }
                store.selectAll()
                return nil
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
