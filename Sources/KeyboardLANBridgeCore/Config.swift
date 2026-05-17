import Foundation

public struct ReceiverConfig: Codable {
    public var bindHost: String
    public var port: UInt16
    public var sharedToken: String
    public var allowedSourceIPs: [String]
    public var promptForPermissionsOnLaunch: Bool
    public var logRequests: Bool
    public var capsLockBehavior: CapsLockBehavior
    public var preferredJapaneseInputSourceID: String?
    public var preferredLatinInputSourceID: String?

    public init(
        bindHost: String,
        port: UInt16,
        sharedToken: String,
        allowedSourceIPs: [String],
        promptForPermissionsOnLaunch: Bool,
        logRequests: Bool,
        capsLockBehavior: CapsLockBehavior,
        preferredJapaneseInputSourceID: String?,
        preferredLatinInputSourceID: String?
    ) {
        self.bindHost = bindHost
        self.port = port
        self.sharedToken = sharedToken
        self.allowedSourceIPs = allowedSourceIPs
        self.promptForPermissionsOnLaunch = promptForPermissionsOnLaunch
        self.logRequests = logRequests
        self.capsLockBehavior = capsLockBehavior
        self.preferredJapaneseInputSourceID = preferredJapaneseInputSourceID
        self.preferredLatinInputSourceID = preferredLatinInputSourceID
    }

    private enum CodingKeys: String, CodingKey {
        case bindHost
        case port
        case sharedToken
        case allowedSourceIPs
        case promptForPermissionsOnLaunch
        case logRequests
        case capsLockBehavior
        case preferredJapaneseInputSourceID
        case preferredLatinInputSourceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bindHost = try container.decode(String.self, forKey: .bindHost)
        self.port = try container.decode(UInt16.self, forKey: .port)
        self.sharedToken = try container.decode(String.self, forKey: .sharedToken)
        self.allowedSourceIPs = try container.decodeIfPresent([String].self, forKey: .allowedSourceIPs) ?? []
        self.promptForPermissionsOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .promptForPermissionsOnLaunch) ?? false
        self.logRequests = try container.decodeIfPresent(Bool.self, forKey: .logRequests) ?? false
        self.capsLockBehavior = try container.decodeIfPresent(CapsLockBehavior.self, forKey: .capsLockBehavior) ?? .toggleLatinAndJapanese
        self.preferredJapaneseInputSourceID = try container.decodeIfPresent(String.self, forKey: .preferredJapaneseInputSourceID)
        self.preferredLatinInputSourceID = try container.decodeIfPresent(String.self, forKey: .preferredLatinInputSourceID)
    }
}

public struct SenderHotkey: Codable {
    public var triggerKey: String
    public var triggerModifiers: [ModifierKey]
    public var sendKey: String?
    public var sendKeyCode: Int?
    public var action: KeyAction
    public var modifiers: [ModifierKey]

    public init(
        triggerKey: String,
        triggerModifiers: [ModifierKey],
        sendKey: String?,
        sendKeyCode: Int?,
        action: KeyAction,
        modifiers: [ModifierKey]
    ) {
        self.triggerKey = triggerKey
        self.triggerModifiers = triggerModifiers
        self.sendKey = sendKey
        self.sendKeyCode = sendKeyCode
        self.action = action
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case triggerKey
        case triggerModifiers
        case sendKey
        case sendKeyCode
        case action
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.triggerKey = try container.decode(String.self, forKey: .triggerKey)
        self.triggerModifiers = try container.decodeIfPresent([ModifierKey].self, forKey: .triggerModifiers) ?? []
        self.sendKey = try container.decodeIfPresent(String.self, forKey: .sendKey)
        self.sendKeyCode = try container.decodeIfPresent(Int.self, forKey: .sendKeyCode)
        self.action = try container.decode(KeyAction.self, forKey: .action)
        self.modifiers = try container.decodeIfPresent([ModifierKey].self, forKey: .modifiers) ?? []
    }
}

