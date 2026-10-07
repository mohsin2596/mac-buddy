import AppKit
import Combine
import SwiftUI

// MARK: - Window & input

final class BuddyHostingView: NSHostingView<BuddyView> {
    var onClick: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var downLocation = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false

    required init(rootView: BuddyView) {
        super.init(rootView: rootView)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        downLocation = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downLocation.x
        let dy = p.y - downLocation.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onDragEnd?() } else { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = BuddySettings()
    private lazy var model = BuddyModel(settings: settings)
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var timers: [Timer] = []
    private var settingsObserver: AnyCancellable?
    private var targetAlpha: CGFloat = 1
    private let originKey = "buddyOrigin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let host = BuddyHostingView(rootView: BuddyView(model: model, settings: settings))
        host.sizingOptions = []
        host.onClick = { [weak self] in self?.model.poke() }
        host.onDragEnd = { [weak self] in self?.saveOrigin() }
        host.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: scaledSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.contentView = host
        panel.setFrameOrigin(restoredOrigin() ?? defaultOrigin())
        applyWindowSettings()
        panel.orderFrontRegardless()

        // Settings publish before they change; apply on the next runloop turn.
        settingsObserver = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWindowSettings() }

        model.refresh()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.refresh() }
            },
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
        ]
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: Per-frame work

    private func tick() {
        let f = panel.frame
        let s = settings.scale
        let mouse = NSEvent.mouseLocation

        if settings.followCursor {
            let eye = CGPoint(x: f.minX + BuddyLayout.eyeCenter.x * s, y: f.minY + BuddyLayout.eyeCenter.y * s)
            model.cursorLook = lookOffset(dx: mouse.x - eye.x, dy: eye.y - mouse.y, reach: 150 * s)
        }

        // Optionally fade out while Claude is idle (but never while you're editing settings).
        let idle = model.mood == .idle || model.mood == .sleeping
        let hidden = settings.hideWhenIdle && idle && model.activePhrase(at: Date()) == nil
            && !(settingsWindow?.isVisible ?? false)
        let alpha: CGFloat = hidden ? 0 : 1
        if alpha != targetAlpha {
            targetAlpha = alpha
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = alpha
            }
        }

        // Only the character itself catches the mouse; the transparent rest lets clicks through.
        let r = BuddyLayout.hitRect
        let hit = NSRect(x: f.minX + r.minX * s, y: f.minY + r.minY * s, width: r.width * s, height: r.height * s)
        let ignore = hidden || !hit.contains(mouse)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    // MARK: Window settings

    private var scaledSize: CGSize {
        CGSize(width: BuddyLayout.window.width * settings.scale, height: BuddyLayout.window.height * settings.scale)
    }

    private func applyWindowSettings() {
        let size = scaledSize
        let old = panel.frame
        if old.size != size {
            // Grow/shrink around the buddy's feet so it stays put.
            panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY,
                                  width: size.width, height: size.height), display: true)
            saveOrigin()
        }
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = settings.allSpaces
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.ignoresCycle]
    }

    // MARK: Position

    private func defaultOrigin() -> NSPoint {
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: screen.maxX - scaledSize.width - 20, y: screen.minY)
    }

    private func restoredOrigin() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: originKey) else { return nil }
        let origin = NSPointFromString(s)
        let frame = NSRect(origin: origin, size: scaledSize)
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? origin : nil
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
    }

    @objc private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: originKey)
        panel.setFrameOrigin(defaultOrigin())
    }

    // MARK: Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, model: model) { [weak self] in self?.resetPosition() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Mac Buddy Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // Show in the Dock and app switcher while the settings window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menus

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Say Hi 👋", action: #selector(sayHi), keyEquivalent: "").target = self
        let follow = menu.addItem(withTitle: "Eyes Follow Cursor", action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = settings.followCursor ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mac Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    /// Needed so ⌘C/⌘V/⌘W/⌘Q work in the settings window.
    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Mac Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Mac Buddy", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        NSApp.mainMenu = main
    }

    @objc private func sayHi() { model.poke() }
    @objc private func toggleFollow() { settings.followCursor.toggle() }
}

// MARK: - Entry point

@main
enum MacBuddyApp {
    @MainActor static let delegate = AppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
