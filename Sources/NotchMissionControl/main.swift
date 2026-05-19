import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
private enum MainApp {
    static var delegate: AppDelegate?
}

@main
enum NotchMissionControlApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        MainApp.delegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusController: StatusController?
    private var mouseMonitor: MouseZoneMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trigger = MissionControlTrigger()
        let resolver = HitZoneResolver(settings: settings)
        let missionControlState = MissionControlStateDetector()

        mouseMonitor = MouseZoneMonitor(
            settings: settings,
            resolver: resolver,
            missionControlState: missionControlState,
            trigger: trigger
        )
        statusController = StatusController(
            settings: settings,
            monitor: mouseMonitor,
            trigger: trigger
        )
        mouseMonitor?.start()
    }
}

@MainActor
final class AppSettings {
    enum DisplayScope: String, CaseIterable {
        case allDisplays
        case builtInNotchOnly

        var title: String {
            switch self {
            case .allDisplays:
                return "All Displays"
            case .builtInNotchOnly:
                return "Built-in Notch Only"
            }
        }
    }

    enum HitZoneSize: String, CaseIterable {
        case precise
        case comfortable
        case wide

        var title: String {
            switch self {
            case .precise:
                return "Precise"
            case .comfortable:
                return "Comfortable"
            case .wide:
                return "Wide"
            }
        }

        var actualNotchPadding: CGFloat {
            switch self {
            case .precise:
                return 12
            case .comfortable:
                return 32
            case .wide:
                return 56
            }
        }

        var actualNotchHeight: CGFloat {
            switch self {
            case .precise:
                return 10
            case .comfortable:
                return 16
            case .wide:
                return 24
            }
        }

        var virtualWidth: CGFloat {
            switch self {
            case .precise:
                return 140
            case .comfortable:
                return 180
            case .wide:
                return 240
            }
        }

        var virtualHeight: CGFloat {
            switch self {
            case .precise:
                return 8
            case .comfortable:
                return 12
            case .wide:
                return 18
            }
        }
    }

    enum TriggerMethod: String, CaseIterable {
        case appFirst
        case keyboardOnly

        var title: String {
            switch self {
            case .appFirst:
                return "Mission Control.app First"
            case .keyboardOnly:
                return "Keyboard Shortcut Only"
            }
        }
    }

    private enum Key {
        static let enabled = "enabled"
        static let displayScope = "displayScope"
        static let hitZoneSize = "hitZoneSize"
        static let triggerMethod = "triggerMethod"
        static let cooldown = "cooldown"
        static let cooldownDefaultMigration = "cooldownDefaultMigration"
    }

    private static let defaultCooldown: TimeInterval = 0.25
    private static let previousDefaultCooldown: TimeInterval = 0.6

    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Key.enabled)
            onChange?()
        }
    }

    var displayScope: DisplayScope {
        didSet {
            defaults.set(displayScope.rawValue, forKey: Key.displayScope)
            onChange?()
        }
    }

    var hitZoneSize: HitZoneSize {
        didSet {
            defaults.set(hitZoneSize.rawValue, forKey: Key.hitZoneSize)
            onChange?()
        }
    }

    var triggerMethod: TriggerMethod {
        didSet {
            defaults.set(triggerMethod.rawValue, forKey: Key.triggerMethod)
            onChange?()
        }
    }

    var cooldown: TimeInterval {
        didSet {
            defaults.set(cooldown, forKey: Key.cooldown)
            onChange?()
        }
    }

    init() {
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        displayScope = DisplayScope(
            rawValue: defaults.string(forKey: Key.displayScope) ?? ""
        ) ?? .allDisplays
        hitZoneSize = HitZoneSize(
            rawValue: defaults.string(forKey: Key.hitZoneSize) ?? ""
        ) ?? .comfortable
        triggerMethod = TriggerMethod(
            rawValue: defaults.string(forKey: Key.triggerMethod) ?? ""
        ) ?? .appFirst

        if let storedCooldown = defaults.object(forKey: Key.cooldown) as? TimeInterval {
            let shouldMigratePreviousDefault = !defaults.bool(forKey: Key.cooldownDefaultMigration)
                && abs(storedCooldown - Self.previousDefaultCooldown) < 0.01
            cooldown = shouldMigratePreviousDefault ? Self.defaultCooldown : storedCooldown
        } else {
            cooldown = Self.defaultCooldown
        }

        defaults.set(cooldown, forKey: Key.cooldown)
        defaults.set(true, forKey: Key.cooldownDefaultMigration)
    }
}

