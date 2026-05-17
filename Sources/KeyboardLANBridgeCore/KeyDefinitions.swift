import Carbon
import CoreGraphics
import Foundation

public enum KeyAction: String, Codable {
    case tap
    case down
    case up
}

public enum ModifierKey: String, Codable, CaseIterable {
    case shift
    case control
    case option
    case command
    case capsLock

    public var eventFlags: CGEventFlags {
        switch self {
        case .shift:
            return .maskShift
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        case .capsLock:
            return .maskAlphaShift
        }
    }

    public var keyCode: CGKeyCode {
        switch self {
        case .shift:
            return CGKeyCode(kVK_Shift)
        case .control:
            return CGKeyCode(kVK_Control)
        case .option:
            return CGKeyCode(kVK_Option)
        case .command:
            return CGKeyCode(kVK_Command)
        case .capsLock:
            return CGKeyCode(kVK_CapsLock)
        }
    }

    public static var orderedForPress: [ModifierKey] {
        [.capsLock, .control, .option, .shift, .command]
    }
}

public struct RemoteKeyRequest: Codable {
    public var token: String?
    public var key: String?
    public var keyCode: Int?
    public var action: KeyAction?
    public var modifiers: [ModifierKey]?
    public var source: String?
    public var sequence: UInt64?
    public var senderInputSourceID: String?
    public var senderInputModeID: String?
    public var senderKeyboardLayoutID: String?

    public init(
        token: String?,
        key: String?,
        keyCode: Int?,
        action: KeyAction?,
        modifiers: [ModifierKey]?,
        source: String?,
        sequence: UInt64?,
        senderInputSourceID: String?,
        senderInputModeID: String?,
        senderKeyboardLayoutID: String?
    ) {
        self.token = token
        self.key = key
        self.keyCode = keyCode
        self.action = action
        self.modifiers = modifiers
        self.source = source
        self.sequence = sequence
        self.senderInputSourceID = senderInputSourceID
        self.senderInputModeID = senderInputModeID
        self.senderKeyboardLayoutID = senderKeyboardLayoutID
    }
}

public struct ResolvedKeyEvent {
    public let token: String
    public let keyCode: CGKeyCode
    public let keyName: String?
    public let action: KeyAction
    public let modifiers: [ModifierKey]
    public let source: String?
    public let sequence: UInt64?
    public let senderInputSourceID: String?
    public let senderInputModeID: String?
    public let senderKeyboardLayoutID: String?
}

public enum RemoteKeyRequestError: Error, CustomStringConvertible {
    case missingToken
    case ambiguousKey
    case missingKey
    case unknownNamedKey(String)
    case invalidKeyCode(Int)

    public var description: String {
        switch self {
        case .missingToken:
            return "missing token"
        case .ambiguousKey:
            return "specify either key or keyCode, not both"
        case .missingKey:
            return "missing key or keyCode"
        case .unknownNamedKey(let name):
            return "unknown key name: \(name)"
        case .invalidKeyCode(let code):
            return "invalid keyCode: \(code)"
        }
    }
}

