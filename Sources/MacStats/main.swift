import AppKit

// UI layer: app entry point. Mac Stats is a menu bar app with no Dock icon (LSUIElement).
MainActor.assumeIsolated {
    // Only one instance may run; a second launch shows Settings in the first one and quits.
    SingleInstance.quitIfAlreadyRunning()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
