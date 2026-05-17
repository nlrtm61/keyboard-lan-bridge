import CoreGraphics
import Foundation
import Network

public enum SenderInputMode: String {
    case local = "LOCAL"
    case remote = "REMOTE"
}

public enum SenderClientError: Error, CustomStringConvertible {
    case invalidReceiverURL
    case requestEncodingFailed
    case transportError(String)
    case invalidPort
    case invalidResponse
    case authRejected

    public var description: String {
        switch self {
        case .invalidReceiverURL:
            return "invalid receiver URL"
        case .requestEncodingFailed:
            return "failed to encode request JSON"
        case .transportError(let message):
            return "transport error: \(message)"
        case .invalidPort:
            return "invalid receiver port"
        case .invalidResponse:
            return "invalid receiver response"
        case .authRejected:
            return "receiver rejected credentials or source"
        }
    }
}

public final class SenderClient {
    private let config: SenderConfig
    private let logger: Logger
    private let sequenceQueue = DispatchQueue(label: "keyboard.bridge.sender.sequence")
    private var nextSequence: UInt64 = 1

    public init(config: SenderConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    public func sendManual(key: String?, keyCode: Int?, action: KeyAction, modifiers: [ModifierKey], completion: @escaping (Result<(Int, String), Error>) -> Void) {
        let inputSource = InputSourceManager.currentInputSource()
        let keyboardLayout = InputSourceManager.currentKeyboardLayout()
        let request = RemoteKeyRequest(
            token: config.sharedToken,
            key: key,
            keyCode: keyCode,
            action: action,
            modifiers: modifiers,
            source: Host.current().localizedName ?? "sender",
            sequence: nextRequestSequence(),
            senderInputSourceID: inputSource?.sourceID,
            senderInputModeID: inputSource?.inputModeID,
            senderKeyboardLayoutID: keyboardLayout?.sourceID
        )
        send(request: request, logSuccessResponse: false, completion: completion)
    }

    public func send(hotkey: SenderHotkey, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        let inputSource = InputSourceManager.currentInputSource()
        let keyboardLayout = InputSourceManager.currentKeyboardLayout()
        let request = RemoteKeyRequest(
            token: config.sharedToken,
            key: hotkey.sendKey,
            keyCode: hotkey.sendKeyCode,
            action: hotkey.action,
            modifiers: hotkey.modifiers,
            source: Host.current().localizedName ?? "sender",
            sequence: nextRequestSequence(),
            senderInputSourceID: inputSource?.sourceID,
            senderInputModeID: inputSource?.inputModeID,
            senderKeyboardLayoutID: keyboardLayout?.sourceID
        )
        send(request: request, logSuccessResponse: false, completion: completion)
    }

    public func sendKeyEvent(keyCode: CGKeyCode, action: KeyAction, modifiers: [ModifierKey], completion: @escaping (Result<(Int, String), Error>) -> Void) {
        let inputSource = InputSourceManager.currentInputSource()
        let keyboardLayout = InputSourceManager.currentKeyboardLayout()
        let request = RemoteKeyRequest(
            token: config.sharedToken,
            key: nil,
            keyCode: Int(keyCode),
            action: action,
            modifiers: modifiers,
            source: Host.current().localizedName ?? "sender",
            sequence: nextRequestSequence(),
            senderInputSourceID: inputSource?.sourceID,
            senderInputModeID: inputSource?.inputModeID,
            senderKeyboardLayoutID: keyboardLayout?.sourceID
        )
        send(request: request, logSuccessResponse: false, completion: completion)
    }

    public func releaseAll(completion: @escaping (Result<(Int, String), Error>) -> Void) {
        sendControl(path: "/v1/control/release-all", logSuccessResponse: false, completion: completion)
    }

    public func health(completion: @escaping (Result<(Int, String), Error>) -> Void) {
        sendRaw(method: "GET", path: "/health", body: nil, logSuccessResponse: false, completion: completion)
    }

    private func send(request payload: RemoteKeyRequest, logSuccessResponse: Bool, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        guard let _ = URL(string: "http://\(config.receiverHost):\(config.receiverPort)/v1/key") else {
            completion(.failure(SenderClientError.invalidReceiverURL))
            return
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(SenderClientError.requestEncodingFailed))
            return
        }
        let requestData = buildHTTPRequest(method: "POST", path: "/v1/key", body: body)
        sendRaw(requestData: requestData, logSuccessResponse: logSuccessResponse, completion: completion)
    }

