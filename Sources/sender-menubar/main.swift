import AppKit
import Foundation
import KeyboardLANBridgeCore

private let logger = Logger(subsystem: "sender-menubar")

private func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var modeItem: NSMenuItem?
    private var receiverItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var connectivityItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var monitor: SenderHotkeyMonitor?
    private var client: SenderClient?
    private var timer: Timer?
    private var permissionsDescription = "Permissions: UNKNOWN"
    private var connectivityDescription = "Receiver: UNKNOWN"
    private var currentMode: SenderInputMode = .local
    private let configPath: String
    private var loadedConfig: SenderConfig?

    init(configPath: String) {
        self.configPath = configPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startMonitor()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "KBD LOCAL"

        let menu = NSMenu()
        let modeItem = NSMenuItem(title: "Mode: LOCAL", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)

        let receiverItem = NSMenuItem(title: "Receiver: UNKNOWN", action: nil, keyEquivalent: "")
        receiverItem.isEnabled = false
        menu.addItem(receiverItem)

        let permissionItem = NSMenuItem(title: "Permissions: UNKNOWN", action: nil, keyEquivalent: "")
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        let connectivityItem = NSMenuItem(title: "Health: UNKNOWN", action: nil, keyEquivalent: "")
        connectivityItem.isEnabled = false
        menu.addItem(connectivityItem)

        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: "Switch to REMOTE", action: #selector(toggleMode), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let configItem = NSMenuItem(title: "Config: \(configPath)", action: nil, keyEquivalent: "")
        configItem.isEnabled = false
        menu.addItem(configItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Sender Menu Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.modeItem = modeItem
        self.receiverItem = receiverItem
        self.permissionItem = permissionItem
        self.connectivityItem = connectivityItem
        self.toggleItem = toggleItem
    }

    private func startMonitor() {
        do {
            let config = try ConfigLoader.loadSenderConfig(path: configPath)
            loadedConfig = config
            let prompt = config.promptForPermissionsOnLaunch
            let permissions = PermissionDiagnostics.inspect(role: .sender, prompt: prompt)
            permissions.lines.forEach { logger.info($0) }
            permissionsDescription = "Permissions: \(permissions.isReady ? "READY" : "MISSING")"
            permissionItem?.title = permissionsDescription
            receiverItem?.title = "Receiver: \(config.receiverHost):\(config.receiverPort)"
            client = SenderClient(config: config, logger: logger)

            let monitor = try SenderHotkeyMonitor(
                config: config,
                permissionStatus: permissions,
                logger: logger,
                modeChangeHandler: { [weak self] mode in
                    DispatchQueue.main.async {
                        self?.updateMode(mode)
                    }
                },
                connectionStatusHandler: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.updateConnectivity(status)
                    }
                }
            )
            try monitor.startEmbedded()
            self.monitor = monitor
            updateMode(monitor.currentMode())
            startConnectivityPolling()
        } catch {
            logger.error("\(error)")
            statusItem?.button?.title = "KBD ERROR"
            modeItem?.title = "Mode: ERROR"
        }
    }

    private func updateMode(_ mode: SenderInputMode) {
        currentMode = mode
        statusItem?.button?.title = "KBD \(mode.rawValue)"
        modeItem?.title = "Mode: \(mode.rawValue)"
        toggleItem?.title = mode == .local ? "Switch to REMOTE" : "Switch to LOCAL"
    }

    private func updateConnectivity(_ value: String) {
        connectivityDescription = "Health: \(value)"
        connectivityItem?.title = connectivityDescription
    }

    private func startConnectivityPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.probeHealth()
        }
        probeHealth()
    }

    private func probeHealth() {
        client?.health { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    self?.updateConnectivity("OK (\(value.0))")
                case .failure:
                    self?.updateConnectivity("ERROR")
                }
            }
        }
    }

    @objc
    private func toggleMode() {
        let next: SenderInputMode = currentMode == .local ? .remote : .local
        monitor?.setMode(next)
    }

    @objc
    private func quitApp() {
        timer?.invalidate()
        monitor?.stop()
        NSApp.terminate(nil)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let configPath = argumentValue("--config", in: arguments) ?? "./configs/sender.local.json"

let app = NSApplication.shared
private let delegate = AppDelegate(configPath: configPath)
app.delegate = delegate
app.run()
