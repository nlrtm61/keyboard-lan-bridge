// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "keyboard-lan-bridge",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "receiver", targets: ["receiver"]),
        .executable(name: "sender", targets: ["sender"]),
        .executable(name: "sender-menubar", targets: ["sender-menubar"])
    ],
    targets: [
        .target(
            name: "KeyboardLANBridgeCore",
            dependencies: []
        ),
        .executableTarget(
            name: "receiver",
            dependencies: ["KeyboardLANBridgeCore"]
        ),
        .executableTarget(
            name: "sender",
            dependencies: ["KeyboardLANBridgeCore"]
        ),
        .executableTarget(
            name: "sender-menubar",
            dependencies: ["KeyboardLANBridgeCore"]
        )
    ]
)
