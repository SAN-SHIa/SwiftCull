import SwiftUI

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
                Button("全选") {
                    store.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)
                Divider()
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

    @MainActor
    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = KeyboardShortcutHandler.setupMonitor(for: store)
    }
}
