// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Puipui",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.5.2")],
    targets: [
        .target(name: "TerminalPTY"),
        .executableTarget(name: "Puipui", dependencies: ["TerminalPTY", .product(name: "GhosttyTerminal", package: "libghostty-spm")],
                          resources: [.process("Resources")]),
        .testTarget(name: "PuipuiTests", dependencies: ["Puipui"])
    ]
)