public struct SenderConfig: Codable {
    public var receiverHost: String
    public var receiverPort: UInt16
    public var sharedToken: String
    public var promptForPermissionsOnLaunch: Bool
    public var enabledOnLaunch: Bool
    public var toggleHotkey: String?
    public var toggleHotkeyModifiers: [ModifierKey]
    public var quitHotkey: String?
    public var quitHotkeyModifiers: [ModifierKey]
    public var logNetworkResponses: Bool
    public var logVerboseEvents: Bool
    public var hotkeys: [SenderHotkey]

    public init(
        receiverHost: String,
        receiverPort: UInt16,
        sharedToken: String,
        promptForPermissionsOnLaunch: Bool,
        enabledOnLaunch: Bool,
        toggleHotkey: String?,
        toggleHotkeyModifiers: [ModifierKey],
        quitHotkey: String?,
        quitHotkeyModifiers: [ModifierKey],
        logNetworkResponses: Bool,
        logVerboseEvents: Bool,
        hotkeys: [SenderHotkey]
    ) {
        self.receiverHost = receiverHost
        self.receiverPort = receiverPort
        self.sharedToken = sharedToken
        self.promptForPermissionsOnLaunch = promptForPermissionsOnLaunch
        self.enabledOnLaunch = enabledOnLaunch
        self.toggleHotkey = toggleHotkey
        self.toggleHotkeyModifiers = toggleHotkeyModifiers
        self.quitHotkey = quitHotkey
        self.quitHotkeyModifiers = quitHotkeyModifiers
        self.logNetworkResponses = logNetworkResponses
        self.logVerboseEvents = logVerboseEvents
        self.hotkeys = hotkeys
    }

    private enum CodingKeys: String, CodingKey {
        case receiverHost
        case receiverPort
        case sharedToken
        case promptForPermissionsOnLaunch
        case enabledOnLaunch
        case toggleHotkey
        case toggleHotkeyModifiers
        case quitHotkey
        case quitHotkeyModifiers
        case logNetworkResponses
        case logVerboseEvents
        case hotkeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.receiverHost = try container.decode(String.self, forKey: .receiverHost)
        self.receiverPort = try container.decode(UInt16.self, forKey: .receiverPort)
        self.sharedToken = try container.decode(String.self, forKey: .sharedToken)
        self.promptForPermissionsOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .promptForPermissionsOnLaunch) ?? false
        self.enabledOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .enabledOnLaunch) ?? false
        self.toggleHotkey = try container.decodeIfPresent(String.self, forKey: .toggleHotkey)
        self.toggleHotkeyModifiers = try container.decodeIfPresent([ModifierKey].self, forKey: .toggleHotkeyModifiers) ?? []
        self.quitHotkey = try container.decodeIfPresent(String.self, forKey: .quitHotkey)
        self.quitHotkeyModifiers = try container.decodeIfPresent([ModifierKey].self, forKey: .quitHotkeyModifiers) ?? []
        self.logNetworkResponses = try container.decodeIfPresent(Bool.self, forKey: .logNetworkResponses) ?? false
        self.logVerboseEvents = try container.decodeIfPresent(Bool.self, forKey: .logVerboseEvents) ?? false
        self.hotkeys = try container.decodeIfPresent([SenderHotkey].self, forKey: .hotkeys) ?? []
    }
}

public enum ConfigLoaderError: Error, CustomStringConvertible {
    case missingPath(String)
    case unreadable(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .missingPath(let path):
            return "config file not found: \(path)"
        case .unreadable(let message):
            return "failed to read config: \(message)"
        case .invalidJSON(let message):
            return "invalid config JSON: \(message)"
        }
    }
}

public enum ConfigLoader {
    public static func loadReceiverConfig(path: String) throws -> ReceiverConfig {
        try load(path: path, as: ReceiverConfig.self)
    }

    public static func loadSenderConfig(path: String) throws -> SenderConfig {
        try load(path: path, as: SenderConfig.self)
    }

    private static func load<T: Decodable>(path: String, as type: T.Type) throws -> T {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigLoaderError.missingPath(url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigLoaderError.unreadable(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ConfigLoaderError.invalidJSON(error.localizedDescription)
        }
    }
}
