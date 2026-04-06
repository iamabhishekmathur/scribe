import SwiftUI
import ScribeCore
import ScribeUI
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "App")

@main
struct ScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    init() {
        logger.info("ScribeApp init started")
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        MainWindowController.shared.setup(appState: state)
        logger.info("ScribeApp init complete, MainWindowController setup done")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(state: appState.recordingState)
        }
    }
}