    private func sendControl(path: String, logSuccessResponse: Bool, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        let body = Data("{\"token\":\"\(config.sharedToken)\"}".utf8)
        let requestData = buildHTTPRequest(method: "POST", path: path, body: body)
        sendRaw(requestData: requestData, logSuccessResponse: logSuccessResponse, completion: completion)
    }

    private func sendRaw(method: String, path: String, body: Data?, logSuccessResponse: Bool, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        let requestData = buildHTTPRequest(method: method, path: path, body: body)
        sendRaw(requestData: requestData, logSuccessResponse: logSuccessResponse, completion: completion)
    }

    private func sendRaw(requestData: Data, logSuccessResponse: Bool, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: config.receiverPort) else {
            completion(.failure(SenderClientError.invalidPort))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(config.receiverHost), port: port, using: .tcp)
        let queue = DispatchQueue(label: "keyboard.bridge.sender.http.\(nextRequestSequence())")
        let completionQueue = DispatchQueue(label: "keyboard.bridge.sender.http.completion")
        var completed = false

        func finish(_ result: Result<(Int, String), Error>) {
            completionQueue.sync {
                guard !completed else { return }
                completed = true
                connection.cancel()
                switch result {
                case .success(let value):
                    if self.config.logNetworkResponses && logSuccessResponse {
                        self.logger.info("receiver status=\(value.0) body=\(value.1)")
                    }
                case .failure:
                    break
                }
                completion(result)
            }
        }

        let timeoutWorkItem = DispatchWorkItem {
            finish(.failure(SenderClientError.transportError("request timed out")))
        }
        queue.asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: requestData, completion: .contentProcessed { error in
                    if let error = error {
                        timeoutWorkItem.cancel()
                        finish(.failure(SenderClientError.transportError(error.localizedDescription)))
                        return
                    }
                    self.receiveResponse(on: connection, accumulator: Data(), timeoutWorkItem: timeoutWorkItem, finish: finish)
                })
            case .failed(let error):
                timeoutWorkItem.cancel()
                finish(.failure(SenderClientError.transportError(error.localizedDescription)))
            case .waiting(let error):
                timeoutWorkItem.cancel()
                finish(.failure(SenderClientError.transportError(error.localizedDescription)))
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveResponse(
        on connection: NWConnection,
        accumulator: Data,
        timeoutWorkItem: DispatchWorkItem,
        finish: @escaping (Result<(Int, String), Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let error = error {
                timeoutWorkItem.cancel()
                finish(.failure(SenderClientError.transportError(error.localizedDescription)))
                return
            }

            var collected = accumulator
            if let data = data, !data.isEmpty {
                collected.append(data)
            }

            if isComplete {
                timeoutWorkItem.cancel()
                finish(self.parseHTTPResponse(collected))
                return
            }

            self.receiveResponse(on: connection, accumulator: collected, timeoutWorkItem: timeoutWorkItem, finish: finish)
        }
    }

    private func buildHTTPRequest(method: String, path: String, body: Data?) -> Data {
        var request = ""
        request += "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: \(config.receiverHost):\(config.receiverPort)\r\n"
        request += "X-Bridge-Token: \(config.sharedToken)\r\n"
        if let body = body {
            request += "Content-Type: application/json\r\n"
            request += "Content-Length: \(body.count)\r\n"
        } else {
            request += "Content-Length: 0\r\n"
        }
        request += "Connection: close\r\n\r\n"

        var data = Data(request.utf8)
        if let body = body {
            data.append(body)
        }
        return data
    }

    private func parseHTTPResponse(_ data: Data) -> Result<(Int, String), Error> {
        guard let text = String(data: data, encoding: .utf8),
              let separatorRange = text.range(of: "\r\n\r\n") else {
            return .failure(SenderClientError.invalidResponse)
        }

        let headerText = String(text[..<separatorRange.lowerBound])
        let bodyText = String(text[separatorRange.upperBound...])
        guard let firstLine = headerText.components(separatedBy: "\r\n").first else {
            return .failure(SenderClientError.invalidResponse)
        }

        let components = firstLine.split(separator: " ")
        guard components.count >= 2, let status = Int(components[1]) else {
            return .failure(SenderClientError.invalidResponse)
        }

        if status == 401 || status == 403 {
            return .failure(SenderClientError.authRejected)
        }
        return .success((status, bodyText))
    }

    private func nextRequestSequence() -> UInt64 {
        sequenceQueue.sync {
            let value = nextSequence
            nextSequence += 1
            return value
        }
    }
}

