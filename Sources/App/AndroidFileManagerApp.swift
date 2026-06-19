import SwiftUI

@main
struct AndroidFileManagerApp: App {
    @State private var deviceManager = DeviceManager()
    @State private var fileBrowser = FileBrowser()
    @State private var clipboardManager = ClipboardManager()
    @State private var searchManager = SearchManager()
    @State private var transferManager = TransferManager()

    var body: some Scene {
        WindowGroup {
            ContentView(
                deviceManager: deviceManager,
                fileBrowser: fileBrowser,
                clipboardManager: clipboardManager,
                searchManager: searchManager,
                transferManager: transferManager
            )
            .task {
                if let window = NSApp.windows.first(where: { $0.title.isEmpty || $0.title == "AndroidFileManager" }) {
                    window.title = "安卓文件小助理"
                    window.setFrameAutosaveName("AndroidFileManagerMainWindow")
                }
                // 清理上次 crash/force-quit 残留的临时文件
                ADBService.cleanupStaleTempFiles()

                // Wire up manager references
                clipboardManager.fileBrowser = fileBrowser
                searchManager.fileBrowser = fileBrowser
                fileBrowser.searchManager = searchManager
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

