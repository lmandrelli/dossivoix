// swift-tools-version: 6.0
// Logique pure de Dossivoix : aucune dépendance à CoreNFC, AVFoundation ou UIKit,
// pour pouvoir tout tester sur Mac avec `swift test`.

import PackageDescription

let package = Package(
    name: "DossivoixCore",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DossivoixCore", targets: ["DossivoixCore"]),
    ],
    targets: [
        .target(name: "DossivoixCore"),
        .testTarget(name: "DossivoixCoreTests", dependencies: ["DossivoixCore"]),
    ]
)