public final class SenderHotkeyMonitor {
    private let config: SenderConfig
    private let permissionStatus: PermissionStatus
    private let logger: Logger
    private let client: SenderClient
    private let networkQueue = DispatchQueue(label: "keyboard.bridge.sender.network")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled: Bool
    private let hotkeys: [(keyCode: CGKeyCode, definition: SenderHotkey)]
    private let toggleKeyCode: CGKeyCode?
    private let toggleModifiers: [ModifierKey]
    private let quitKeyCode: CGKeyCode?
    private let quitModifiers: [ModifierKey]
    private let modeChangeHandler: ((SenderInputMode) -> Void)?
    private let connectionStatusHandler: ((String) -> Void)?
    private var pendingReleaseAll = false

    public init(
        config: SenderConfig,
        permissionStatus: PermissionStatus,
        logger: Logger,
        modeChangeHandler: ((SenderInputMode) -> Void)? = nil,
        connectionStatusHandler: ((String) -> Void)? = nil
    ) throws {
        self.config = config
        self.permissionStatus = permissionStatus
        self.logger = logger
        self.client = SenderClient(config: config, logger: logger)
        self.enabled = config.enabledOnLaunch
        self.modeChangeHandler = modeChangeHandler
        self.connectionStatusHandler = connectionStatusHandler

        var resolvedHotkeys: [(keyCode: CGKeyCode, definition: SenderHotkey)] = []
        for hotkey in config.hotkeys {
            guard let triggerCode = KeyRegistry.keyCode(for: hotkey.triggerKey) else {
                throw NSError(domain: "SenderHotkeyMonitor", code: 1, userInfo: [NSLocalizedDescriptionKey: "unknown trigger key \(hotkey.triggerKey)"])
            }
            resolvedHotkeys.append((keyCode: triggerCode, definition: hotkey))
        }
        self.hotkeys = resolvedHotkeys
        self.toggleKeyCode = config.toggleHotkey.flatMap(KeyRegistry.keyCode(for:))
        self.toggleModifiers = config.toggleHotkeyModifiers
        self.quitKeyCode = config.quitHotkey.flatMap(KeyRegistry.keyCode(for:))
        self.quitModifiers = config.quitHotkeyModifiers
    }

    public func start() throws {
        try installEventTap()
        CFRunLoopRun()
    }

    public func startEmbedded() throws {
        try installEventTap()
    }

    public func currentMode() -> SenderInputMode {
        enabled ? .remote : .local
    }

    public func setMode(_ mode: SenderInputMode) {
        let shouldEnable = (mode == .remote)
        guard enabled != shouldEnable else { return }
        enabled = shouldEnable
        logger.warning("input mode \(mode.rawValue)")
        modeChangeHandler?(mode)
        if mode == .local {
            requestReleaseAllIfNeeded()
        }
    }

    private func installEventTap() throws {
        guard permissionStatus.isReady else {
            throw NSError(domain: "SenderHotkeyMonitor", code: 2, userInfo: [NSLocalizedDescriptionKey: "sender lacks Accessibility or listen-event permission"])
        }

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<SenderHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            throw NSError(domain: "SenderHotkeyMonitor", code: 3, userInfo: [NSLocalizedDescriptionKey: "failed to create event tap"])
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source

        logger.info("sender hotkey monitor started enabled=\(enabled)")
        if let toggleKeyCode = toggleKeyCode {
            logger.info("toggle forwarding key=\(KeyRegistry.keyName(for: toggleKeyCode) ?? "\(toggleKeyCode)") modifiers=\(toggleModifiers.map { $0.rawValue }.joined(separator: "+"))")
        }
        if let quitKeyCode = quitKeyCode {
            logger.info("quit key=\(KeyRegistry.keyName(for: quitKeyCode) ?? "\(quitKeyCode)") modifiers=\(quitModifiers.map { $0.rawValue }.joined(separator: "+"))")
        }
        modeChangeHandler?(currentMode())
    }

    public func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("event tap was disabled and has been re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat && !enabled {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if config.logVerboseEvents {
            logger.info("observed \(type) keyCode=\(keyCode) flags=\(event.flags.rawValue)")
        }

        if let toggleKeyCode = toggleKeyCode,
           type == .keyDown,
           keyCode == toggleKeyCode,
           modifiersMatch(required: toggleModifiers, actualFlags: event.flags) {
            setMode(enabled ? .local : .remote)
            return nil
        }