struct HitZone {
    let id: String
    let rect: CGRect
    let isActualNotch: Bool

    func containsPointer(_ point: CGPoint) -> Bool {
        let topEdgeTolerance: CGFloat = 2
        let sideEdgeTolerance: CGFloat = 1

        return point.x >= rect.minX - sideEdgeTolerance
            && point.x <= rect.maxX + sideEdgeTolerance
            && point.y >= rect.minY
            && point.y <= rect.maxY + topEdgeTolerance
    }
}

@MainActor
final class HitZoneResolver {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func zones() -> [HitZone] {
        NSScreen.screens.compactMap { screen in
            zone(for: screen)
        }
    }

    private func zone(for screen: NSScreen) -> HitZone? {
        let frame = screen.frame
        let notch = actualNotchFrame(for: screen)

        if settings.displayScope == .builtInNotchOnly && notch == nil {
            return nil
        }

        let rect: CGRect
        let isActualNotch: Bool

        if let notch {
            let padding = settings.hitZoneSize.actualNotchPadding
            let height = max(settings.hitZoneSize.actualNotchHeight, min(notch.height, 36))
            rect = CGRect(
                x: notch.minX - padding,
                y: frame.maxY - height,
                width: notch.width + (padding * 2),
                height: height
            )
            isActualNotch = true
        } else {
            let width = settings.hitZoneSize.virtualWidth
            let height = settings.hitZoneSize.virtualHeight
            rect = CGRect(
                x: frame.midX - (width / 2),
                y: frame.maxY - height,
                width: width,
                height: height
            )
            isActualNotch = false
        }

        return HitZone(
            id: screen.displayIdentifier,
            rect: rect,
            isActualNotch: isActualNotch
        )
    }

    private func actualNotchFrame(for screen: NSScreen) -> CGRect? {
        guard
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let frame = screen.frame

        guard !left.isEmpty, !right.isEmpty, right.minX > left.maxX else {
            return nil
        }

        let gapWidth = right.minX - left.maxX
        guard gapWidth > 40 else {
            return nil
        }

        let safeTop = max(screen.safeAreaInsets.top, settings.hitZoneSize.actualNotchHeight)
        let height = min(max(safeTop, settings.hitZoneSize.actualNotchHeight), 40)

        return CGRect(
            x: left.maxX,
            y: frame.maxY - height,
            width: gapWidth,
            height: height
        )
    }
}

@MainActor
final class MouseZoneMonitor {
    private let settings: AppSettings
    private let resolver: HitZoneResolver
    private let missionControlState: MissionControlStateDetector
    private let trigger: MissionControlTrigger
    private var timer: Timer?
    private var zonesContainingPointer = Set<String>()
    private var lastTriggerDate = Date.distantPast
    private var missionControlOpeningGraceUntil = Date.distantPast
    private var missionControlWasActive = false

    init(
        settings: AppSettings,
        resolver: HitZoneResolver,
        missionControlState: MissionControlStateDetector,
        trigger: MissionControlTrigger
    ) {
        self.settings = settings
        self.resolver = resolver
        self.missionControlState = missionControlState
        self.trigger = trigger
        self.settings.onChange = { [weak self] in
            self?.zonesContainingPointer.removeAll()
        }
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollMouseLocation()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        zonesContainingPointer.removeAll()
        missionControlOpeningGraceUntil = .distantPast
        missionControlWasActive = false
    }

    func currentZonesDescription() -> String {
        resolver.zones()
            .map { zone in
                let kind = zone.isActualNotch ? "notch" : "virtual"
                return "\(zone.id) \(kind) \(Int(zone.rect.minX)),\(Int(zone.rect.minY)) \(Int(zone.rect.width))x\(Int(zone.rect.height))"
            }
            .joined(separator: "\n")
    }

