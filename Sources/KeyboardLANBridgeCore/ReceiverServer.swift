import Carbon
import CoreGraphics
import Foundation
import Network

public struct ReceiverRunOptions {
    public let dryRun: Bool

    public init(dryRun: Bool) {
        self.dryRun = dryRun
    }
}

public struct InjectionResult {
    public let posted: Bool
    public let message: String
}

public struct ReceiverControlRequest: Codable {
    public var token: String?
}

private struct PressedKey: Hashable {
    let keyCode: CGKeyCode
}

private final class ReceiverState {
    private let queue = DispatchQueue(label: "keyboard.bridge.receiver.state")
    private var enabled: Bool = true
    private var pressedKeys: Set<PressedKey> = []

    func isEnabled() -> Bool {
        queue.sync { enabled }
    }

    func setEnabled(_ value: Bool) {
        queue.sync {
            enabled = value
        }
    }

    func keyDown(_ keyCode: CGKeyCode) {
        _ = queue.sync {
            pressedKeys.insert(PressedKey(keyCode: keyCode))
        }
    }

    func keyUp(_ keyCode: CGKeyCode) {
        _ = queue.sync {
            pressedKeys.remove(PressedKey(keyCode: keyCode))
        }
    }

    func allPressedKeyCodes() -> [CGKeyCode] {
        queue.sync { pressedKeys.map(\.keyCode) }
    }

    func resetPressedKeys() {
        queue.sync {
            pressedKeys.removeAll()
        }
    }

    func pressedKeyCount() -> Int {
        queue.sync { pressedKeys.count }
    }
}

public final class KeyEventInjector {
    private let dryRun: Bool
    private let permissionStatus: PermissionStatus
    private let state: ReceiverState
    private let config: ReceiverConfig

    fileprivate init(dryRun: Bool, permissionStatus: PermissionStatus, state: ReceiverState, config: ReceiverConfig) {
        self.dryRun = dryRun
        self.permissionStatus = permissionStatus
        self.state = state
        self.config = config
    }

    public func inject(_ event: ResolvedKeyEvent) -> InjectionResult {
        if dryRun {
            return InjectionResult(
                posted: false,
                message: "dry-run accepted keyCode=\(event.keyCode) action=\(event.action.rawValue)"
            )
        }

        guard permissionStatus.isReady else {
            return InjectionResult(
                posted: false,
                message: "receiver lacks Accessibility or post-event permission"
            )
        }

        if let specialResult = handleCapsLockIfNeeded(event) {
            return specialResult
        }

        let source = CGEventSource(stateID: .hidSystemState)

        switch event.action {
        case .tap:
            postModifiers(event.modifiers, isKeyDown: true, source: source)
            postKey(keyCode: event.keyCode, isKeyDown: true, flags: [], source: source)
            postKey(keyCode: event.keyCode, isKeyDown: false, flags: [], source: source)
            postModifiers(event.modifiers.reversed(), isKeyDown: false, source: source)
        case .down:
            postKey(keyCode: event.keyCode, isKeyDown: true, flags: flags(for: event.modifiers), source: source)
            state.keyDown(event.keyCode)
        case .up:
            postKey(keyCode: event.keyCode, isKeyDown: false, flags: flags(for: event.modifiers), source: source)
            state.keyUp(event.keyCode)
        }

        return InjectionResult(
            posted: true,
            message: "posted keyCode=\(event.keyCode) action=\(event.action.rawValue)"
        )
    }

    public func releaseAll() -> InjectionResult {
        if dryRun {
            state.resetPressedKeys()
            return InjectionResult(posted: false, message: "dry-run released all keys")
        }

        guard permissionStatus.isReady else {
            return InjectionResult(posted: false, message: "receiver lacks Accessibility or post-event permission")
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let pressedKeys = state.allPressedKeyCodes()
        for keyCode in pressedKeys {
            postKey(keyCode: keyCode, isKeyDown: false, flags: [], source: source)
        }
        state.resetPressedKeys()
        return InjectionResult(posted: true, message: "released \(pressedKeys.count) pressed keys")
    }

    private func postModifiers<S: Sequence>(_ modifiers: S, isKeyDown: Bool, source: CGEventSource?) where S.Element == ModifierKey {
        for modifier in modifiers {
            postKey(keyCode: modifier.keyCode, isKeyDown: isKeyDown, flags: [], source: source)
        }
    }

    private func handleCapsLockIfNeeded(_ event: ResolvedKeyEvent) -> InjectionResult? {
        guard event.keyCode == CGKeyCode(kVK_CapsLock) else {
            return nil
        }

        switch config.capsLockBehavior {
        case .passThrough:
            return nil
        case .toggleLatinAndJapanese:
            guard event.action == .down || event.action == .tap else {
                return InjectionResult(posted: true, message: "ignored caps-lock keyUp after input source toggle")
            }
            let result = InputSourceManager.toggleLatinAndJapanese(
                preferredJapaneseInputSourceID: config.preferredJapaneseInputSourceID,
                preferredLatinInputSourceID: config.preferredLatinInputSourceID
            )
            return InjectionResult(posted: true, message: result)
        }
    }

    private func flags(for modifiers: [ModifierKey]) -> CGEventFlags {
        modifiers.reduce([]) { partial, modifier in
            partial.union(modifier.eventFlags)
        }
    }

    private func postKey(keyCode: CGKeyCode, isKeyDown: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isKeyDown) else {
            return
        }
        if !flags.isEmpty {
            event.flags = flags
        }
        event.post(tap: .cghidEventTap)
    }
}

