import AppKit
import Combine
import SwiftUI
import GridCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store = SettingsStore.shared
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboarding: OnboardingModel?
    private static let onboardingDoneKey = "onboardingCompleted"
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        overlay = OverlayController(store: store)
        setUpStatusItem()

        overlay.onNeedsPermission = { [weak self] in self?.showOnboarding(at: .accessibility) }
        GlobalHotKey.shared.onPress = { [weak self] in self?.overlay.hotKeyPressed() }
        store.$config.map(\.launchKey).removeDuplicates().sink { combo in
            let ok = GlobalHotKey.shared.register(combo)
            if !ok { NSLog("Grid: could not register \(combo.displayString)") }
            NotificationCenter.default.post(name: .hotKeyRegistrationChanged, object: ok)
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.overlay.hide() }
            .store(in: &cancellables)

        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            return snapshot(to: CommandLine.arguments[i + 1])
        }
        #endif

        if !UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) {
            showOnboarding(at: .welcome)
        } else if !WindowManager.isTrusted {
            // Typically after reinstalling a new build: go straight to the permission step.
            showOnboarding(at: .accessibility)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Grid")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = NSMenuItem(title: "Show Grid", action: #selector(showGrid), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hint = NSMenuItem(title: "Shortcut: \(store.config.launchKey.displayString)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        if !WindowManager.isTrusted {
            let ax = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            ax.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            ax.target = self
            menu.addItem(ax)
        }
        let guide = NSMenuItem(title: "Setup Guide…", action: #selector(openSetupGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Grid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func showGrid() {
        // Let the menu finish closing so focus returns to the previous app first.
        DispatchQueue.main.async { self.overlay.show() }
    }

    @objc private func grantAccess() {
        showOnboarding(at: .accessibility)
    }

    @objc private func openSetupGuide() {
        showOnboarding(at: .welcome)
    }

    // MARK: Onboarding

    func showOnboarding(at step: OnboardingStep) {
        if let window = onboardingWindow, let onboarding {
            onboarding.step = step
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = OnboardingModel(startAt: step)
        let host = NSHostingController(rootView: OnboardingView(model: model, store: store) { [weak self] in
            self?.openSettings()
        })
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Grid"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        model.onTrustGranted = { [weak window] in
            // Bring the guide back in front of System Settings once access is on.
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        model.onStepChange = { [weak window] step in
            // Float during "Try it" so the guide stays visible while another app is focused.
            window?.level = step == .tryIt ? .floating : .normal
        }
        model.onFinish = { [weak window] in window?.close() }

        onboarding = model
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboardingWindow else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        onboardingWindow = nil
        onboarding = nil
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store) { [weak self] in
                self?.showOnboarding(at: .accessibility)
            })
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Grid Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 540, height: 720))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    private func snapshot(to dir: String) {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            func write(_ rep: NSBitmapImageRep?, _ name: String) {
                try? rep?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
            if let view = self.settingsWindow?.contentView?.superview {
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                if let rep { view.cacheDisplay(in: view.bounds, to: rep) }
                write(rep, "settings.png")
            }
            write(self.overlay.debugSnapshot(), "overlay.png")
            self.snapshotEditor(write: write)
            self.settingsWindow?.close()
            self.snapshotOnboarding(OnboardingStep.allCases, to: dir, write: write)
        }
    }

    private func snapshotEditor(write: @escaping (NSBitmapImageRep?, String) -> Void) {
        let editor = ShortcutEditor(draft: store.config.shortcuts[1], isNew: false, existing: store.config.shortcuts) { _ in }
        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                write(rep, "editor.png")
            }
            window.close()
        }
    }

    private func snapshotOnboarding(_ steps: [OnboardingStep], to dir: String, write: @escaping (NSBitmapImageRep?, String) -> Void) {
        guard let step = steps.first else { return NSApp.terminate(nil) }
        showOnboarding(at: step)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let view = self.onboardingWindow?.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                write(rep, "onboarding-\(step.rawValue)-\(step).png")
            }
            self.snapshotOnboarding(Array(steps.dropFirst()), to: dir, write: write)
        }
    }
    #endif

    /// Accessory apps still need an Edit menu so ⌘C / ⌘V / ⌘A work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Grid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
