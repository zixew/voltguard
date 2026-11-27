import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import VoltGuardData
import VoltGuardDomain

@main
struct VoltGuardApplication: App {
    @NSApplicationDelegateAdaptor(VoltGuardAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class VoltGuardAppDelegate: NSObject, NSApplicationDelegate, AppRouterProtocol, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var toastPanel: NSPanel?
    private var dashboardWindow: NSWindow?
    private var presenter: VoltGuardPresenter?
    private var cancellables = Set<AnyCancellable>()
    private var reopenObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingApps = NSRunningApplication.runningApplications(withBundleIdentifier: AppLayoutConstants.brandBundleID)
            .filter { $0.processIdentifier != currentPID }

        let gotLock = SingleInstanceGuard.shared.acquireLock()
        if !gotLock || !existingApps.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(DataConstants.Storage.reopenNotificationName),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            existingApps.first?.activate(options: [.activateAllWindows])
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(DataConstants.Storage.reopenNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.statusItem?.isVisible = true
                self?.openFullAppWindow()
            }
        }
        registerGlobalHotKey()

        let presenter = VoltGuardPresenter()
        presenter.router = self
        self.presenter = presenter

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            let iconView = MenuBarIconView(presenter: presenter)
            let hosting = NSHostingView(rootView: iconView)
            hosting.frame = NSRect(x: 0, y: 0, width: 84, height: AppLayoutConstants.menuBarHeight)
            button.addSubview(hosting)
            button.frame = hosting.frame
            button.action = #selector(handleStatusBarClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(presenter: presenter))
        self.popover = popover

        presenter.$state
            .map(\.settings.menuBarIcon)
            .removeDuplicates()
            .sink { [weak self] cfg in
                guard let self, let button = self.statusItem?.button else { return }
                let width: CGFloat = AppLayoutConstants.menuBarBaseWidth
                    + (cfg.showPercentage ? AppLayoutConstants.menuBarPercentageWidth : 0)
                    + (cfg.showWattage ? AppLayoutConstants.menuBarWattageWidth : 0)
                    + (cfg.showTemperature ? AppLayoutConstants.menuBarTemperatureWidth : 0)
                    + (cfg.showTimeRemaining ? AppLayoutConstants.menuBarETAWidth : 0)
                button.frame = NSRect(x: 0, y: 0, width: width, height: AppLayoutConstants.menuBarHeight)
                button.subviews.first?.frame = button.frame
            }
            .store(in: &cancellables)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.isVisible = true
        if !flag {
            openFullAppWindow()
        }
        return true
    }

    @objc private func handleStatusBarClick(_ sender: AnyObject?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusContextMenu()
            return
        }
        togglePopover(sender)
    }

    private func showStatusContextMenu() {
        guard let button = statusItem?.button, let presenter else { return }
        let locale = presenter.state.settings.locale
        let policy = presenter.state.settings.policy
        let menu = NSMenu()

        let limitMenuItem = NSMenuItem(title: "\(L10n.text(.chargeLimit, locale: locale)) (\(policy.limitPercent)%)", action: nil, keyEquivalent: "")
        let limitSubmenu = NSMenu()
        for preset in VoltGuardLimits.quickPresets {
            let item = NSMenuItem(title: "\(preset)%", action: #selector(menuSetChargeLimit(_:)), keyEquivalent: "")
            item.tag = preset
            item.state = policy.limitPercent == preset ? .on : .off
            item.target = self
            limitSubmenu.addItem(item)
        }
        limitMenuItem.submenu = limitSubmenu
        menu.addItem(limitMenuItem)

        let topUpItem = NSMenuItem(title: L10n.text(.topUp, locale: locale), action: #selector(menuToggleTopUp), keyEquivalent: "")
        topUpItem.state = policy.topUpActive ? .on : .off
        menu.addItem(topUpItem)

        let dischargeItem = NSMenuItem(title: L10n.text(.discharge, locale: locale), action: #selector(menuToggleDischarge), keyEquivalent: "")
        dischargeItem.state = policy.manualDischarge ? .on : .off
        menu.addItem(dischargeItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(.openFullApp, locale: locale), action: #selector(menuOpenFullApp), keyEquivalent: "o")
        menu.addItem(withTitle: L10n.text(.minimizeToBackground, locale: locale), action: #selector(menuMinimize), keyEquivalent: "m")
        menu.addItem(withTitle: L10n.text(.hideMenuBarIcon, locale: locale), action: #selector(menuHideIcon), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(.quit, locale: locale), action: #selector(menuQuit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuSetChargeLimit(_ sender: NSMenuItem) { presenter?.dispatch(.setChargeLimit(sender.tag)) }
    @objc private func menuToggleTopUp() { presenter?.dispatch(.toggleTopUp) }
    @objc private func menuToggleDischarge() { presenter?.dispatch(.toggleManualDischarge) }
    @objc private func menuOpenFullApp() { openFullAppWindow() }
    @objc private func menuMinimize() { minimizeToBackground() }
    @objc private func menuHideIcon() { setMenuBarIconVisible(false) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        presenter?.startPolling(activePopover: true)
    }

    func popoverDidClose(_ notification: Notification) {
        if dashboardWindow?.isVisible != true {
            presenter?.startPolling(activePopover: false)
        }
    }

    func openFullAppWindow() {
        statusItem?.isVisible = true
        popover?.performClose(nil)
        if dashboardWindow == nil, let presenter {
            let controller = NSHostingController(rootView: FullDashboardView(presenter: presenter))
            let window = NSWindow(contentViewController: controller)
            window.title = "VoltGuard"
            window.setContentSize(NSSize(width: AppLayoutConstants.fullWindowWidth, height: AppLayoutConstants.fullWindowHeight))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        presenter?.startPolling(activePopover: true)
    }

    func minimizeToBackground() {
        popover?.performClose(nil)
        dashboardWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        presenter?.startPolling(activePopover: false)
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        if !visible {
            minimizeToBackground()
        }
        statusItem?.isVisible = visible
    }

    func showToolbarEventToast() {
        guard let presenter, presenter.state.activeToolbarEvent != nil else { return }
        // If popover is already open, the interactive banner renders inline at the top of PopoverView.
        if popover?.isShown == true {
            hideToolbarEventToast()
            return
        }
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 78

        if toastPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentViewController = NSHostingController(rootView: ToolbarEventToastView(presenter: presenter))
            self.toastPanel = panel
        }

        guard let panel = toastPanel else { return }
        let targetOrigin: NSPoint = {
            if let button = statusItem?.button, let btnWin = button.window {
                let btnRectInWin = button.convert(button.bounds, to: nil)
                let screenRect = btnWin.convertToScreen(btnRectInWin)
                let x = min(max(screenRect.midX - (panelWidth / 2), 12), (NSScreen.main?.visibleFrame.maxX ?? 1400) - panelWidth - 12)
                let y = screenRect.minY - panelHeight - 8
                return NSPoint(x: x, y: y)
            }
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSPoint(x: screenFrame.maxX - panelWidth - 16, y: screenFrame.maxY - panelHeight - 10)
        }()

        panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + 8))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    func hideToolbarEventToast() {
        guard let panel = toastPanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
            }
        })
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        presenter?.startPolling(activePopover: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let reopenObserver {
            DistributedNotificationCenter.default().removeObserver(reopenObserver)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
        SingleInstanceGuard.shared.releaseLock()
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let delegate = Unmanaged<VoltGuardAppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    delegate.togglePopover(nil)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &hotKeyHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5647484B), id: 1) // VGHK
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