    func triggerMissionControlNow() {
        markMissionControlOpening()
        lastTriggerDate = Date()
        trigger.trigger(method: settings.triggerMethod)
    }

    private func pollMouseLocation() {
        guard settings.enabled else {
            zonesContainingPointer.removeAll()
            missionControlOpeningGraceUntil = .distantPast
            missionControlWasActive = false
            return
        }

        let pointer = NSEvent.mouseLocation
        let zones = resolver.zones()
        let currentZoneIDs = Set(zones.filter { $0.containsPointer(pointer) }.map(\.id))

        if isMissionControlOpeningGraceActive() {
            zonesContainingPointer = currentZoneIDs
            return
        }

        if missionControlState.isActive() {
            missionControlWasActive = true
            zonesContainingPointer.removeAll()
            return
        }

        let justFinishedMissionControl = missionControlWasActive
        missionControlWasActive = false

        let enteredZoneIDs = currentZoneIDs.subtracting(zonesContainingPointer)

        zonesContainingPointer = currentZoneIDs

        guard !enteredZoneIDs.isEmpty else {
            return
        }

        let now = Date()
        guard justFinishedMissionControl || now.timeIntervalSince(lastTriggerDate) >= settings.cooldown else {
            return
        }

        lastTriggerDate = now
        markMissionControlOpening()
        trigger.trigger(method: settings.triggerMethod)
    }

    private func markMissionControlOpening() {
        missionControlOpeningGraceUntil = Date().addingTimeInterval(0.25)
    }

    private func isMissionControlOpeningGraceActive() -> Bool {
        Date() < missionControlOpeningGraceUntil
    }
}

final class MissionControlStateDetector {
    func isActive() -> Bool {
        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return false
        }

        return windowInfo.contains { info in
            guard
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                ownerName == "Dock",
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let width = bounds.cgFloatValue(for: "Width"),
                let height = bounds.cgFloatValue(for: "Height"),
                let layer = info[kCGWindowLayer as String] as? Int
            else {
                return false
            }

            return layer >= 0 && layer <= 30 && width >= 800 && height >= 500
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func cgFloatValue(for key: String) -> CGFloat? {
        if let value = self[key] as? CGFloat {
            return value
        }

        if let value = self[key] as? Double {
            return CGFloat(value)
        }

        if let value = self[key] as? Int {
            return CGFloat(value)
        }

        if let value = self[key] as? NSNumber {
            return CGFloat(truncating: value)
        }

        return nil
    }
}

@MainActor
final class MissionControlTrigger {
    private let missionControlURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    func trigger(method: AppSettings.TriggerMethod) {
        switch method {
        case .appFirst:
            if !NSWorkspace.shared.open(missionControlURL) {
                sendMissionControlShortcut(promptForAccessibility: false)
            }
        case .keyboardOnly:
            sendMissionControlShortcut(promptForAccessibility: false)
        }
    }

    func triggerNow(method: AppSettings.TriggerMethod) {
        trigger(method: method)
    }

    func promptForAccessibilityPermission() {
        sendMissionControlShortcut(promptForAccessibility: true)
    }

