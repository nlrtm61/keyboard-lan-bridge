import Carbon
import Foundation

public enum CapsLockBehavior: String, Codable {
    case passThrough
    case toggleLatinAndJapanese
}

public struct InputSourceSnapshot {
    public let sourceID: String?
    public let bundleID: String?
    public let inputModeID: String?
    public let localizedName: String?
    public let sourceType: String?
    public let isASCIICapable: Bool

    public var isJapaneseIME: Bool {
        let parts = [sourceID, bundleID, inputModeID, localizedName]
            .compactMap { $0?.lowercased() }
        return parts.contains { value in
            value.contains("japanese") || value.contains("kotoeri") || value.contains("hiragana")
        }
    }

    public var isLatinKeyboardLayout: Bool {
        if let sourceID = sourceID, sourceID.hasPrefix("com.apple.keylayout.") {
            return true
        }
        return isASCIICapable && inputModeID == nil
    }
}

public enum InputSourceManager {
    private static let rememberedJapaneseSourceDefaultsKey = "KeyboardLANBridge.lastJapaneseInputSourceID"
    private static let preferredJapaneseFallbacks = [
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
        "com.apple.inputmethod.Kotoeri.Japanese",
        "com.apple.inputmethod.Kotoeri"
    ]
    private static let preferredLatinFallbacks = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    public static func currentInputSource() -> InputSourceSnapshot? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return snapshot(for: source)
    }

    public static func currentKeyboardLayout() -> InputSourceSnapshot? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        return snapshot(for: source)
    }

    public static func toggleLatinAndJapanese(
        preferredJapaneseInputSourceID: String?,
        preferredLatinInputSourceID: String?
    ) -> String {
        guard let current = currentInputSource() else {
            return "failed to inspect current input source"
        }

        if current.isLatinKeyboardLayout {
            if let target = japaneseInputSource(preferredID: preferredJapaneseInputSourceID) {
                rememberJapaneseSourceID(target.snapshot.sourceID)
                let status = TISSelectInputSource(target.source)
                return status == noErr
                    ? "selected japanese input source: \(target.snapshot.localizedName ?? target.snapshot.sourceID ?? "unknown")"
                    : "failed to select japanese input source status=\(status)"
            }
            return "no japanese input source available"
        }

        if current.isJapaneseIME, let currentID = current.sourceID {
            rememberJapaneseSourceID(currentID)
        }

        if let target = latinInputSource(preferredID: preferredLatinInputSourceID) {
            let status = TISSelectInputSource(target.source)
            return status == noErr
                ? "selected latin input source: \(target.snapshot.localizedName ?? target.snapshot.sourceID ?? "unknown")"
                : "failed to select latin input source status=\(status)"
        }

        return "no latin input source available"
    }

    private static func japaneseInputSource(preferredID: String?) -> (source: TISInputSource, snapshot: InputSourceSnapshot)? {
        let remembered = UserDefaults.standard.string(forKey: rememberedJapaneseSourceDefaultsKey)
        let preferreds = [preferredID, remembered]
            .compactMap { $0 } + preferredJapaneseFallbacks

        for preferred in preferreds {
            if let match = inputSource(sourceID: preferred) {
                return match
            }
        }
        return nil
    }

    private static func latinInputSource(preferredID: String?) -> (source: TISInputSource, snapshot: InputSourceSnapshot)? {
        let preferreds = [preferredID].compactMap { $0 } + preferredLatinFallbacks

        for preferred in preferreds {
            if let match = inputSource(sourceID: preferred) {
                return match
            }
        }
        return nil
    }

    private static func rememberJapaneseSourceID(_ sourceID: String?) {
        guard let sourceID = sourceID, !sourceID.isEmpty else { return }
        UserDefaults.standard.set(sourceID, forKey: rememberedJapaneseSourceDefaultsKey)
    }

    private static func inputSource(sourceID: String) -> (source: TISInputSource, snapshot: InputSourceSnapshot)? {
        let properties = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let unmanagedList = TISCreateInputSourceList(properties, false) else {
            return nil
        }
        let sourceList = unmanagedList.takeRetainedValue()
        guard CFArrayGetCount(sourceList) > 0 else {
            return nil
        }
        let rawValue = CFArrayGetValueAtIndex(sourceList, 0)
        let source = unsafeBitCast(rawValue, to: TISInputSource.self)
        return (source, snapshot(for: source))
    }

    private static func snapshot(for source: TISInputSource) -> InputSourceSnapshot {
        let sourceID = stringProperty(kTISPropertyInputSourceID, source: source)
        let bundleID = stringProperty(kTISPropertyBundleID, source: source)
        let inputModeID = stringProperty(kTISPropertyInputModeID, source: source)
        let localizedName = stringProperty(kTISPropertyLocalizedName, source: source)
        let sourceType = stringProperty(kTISPropertyInputSourceType, source: source)
        let isASCIICapable = booleanProperty(kTISPropertyInputSourceIsASCIICapable, source: source)

        return InputSourceSnapshot(
            sourceID: sourceID,
            bundleID: bundleID,
            inputModeID: inputModeID,
            localizedName: localizedName,
            sourceType: sourceType,
            isASCIICapable: isASCIICapable
        )
    }

    private static func stringProperty(_ key: CFString, source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let value = unsafeBitCast(pointer, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private static func booleanProperty(_ key: CFString, source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }
        let value = unsafeBitCast(pointer, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
