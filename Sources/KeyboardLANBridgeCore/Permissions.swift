import ApplicationServices
import CoreGraphics
import Foundation

public enum PermissionRole: String {
    case sender
    case receiver
}

public struct PermissionStatus {
    public let role: PermissionRole
    public let accessibilityTrusted: Bool
    public let eventAccessGranted: Bool
    public let promptAttempted: Bool

    public var isReady: Bool {
        accessibilityTrusted && eventAccessGranted
    }

    public var lines: [String] {
        switch role {
        case .sender:
            return [
                "role: sender",
                "accessibility trusted: \(accessibilityTrusted)",
                "listen event access: \(eventAccessGranted)",
                "ready: \(isReady)"
            ]
        case .receiver:
            return [
                "role: receiver",
                "accessibility trusted: \(accessibilityTrusted)",
                "post event access: \(eventAccessGranted)",
                "ready: \(isReady)"
            ]
        }
    }
}

public enum PermissionDiagnostics {
    public static func inspect(role: PermissionRole, prompt: Bool) -> PermissionStatus {
        let accessibilityTrusted = axIsTrusted(prompt: prompt)
        let eventAccessGranted: Bool

        if #available(macOS 10.15, *) {
            switch role {
            case .sender:
                eventAccessGranted = prompt ? CGRequestListenEventAccess() : CGPreflightListenEventAccess()
            case .receiver:
                eventAccessGranted = prompt ? CGRequestPostEventAccess() : CGPreflightPostEventAccess()
            }
        } else {
            eventAccessGranted = true
        }

        return PermissionStatus(
            role: role,
            accessibilityTrusted: accessibilityTrusted,
            eventAccessGranted: eventAccessGranted,
            promptAttempted: prompt
        )
    }

    private static func axIsTrusted(prompt: Bool) -> Bool {
        if prompt {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }
}
