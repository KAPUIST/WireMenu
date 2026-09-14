import AppKit
import QuartzCore
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // ponytail: opacity matched to the native menu on macOS 26; recheck after OS appearance changes.
    static let menuBarSymbolColor = NSColor(name: nil) { appearance in
        var color = NSColor.textColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.textColor.withAlphaComponent(0.95)
        }
        return color
    }
    private let logger = Logger(subsystem: "local.taegwonson.WireMenu", category: "status")
    private var statusItem: NSStatusItem!
    private let networkMonitor = NetworkMonitor()
    private let panelModel = NetworkPanelModel()
    private var panel: NetworkMenuPanel?
    private var dismissingPanel: NetworkMenuPanel?
    private var sizeObservation: NSKeyValueObservation?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application launched")
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position WireMenu": 250])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "WireMenu"
        statusItem.isVisible = true
        configureStatusItem()
        panelModel.onSignalChange = { [weak self] in self?.updateStatusImage() }
        setStatusImage(
            NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "연결 확인 중…"),
            toolTip: "연결 확인 중…"
        )
        networkMonitor.onChange = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        networkMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        networkMonitor.stop()
        closePanel()
    }

    private func configureStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "WireMenu"
    }

    private func showPanel() {
        dismissingPanel?.orderOut(nil)
        dismissingPanel = nil
        guard let maximumFrame = panelFrame(height: .greatestFiniteMagnitude), maximumFrame.height > 0 else { return }
        panelModel.refresh()
        let controller = NSHostingController(rootView: NetworkPanelView(model: panelModel, maximumHeight: maximumFrame.height))
        controller.sizingOptions = [.preferredContentSize]
        let panel = NetworkMenuPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        let container = NSViewController()
        container.addChild(controller)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 18
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 18
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.contentView = controller.view
            container.view = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .menu
            material.blendingMode = .behindWindow
            material.state = .active
            let mask = NSImage(size: NSSize(width: 37, height: 37), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
            material.maskImage = mask
            material.addSubview(controller.view)
            controller.view.autoresizingMask = [.width, .height]
            container.view = material
        }
        panel.contentViewController = container
        panel.delegate = self
        self.panel = panel
        sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] controller, _ in
            self?.positionPanel(size: controller.preferredContentSize)
        }
        positionPanel(size: controller.view.fittingSize)
        NSApp.activate(ignoringOtherApps: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        panel.makeFirstResponder(controller.view)
        statusItem.button?.highlight(true)
        panelModel.startTrafficMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, panel.attachedSheet == nil { self.closePanel(); return nil }
                if event.window === panel, panel.attachedSheet == nil,
                   event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                   [UInt16(123), 124, 125, 126, 36, 49].contains(event.keyCode) {
                    NotificationCenter.default.post(name: MenuNavigation.keyNotification, object: event.keyCode)
                    return nil
                }
            } else if event.window !== panel, event.window !== panel.attachedSheet,
                      event.window !== self.statusItem.button?.window {
                self.closePanel()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func positionPanel(size: NSSize) {
        guard let panel, size.height > 0, let frame = panelFrame(height: size.height) else { return }
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true, animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel.invalidateShadow()
    }

    private func panelFrame(height: CGFloat) -> NSRect? {
        guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return nil }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        return MenuPanelLayout.frame(anchor: anchor, visibleFrame: screen.visibleFrame, contentHeight: height)
    }

    @objc private func screenParametersChanged() { closePanel() }

    private func closePanel() {
        sizeObservation = nil
        statusItem?.button?.highlight(false)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        let closingPanel = panel
        panel = nil
        closingPanel?.delegate = nil
        panelModel.stopTrafficMonitoring(clearHistory: false)
        guard let closingPanel else { return }
        dismissingPanel = closingPanel
        closingPanel.ignoresMouseEvents = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            closingPanel.orderOut(nil)
            dismissingPanel = nil
            panelModel.stopTrafficMonitoring()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                closingPanel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                closingPanel.orderOut(nil)
                guard let self, self.dismissingPanel === closingPanel else { return }
                self.dismissingPanel = nil
                self.panelModel.stopTrafficMonitoring()
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        if panel?.attachedSheet == nil { closePanel() }
    }

    private func apply(_ snapshot: ConnectionSnapshot) {
        logger.notice("Connection changed: \(snapshot.kind.title, privacy: .public), interface: \(snapshot.interfaceName ?? "none", privacy: .public)")
        panelModel.updateConnection(snapshot)
        panelModel.refreshSignalStrength()
        updateStatusImage()
    }

    private func updateStatusImage() {
        let kind = panelModel.connection.kind
        let image = NSImage(systemSymbolName: kind.systemSymbolName,
                            variableValue: kind == .wifi ? panelModel.currentSignalStrength : 1,
                            accessibilityDescription: kind.title)
        setStatusImage(image, toolTip: kind.title)
    }

    private func setStatusImage(_ image: NSImage?, toolTip: String) {
        guard let button = statusItem.button else { return }
        // Keep the SF Symbol's optical proportions instead of stretching it into a square.
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.preferringMonochrome())
            .applying(.init(paletteColors: [Self.menuBarSymbolColor]))
        let symbol = image?.withSymbolConfiguration(configuration) ?? image
        // Template tinting makes SF Symbols too faint in an inactive menu bar.
        symbol?.isTemplate = false
        button.image = symbol
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
    }

    @objc private func togglePopover() {
        if panel != nil { closePanel() }
        else { showPanel() }
    }
}

enum MenuPanelLayout {
    static func frame(anchor: NSRect, visibleFrame: NSRect, contentHeight: CGFloat) -> NSRect {
        let width: CGFloat = 308
        let top = min(anchor.minY, visibleFrame.maxY)
        let height = min(max(0, contentHeight), max(0, top - visibleFrame.minY - 8))
        let x = min(max(anchor.maxX - width, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}

private final class NetworkMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
