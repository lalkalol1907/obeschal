import AppKit
import SwiftUI

@main
struct ObeshchalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Обещал", systemImage: "checkmark.bubble") {
            Button("Новое обещание") { delegate.showCapture() }
            Button("Сегодня") {
                delegate.model.filter = .today
                delegate.showOverview()
            }
            Button("Все обещания") {
                delegate.model.filter = .all
                delegate.showOverview()
            }
            Divider()
            Button("Импортировать…") { delegate.showOverview(); delegate.model.importArchive() }
            Button("Экспортировать…") { delegate.showOverview(); delegate.model.exportArchive() }
            Divider()
            Button("Настройки…") { delegate.showSettings() }
                .keyboardShortcut(",")
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var capturePanel: CapturePanel?
    private var overviewWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var returnToOverview = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.onShowWindow = { [weak self] in self?.showCapture() }
        model.onShowOverview = { [weak self] in self?.showOverview() }
        model.onDismissWindow = { [weak self] in self?.hideActiveWindow() }
        model.onCaptureSizeChange = { [weak self] size in
            DispatchQueue.main.async { self?.resizeCapture(to: size) }
        }
        model.configureHotKey()
        showCapture()
    }

    func applicationDidBecomeActive(_ notification: Notification) { model.refreshDay() }

    func showCapture() {
        rememberPreviousApp()
        model.refreshDay()
        if capturePanel == nil {
            let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Новое обещание"
            panel.identifier = NSUserInterfaceItemIdentifier("obeshchal.capture")
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .utilityWindow
            panel.contentView = NSHostingView(rootView: QuickCaptureView(model: model))
            panel.delegate = self
            capturePanel = panel
        }
        guard let panel = capturePanel else { return }
        if !panel.isVisible {
            returnToOverview = overviewWindow?.isVisible == true
            center(panel)
        }
        overviewWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.activeSurface = .capture
        DispatchQueue.main.async { NotificationCenter.default.post(name: .obeshchalFocusInput, object: nil) }
    }

    func showOverview() {
        rememberPreviousApp()
        model.refreshDay()
        capturePanel?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        returnToOverview = false
        if overviewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Обещал"
            window.identifier = NSUserInterfaceItemIdentifier("obeshchal.overview")
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 660, height: 420)
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.delegate = self
            center(window)
            overviewWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        overviewWindow?.makeKeyAndOrderFront(nil)
        model.activeSurface = .overview
    }

    func showSettings() {
        rememberPreviousApp()
        capturePanel?.orderOut(nil)
        overviewWindow?.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Настройки «Обещал»"
            window.identifier = NSUserInterfaceItemIdentifier("obeshchal.settings")
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.delegate = self
            center(window)
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.activeSurface = .settings
    }

    private func hideActiveWindow() {
        switch model.activeSurface {
        case .capture:
            capturePanel?.orderOut(nil)
            if returnToOverview { showOverview(); return }
        case .overview: overviewWindow?.orderOut(nil)
        case .settings: settingsWindow?.orderOut(nil)
        }
        previousApp?.activate(options: [])
    }

    private func resizeCapture(to size: CGSize) {
        guard let panel = capturePanel, size.height.isFinite, size.height > 0 else { return }
        let height = max(220, size.height)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size = NSSize(width: 440, height: height)
        if let screen = panel.screen, frame.minY < screen.visibleFrame.minY {
            frame.origin.y = screen.visibleFrame.minY
        }
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private func rememberPreviousApp() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
    }

    private func center(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
            y: max(area.minY, area.midY - window.frame.height / 2)))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if sender === capturePanel, returnToOverview { showOverview() }
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === capturePanel { model.activeSurface = .capture }
        else if window === overviewWindow { model.activeSurface = .overview }
        else if window === settingsWindow { model.activeSurface = .settings }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
