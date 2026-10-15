// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Puipui",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.5.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "TerminalPTY"),
        .executableTarget(name: "Puipui", dependencies: ["TerminalPTY", .product(name: "GhosttyTerminal", package: "libghostty-spm"), .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.process("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PuipuiTests", dependencies: ["Puipui"])
    ]
)