public final class ReceiverServer {
    private let config: ReceiverConfig
    private let options: ReceiverRunOptions
    private let logger: Logger
    private let listenerQueue = DispatchQueue(label: "keyboard.bridge.receiver.listener")
    private let state = ReceiverState()
    private let permissionStatus: PermissionStatus
    private lazy var injector = KeyEventInjector(dryRun: options.dryRun, permissionStatus: permissionStatus, state: state, config: config)
    private var listener: NWListener?

    public init(
        config: ReceiverConfig,
        options: ReceiverRunOptions,
        permissionStatus: PermissionStatus,
        logger: Logger
    ) {
        self.config = config
        self.options = options
        self.permissionStatus = permissionStatus
        self.logger = logger
    }

    public func start() throws {
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw NSError(domain: "ReceiverServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid port"])
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                let portText = listener.port?.rawValue ?? self?.config.port ?? 0
                self?.logger.info("receiver ready on *:\(portText) dryRun=\(self?.options.dryRun ?? false)")
                if let bindHost = self?.config.bindHost, bindHost != "0.0.0.0" {
                    self?.logger.warning("bindHost=\(bindHost) is recorded in config, but this phase listens on all local interfaces and relies on allowedSourceIPs for restriction")
                }
            case .failed(let error):
                self?.logger.error("listener failed: \(error)")
            case .cancelled:
                self?.logger.info("listener cancelled")
            default:
                break
            }
        }
        listener.start(queue: listenerQueue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
    }

    private func handle(connection: NWConnection) {
        let remoteAddress = peerAddress(for: connection)
        connection.start(queue: listenerQueue)
        receiveNext(on: connection, buffer: Data(), remoteAddress: remoteAddress)
    }

    private func receiveNext(on connection: NWConnection, buffer: Data, remoteAddress: String?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var combined = buffer
            if let data = data, !data.isEmpty {
                combined.append(data)
            }

            do {
                let parseResult = try HTTPParser.parse(data: combined)
                switch parseResult {
                case .incomplete:
                    if combined.count > 16 * 1024 {
                        self.send(response: HTTPResponse.text(statusCode: 413, message: "payload too large"), on: connection)
                        return
                    }
                    if isComplete {
                        self.send(response: HTTPResponse.text(statusCode: 400, message: "incomplete request"), on: connection)
                        return
                    }
                    self.receiveNext(on: connection, buffer: combined, remoteAddress: remoteAddress)
                case .complete(let request, let consumedBytes):
                    if consumedBytes == Int.max {
                        self.send(response: HTTPResponse.text(statusCode: 413, message: "payload too large"), on: connection)
                        return
                    }
                    let response = self.route(request: request, remoteAddress: remoteAddress)
                    self.send(response: response, on: connection)
                }
            } catch {
                self.send(response: HTTPResponse.text(statusCode: 400, message: error.localizedDescription), on: connection)
            }

            if let error = error {
                self.logger.warning("connection receive error: \(error)")
            }
        }
    }

    private func route(request: HTTPRequest, remoteAddress: String?) -> HTTPResponse {
        if config.logRequests && !(request.method == "GET" && request.path == "/health") {
            logger.info("request \(request.method) \(request.path) from \(remoteAddress ?? "unknown")")
        }

        if request.method == "GET" && request.path == "/health" {
            let currentInputSource = InputSourceManager.currentInputSource()
            let currentKeyboardLayout = InputSourceManager.currentKeyboardLayout()
            return HTTPResponse.json(statusCode: 200, object: [
                "accessibilityTrusted": permissionStatus.accessibilityTrusted,
                "bindHost": config.bindHost,
                "capsLockBehavior": config.capsLockBehavior.rawValue,
                "currentInputModeID": currentInputSource?.inputModeID ?? NSNull(),
                "currentInputSourceID": currentInputSource?.sourceID ?? NSNull(),
                "currentInputSourceName": currentInputSource?.localizedName ?? NSNull(),
                "currentKeyboardLayoutID": currentKeyboardLayout?.sourceID ?? NSNull(),
                "currentKeyboardLayoutName": currentKeyboardLayout?.localizedName ?? NSNull(),
                "dryRun": options.dryRun,
                "enabled": state.isEnabled(),
                "listenAddressKnown": remoteAddress != nil,
                "postEventAccess": permissionStatus.eventAccessGranted,
                "pressedKeyCount": state.pressedKeyCount(),
                "readyForPosting": permissionStatus.isReady
            ])
        }

        guard isAllowed(remoteAddress: remoteAddress) else {
            return HTTPResponse.json(statusCode: 403, object: [
                "error": "source IP not allowed",
                "remoteAddress": remoteAddress ?? "unknown"
            ])
        }

        if request.method == "POST" && request.path == "/v1/control/disable" {
            return handleControl(request: request, enable: false)
        }

        if request.method == "POST" && request.path == "/v1/control/enable" {
            return handleControl(request: request, enable: true)
        }

        if request.method == "POST" && request.path == "/v1/control/release-all" {
            return handleReleaseAll(request: request)
        }

        if request.method == "POST" && request.path == "/v1/key" {
            return handleKey(request: request)
        }

        return HTTPResponse.json(statusCode: 404, object: ["error": "unknown endpoint"])
    }

    private func handleControl(request: HTTPRequest, enable: Bool) -> HTTPResponse {
        let payload: ReceiverControlRequest
        if request.body.isEmpty {
            payload = ReceiverControlRequest(token: nil)
        } else if let decoded = try? JSONDecoder().decode(ReceiverControlRequest.self, from: request.body) {
            payload = decoded
        } else {
            return HTTPResponse.json(statusCode: 400, object: ["error": "invalid JSON body"])
        }

        let token = payload.token ?? request.header(named: "x-bridge-token")
        guard secureEquals(token, config.sharedToken) else {
            return HTTPResponse.json(statusCode: 401, object: ["error": "invalid token"])
        }

        state.setEnabled(enable)
        logger.warning("receiver \(enable ? "enabled" : "disabled") via control endpoint")
        return HTTPResponse.json(statusCode: 200, object: [
            "enabled": enable,
            "message": enable ? "receiver enabled" : "receiver disabled"
        ])
    }

    private func handleReleaseAll(request: HTTPRequest) -> HTTPResponse {
        let payload: ReceiverControlRequest
        if request.body.isEmpty {
            payload = ReceiverControlRequest(token: nil)
        } else if let decoded = try? JSONDecoder().decode(ReceiverControlRequest.self, from: request.body) {
            payload = decoded
        } else {
            return HTTPResponse.json(statusCode: 400, object: ["error": "invalid JSON body"])
        }

        let token = payload.token ?? request.header(named: "x-bridge-token")
        guard secureEquals(token, config.sharedToken) else {
            return HTTPResponse.json(statusCode: 401, object: ["error": "invalid token"])
        }

        let result = injector.releaseAll()
        let statusCode = result.posted || options.dryRun ? 200 : 503
        return HTTPResponse.json(statusCode: statusCode, object: [
            "message": result.message,
            "pressedKeyCount": state.pressedKeyCount(),
            "released": result.posted || options.dryRun
        ])
    }

    private func handleKey(request: HTTPRequest) -> HTTPResponse {
        if !state.isEnabled() {
            return HTTPResponse.json(statusCode: 409, object: ["error": "receiver is disabled"])
        }

        let decoded: RemoteKeyRequest
        do {
            decoded = try JSONDecoder().decode(RemoteKeyRequest.self, from: request.body)
        } catch {
            return HTTPResponse.json(statusCode: 400, object: ["error": "invalid JSON body"])
        }

        let resolved: ResolvedKeyEvent
        do {
            resolved = try RemoteKeyRequestValidator.resolve(decoded, headerToken: request.header(named: "x-bridge-token"))
        } catch {
            return HTTPResponse.json(statusCode: 422, object: ["error": "\(error)"])
        }

        guard secureEquals(resolved.token, config.sharedToken) else {
            return HTTPResponse.json(statusCode: 401, object: ["error": "invalid token"])
        }

        let result = injector.inject(resolved)
        let statusCode = result.posted || options.dryRun ? 200 : 503
        return HTTPResponse.json(statusCode: statusCode, object: [
            "action": resolved.action.rawValue,
            "dryRun": options.dryRun,
            "keyCode": Int(resolved.keyCode),
            "keyName": resolved.keyName ?? NSNull(),
            "message": result.message,
            "posted": result.posted,
            "sequence": resolved.sequence ?? NSNull(),
            "source": resolved.source ?? NSNull()
        ])
    }

    private func send(response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.warning("send failed: \(error)")
            }
            connection.cancel()
        })
    }

    private func isAllowed(remoteAddress: String?) -> Bool {
        guard !config.allowedSourceIPs.isEmpty else {
            return true
        }
        guard let remoteAddress = remoteAddress else {
            return false
        }
        return config.allowedSourceIPs.contains(remoteAddress)
    }

    private func peerAddress(for connection: NWConnection) -> String? {
        switch connection.endpoint {
        case .hostPort(let host, _):
            return host.debugDescription.replacingOccurrences(of: "\"", with: "")
        default:
            return nil
        }
    }

    private func secureEquals(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs = lhs else {
            return false
        }

        let leftBytes = Array(lhs.utf8)
        let rightBytes = Array(rhs.utf8)

        if leftBytes.count != rightBytes.count {
            return false
        }

        var diff: UInt8 = 0
        for (left, right) in zip(leftBytes, rightBytes) {
            diff |= left ^ right
        }
        return diff == 0
    }
}