public enum KeyRegistry {
    private static let keyCodes: [String: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        "space": CGKeyCode(kVK_Space),
        "enter": CGKeyCode(kVK_Return),
        "return": CGKeyCode(kVK_Return),
        "escape": CGKeyCode(kVK_Escape),
        "esc": CGKeyCode(kVK_Escape),
        "tab": CGKeyCode(kVK_Tab),
        "delete": CGKeyCode(kVK_Delete),
        "backspace": CGKeyCode(kVK_Delete),
        "forward-delete": CGKeyCode(kVK_ForwardDelete),
        "left-arrow": CGKeyCode(kVK_LeftArrow),
        "right-arrow": CGKeyCode(kVK_RightArrow),
        "up-arrow": CGKeyCode(kVK_UpArrow),
        "down-arrow": CGKeyCode(kVK_DownArrow),
        "left": CGKeyCode(kVK_LeftArrow),
        "right": CGKeyCode(kVK_RightArrow),
        "up": CGKeyCode(kVK_UpArrow),
        "down": CGKeyCode(kVK_DownArrow),
        "home": CGKeyCode(kVK_Home),
        "end": CGKeyCode(kVK_End),
        "page-up": CGKeyCode(kVK_PageUp),
        "page-down": CGKeyCode(kVK_PageDown),
        "comma": CGKeyCode(kVK_ANSI_Comma),
        "period": CGKeyCode(kVK_ANSI_Period),
        "slash": CGKeyCode(kVK_ANSI_Slash),
        "backslash": CGKeyCode(kVK_ANSI_Backslash),
        "semicolon": CGKeyCode(kVK_ANSI_Semicolon),
        "quote": CGKeyCode(kVK_ANSI_Quote),
        "minus": CGKeyCode(kVK_ANSI_Minus),
        "equals": CGKeyCode(kVK_ANSI_Equal),
        "grave": CGKeyCode(kVK_ANSI_Grave),
        "left-bracket": CGKeyCode(kVK_ANSI_LeftBracket),
        "right-bracket": CGKeyCode(kVK_ANSI_RightBracket),
        "f1": CGKeyCode(kVK_F1),
        "f2": CGKeyCode(kVK_F2),
        "f3": CGKeyCode(kVK_F3),
        "f4": CGKeyCode(kVK_F4),
        "f5": CGKeyCode(kVK_F5),
        "f6": CGKeyCode(kVK_F6),
        "f7": CGKeyCode(kVK_F7),
        "f8": CGKeyCode(kVK_F8),
        "f9": CGKeyCode(kVK_F9),
        "f10": CGKeyCode(kVK_F10),
        "f11": CGKeyCode(kVK_F11),
        "f12": CGKeyCode(kVK_F12),
        "f13": CGKeyCode(kVK_F13),
        "f14": CGKeyCode(kVK_F14),
        "f15": CGKeyCode(kVK_F15),
        "f16": CGKeyCode(kVK_F16),
        "f17": CGKeyCode(kVK_F17),
        "f18": CGKeyCode(kVK_F18),
        "f19": CGKeyCode(kVK_F19)
    ]

    public static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    public static func keyCode(for name: String) -> CGKeyCode? {
        keyCodes[normalized(name)]
    }

    public static func keyName(for code: CGKeyCode) -> String? {
        keyCodes.first(where: { $0.value == code })?.key
    }
}

public enum RemoteKeyRequestValidator {
    public static func resolve(_ request: RemoteKeyRequest, headerToken: String?) throws -> ResolvedKeyEvent {
        let token = request.token ?? headerToken
        guard let token = token, !token.isEmpty else {
            throw RemoteKeyRequestError.missingToken
        }

        let action = request.action ?? .tap
        let modifiers = request.modifiers ?? []

        if request.key != nil && request.keyCode != nil {
            throw RemoteKeyRequestError.ambiguousKey
        }

        if let key = request.key {
            guard let keyCode = KeyRegistry.keyCode(for: key) else {
                throw RemoteKeyRequestError.unknownNamedKey(key)
            }
            return ResolvedKeyEvent(
                token: token,
                keyCode: keyCode,
                keyName: KeyRegistry.normalized(key),
                action: action,
                modifiers: modifiers,
                source: request.source,
                sequence: request.sequence,
                senderInputSourceID: request.senderInputSourceID,
                senderInputModeID: request.senderInputModeID,
                senderKeyboardLayoutID: request.senderKeyboardLayoutID
            )
        }

        if let keyCodeValue = request.keyCode {
            guard (0...127).contains(keyCodeValue) else {
                throw RemoteKeyRequestError.invalidKeyCode(keyCodeValue)
            }
            return ResolvedKeyEvent(
                token: token,
                keyCode: CGKeyCode(keyCodeValue),
                keyName: KeyRegistry.keyName(for: CGKeyCode(keyCodeValue)),
                action: action,
                modifiers: modifiers,
                source: request.source,
                sequence: request.sequence,
                senderInputSourceID: request.senderInputSourceID,
                senderInputModeID: request.senderInputModeID,
                senderKeyboardLayoutID: request.senderKeyboardLayoutID
            )
        }

        throw RemoteKeyRequestError.missingKey
    }
}
