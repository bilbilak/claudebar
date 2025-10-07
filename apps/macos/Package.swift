// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeBar", targets: ["ClaudeBar"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeBar",
            path: "Sources/ClaudeBar",
            resources: [
                // Resources/ lives at apps/macos/Resources/, two levels up from
                // Sources/ClaudeBar/. SwiftPM treats .xcstrings as a localized
                // resource and ships the compiled string catalog inside the
                // built .app's Resources directory. The `..` traversal is
                // allowed because the resolved path stays inside the package
                // root (apps/macos/).
                .process("../../Resources/Localizable.xcstrings"),
            ]
        )
    ]
)