    private func sendMissionControlShortcut(promptForAccessibility: Bool) {
        if promptForAccessibility {
            let options = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let upArrowKeyCode = CGKeyCode(126)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: upArrowKeyCode,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: upArrowKeyCode,
            keyDown: false
        )

        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class StatusController: NSObject {
    private let settings: AppSettings
    private weak var monitor: MouseZoneMonitor?
    private let trigger: MissionControlTrigger
    private let statusItem: NSStatusItem

    init(
        settings: AppSettings,
        monitor: MouseZoneMonitor?,
        trigger: MissionControlTrigger
    ) {
        self.settings = settings
        self.monitor = monitor
        self.trigger = trigger
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        rebuildMenu()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.3.group",
                accessibilityDescription: "Notch Mission Control"
            )
            button.toolTip = "Notch Mission Control"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(
            title: "Enable Notch Mission Control",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = settings.enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        addDisplayScopeMenu(to: menu)
        addHitZoneMenu(to: menu)
        addCooldownMenu(to: menu)
        addTriggerMethodMenu(to: menu)

        menu.addItem(NSMenuItem.separator())

        let triggerNowItem = NSMenuItem(
            title: "Trigger Mission Control Now",
            action: #selector(triggerMissionControlNow),
            keyEquivalent: ""
        )
        triggerNowItem.target = self
        menu.addItem(triggerNowItem)

        let copyZonesItem = NSMenuItem(
            title: "Copy Hit Zone Debug Info",
            action: #selector(copyHitZoneDebugInfo),
            keyEquivalent: ""
        )
        copyZonesItem.target = self
        menu.addItem(copyZonesItem)

        let accessibilityItem = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addDisplayScopeMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for scope in AppSettings.DisplayScope.allCases {
            let scopeItem = NSMenuItem(
                title: scope.title,
                action: #selector(selectDisplayScope(_:)),
                keyEquivalent: ""
            )
            scopeItem.target = self
            scopeItem.representedObject = scope.rawValue
            scopeItem.state = settings.displayScope == scope ? .on : .off
            submenu.addItem(scopeItem)
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addHitZoneMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Hit Zone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for size in AppSettings.HitZoneSize.allCases {
            let sizeItem = NSMenuItem(
                title: size.title,
                action: #selector(selectHitZoneSize(_:)),
                keyEquivalent: ""
            )
            sizeItem.target = self
            sizeItem.representedObject = size.rawValue
            sizeItem.state = settings.hitZoneSize == size ? .on : .off
            submenu.addItem(sizeItem)
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addCooldownMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Cooldown", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let cooldowns: [(String, TimeInterval)] = [
            ("150 ms", 0.15),
            ("250 ms", 0.25),
            ("400 ms", 0.4),
            ("600 ms", 0.6),
            ("1000 ms", 1.0)
        ]

        for cooldown in cooldowns {
            let cooldownItem = NSMenuItem(
                title: cooldown.0,
                action: #selector(selectCooldown(_:)),
                keyEquivalent: ""
            )
            cooldownItem.target = self
            cooldownItem.representedObject = cooldown.1
            cooldownItem.state = abs(settings.cooldown - cooldown.1) < 0.01 ? .on : .off
            submenu.addItem(cooldownItem)
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addTriggerMethodMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Trigger Method", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for method in AppSettings.TriggerMethod.allCases {
            let methodItem = NSMenuItem(
                title: method.title,
                action: #selector(selectTriggerMethod(_:)),
                keyEquivalent: ""
            )
            methodItem.target = self
            methodItem.representedObject = method.rawValue
            methodItem.state = settings.triggerMethod == method ? .on : .off
            submenu.addItem(methodItem)
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    @objc
    private func toggleEnabled() {
        settings.enabled.toggle()
        rebuildMenu()
    }

    @objc
    private func selectDisplayScope(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let scope = AppSettings.DisplayScope(rawValue: rawValue)
        else {
            return
        }

        settings.displayScope = scope
        rebuildMenu()
    }

    @objc
    private func selectHitZoneSize(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let size = AppSettings.HitZoneSize(rawValue: rawValue)
        else {
            return
        }

        settings.hitZoneSize = size
        rebuildMenu()
    }

    @objc
    private func selectCooldown(_ sender: NSMenuItem) {
        guard let cooldown = sender.representedObject as? TimeInterval else {
            return
        }

        settings.cooldown = cooldown
        rebuildMenu()
    }

    @objc
    private func selectTriggerMethod(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let method = AppSettings.TriggerMethod(rawValue: rawValue)
        else {
            return
        }

        settings.triggerMethod = method
        rebuildMenu()
    }

    @objc
    private func triggerMissionControlNow() {
        if let monitor {
            monitor.triggerMissionControlNow()
        } else {
            trigger.triggerNow(method: settings.triggerMethod)
        }
    }

    @objc
    private func copyHitZoneDebugInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(monitor?.currentZonesDescription() ?? "No hit zones", forType: .string)
    }

    @objc
    private func requestAccessibilityPermission() {
        trigger.promptForAccessibilityPermission()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private extension NSScreen {
    var displayIdentifier: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "unknown-\(Int(frame.minX))-\(Int(frame.minY))"
        }

        return String(number.uint32Value)
    }
}