        if let quitKeyCode = quitKeyCode,
           type == .keyDown,
           keyCode == quitKeyCode,
           modifiersMatch(required: quitModifiers, actualFlags: event.flags) {
            logger.warning("quit hotkey received")
            stop()
            return nil
        }

        if enabled, type == .keyDown, let hotkey = matchedHotkey(for: keyCode, flags: event.flags) {
            logger.info("matched trigger key=\(hotkey.triggerKey) triggerModifiers=\(hotkey.triggerModifiers.map { $0.rawValue }.joined(separator: "+"))")
            networkQueue.async { [weak self] in
                self?.client.send(hotkey: hotkey) { result in
                    switch result {
                    case .success(let value):
                        let status = value.0
                        if !(200...299).contains(status) {
                            self?.logger.warning("receiver returned status \(status)")
                            self?.connectionStatusHandler?("HTTP \(status)")
                        } else {
                            self?.connectionStatusHandler?("OK")
                        }
                    case .failure(let error):
                        self?.logger.error("send failed: \(error)")
                        self?.connectionStatusHandler?("ERROR")
                    }
                }
            }
            return nil
        }

        guard enabled else {
            return Unmanaged.passUnretained(event)
        }

        guard let forwarded = forwardedEvent(for: type, keyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        networkQueue.async { [weak self] in
            self?.client.sendKeyEvent(keyCode: forwarded.keyCode, action: forwarded.action, modifiers: forwarded.modifiers) { result in
                switch result {
                case .success(let value):
                    let status = value.0
                    if !(200...299).contains(status) {
                        self?.logger.warning("receiver returned status \(status)")
                        self?.connectionStatusHandler?("HTTP \(status)")
                    } else {
                        self?.connectionStatusHandler?("OK")
                    }
                case .failure(let error):
                    self?.logger.error("send failed: \(error)")
                    self?.connectionStatusHandler?("ERROR")
                }
            }
        }

        return nil
    }

    private func forwardedEvent(for type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) -> (keyCode: CGKeyCode, action: KeyAction, modifiers: [ModifierKey])? {
        switch type {
        case .flagsChanged:
            guard let modifier = modifierKey(for: keyCode) else {
                return nil
            }
            let action: KeyAction = flags.contains(modifier.eventFlags) ? .down : .up
            return (keyCode: keyCode, action: action, modifiers: [])
        case .keyDown:
            if isToggleKeyCandidate(keyCode: keyCode) || isQuitKeyCandidate(keyCode: keyCode) {
                return nil
            }
            return (keyCode: keyCode, action: .down, modifiers: activeModifiers(from: flags))
        case .keyUp:
            if isToggleKeyCandidate(keyCode: keyCode) || isQuitKeyCandidate(keyCode: keyCode) {
                return nil
            }
            return (keyCode: keyCode, action: .up, modifiers: activeModifiers(from: flags))
        default:
            return nil
        }
    }

    private func matchedHotkey(for keyCode: CGKeyCode, flags: CGEventFlags) -> SenderHotkey? {
        for hotkey in hotkeys where hotkey.keyCode == keyCode {
            if modifiersMatch(required: hotkey.definition.triggerModifiers, actualFlags: flags) {
                return hotkey.definition
            }
        }
        return nil
    }

    private func modifiersMatch(required: [ModifierKey], actualFlags: CGEventFlags) -> Bool {
        for modifier in required {
            if !actualFlags.contains(modifier.eventFlags) {
                return false
            }
        }
        return true
    }

    private func activeModifiers(from flags: CGEventFlags) -> [ModifierKey] {
        ModifierKey.allCases.filter { flags.contains($0.eventFlags) }
    }

    private func modifierKey(for keyCode: CGKeyCode) -> ModifierKey? {
        ModifierKey.allCases.first(where: { $0.keyCode == keyCode })
    }

    private func isToggleKeyCandidate(keyCode: CGKeyCode) -> Bool {
        toggleKeyCode == keyCode
    }

    private func isQuitKeyCandidate(keyCode: CGKeyCode) -> Bool {
        quitKeyCode == keyCode
    }

    private func requestReleaseAllIfNeeded() {
        guard !pendingReleaseAll else { return }
        pendingReleaseAll = true
        networkQueue.async { [weak self] in
            self?.client.releaseAll { result in
                defer { self?.pendingReleaseAll = false }
                switch result {
                case .success:
                    self?.connectionStatusHandler?("OK")
                case .failure(let error):
                    self?.logger.error("release-all failed: \(error)")
                    self?.connectionStatusHandler?("ERROR")
                }
            }
        }
    }
}
