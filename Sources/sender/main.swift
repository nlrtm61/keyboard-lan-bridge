import Foundation
import KeyboardLANBridgeCore

private let logger = Logger(subsystem: "sender")

private func usage() {
    let text = """
    Usage:
      sender permissions [--prompt]
      sender run --config <path>
      sender send --config <path> --key <name> [--action tap|down|up]
      sender send --config <path> --key-code <number> [--action tap|down|up]

    Examples:
      sender permissions --prompt
      sender run --config ./configs/sender.sample.json
      sender send --config ./configs/sender.sample.json --key space
    """
    print(text)
}

private func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private func parseAction(_ value: String?) -> KeyAction {
    guard let value = value, let action = KeyAction(rawValue: value) else {
        return .tap
    }
    return action
}

private func waitForSend(using work: (@escaping (Result<(Int, String), Error>) -> Void) -> Void) -> Int32 {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    work { result in
        switch result {
        case .success(let value):
            print("status: \(value.0)")
            print(value.1)
            exitCode = (200...299).contains(value.0) ? 0 : 1
        case .failure(let error):
            fputs("\(error)\n", stderr)
            exitCode = 1
        }
        semaphore.signal()
    }

    semaphore.wait()
    return exitCode
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first else {
    usage()
    exit(1)
}

switch subcommand {
case "permissions":
    let prompt = arguments.contains("--prompt")
    let status = PermissionDiagnostics.inspect(role: .sender, prompt: prompt)
    status.lines.forEach { print($0) }

case "run":
    guard let configPath = argumentValue("--config", in: arguments) else {
        fputs("missing --config\n", stderr)
        usage()
        exit(1)
    }

    do {
        let config = try ConfigLoader.loadSenderConfig(path: configPath)
        let prompt = arguments.contains("--prompt") || config.promptForPermissionsOnLaunch
        let permissions = PermissionDiagnostics.inspect(role: .sender, prompt: prompt)
        permissions.lines.forEach { logger.info($0) }

        let monitor = try SenderHotkeyMonitor(config: config, permissionStatus: permissions, logger: logger)
        try monitor.start()
    } catch {
        logger.error("\(error)")
        exit(1)
    }

case "send":
    guard let configPath = argumentValue("--config", in: arguments) else {
        fputs("missing --config\n", stderr)
        usage()
        exit(1)
    }

    do {
        let config = try ConfigLoader.loadSenderConfig(path: configPath)
        let client = SenderClient(config: config, logger: logger)
        let action = parseAction(argumentValue("--action", in: arguments))
        let exitCode: Int32

        if let key = argumentValue("--key", in: arguments) {
            exitCode = waitForSend { completion in
                client.sendManual(key: key, keyCode: nil, action: action, modifiers: [], completion: completion)
            }
        } else if let rawKeyCode = argumentValue("--key-code", in: arguments), let keyCode = Int(rawKeyCode) {
            exitCode = waitForSend { completion in
                client.sendManual(key: nil, keyCode: keyCode, action: action, modifiers: [], completion: completion)
            }
        } else {
            fputs("missing --key or --key-code\n", stderr)
            usage()
            exit(1)
        }

        exit(exitCode)
    } catch {
        logger.error("\(error)")
        exit(1)
    }

default:
    usage()
    exit(1)
}
