import Foundation
import KeyboardLANBridgeCore

private let logger = Logger(subsystem: "receiver")
private var runningServer: ReceiverServer?

private func usage() {
    let text = """
    Usage:
      receiver permissions [--prompt]
      receiver run --config <path> [--dry-run]

    Examples:
      receiver permissions --prompt
      receiver run --config ./configs/receiver.sample.json --dry-run
    """
    print(text)
}

private func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first else {
    usage()
    exit(1)
}

switch subcommand {
case "permissions":
    let prompt = arguments.contains("--prompt")
    let status = PermissionDiagnostics.inspect(role: .receiver, prompt: prompt)
    status.lines.forEach { print($0) }

case "run":
    guard let configPath = argumentValue("--config", in: arguments) else {
        fputs("missing --config\n", stderr)
        usage()
        exit(1)
    }

    do {
        let config = try ConfigLoader.loadReceiverConfig(path: configPath)
        let prompt = arguments.contains("--prompt") || config.promptForPermissionsOnLaunch
        let permissions = PermissionDiagnostics.inspect(role: .receiver, prompt: prompt)
        permissions.lines.forEach { logger.info($0) }

        let dryRun = arguments.contains("--dry-run")
        let server = ReceiverServer(
            config: config,
            options: ReceiverRunOptions(dryRun: dryRun),
            permissionStatus: permissions,
            logger: logger
        )
        try server.start()
        runningServer = server
        RunLoop.current.run()
    } catch {
        logger.error("\(error)")
        exit(1)
    }

default:
    usage()
    exit(1)
}
