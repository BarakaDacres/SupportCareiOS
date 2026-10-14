// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SupportCareKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "SupportCareCore", targets: ["SupportCareCore"]),
        .library(name: "SupportCareServices", targets: ["SupportCareServices"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.31.0"),
    ],
    targets: [
        // Pure Foundation: models, pay engine, invoicing, holidays. Builds and tests on Linux.
        .target(
            name: "SupportCareCore",
            resources: [.process("Resources")]
        ),
        // Supabase-backed repositories and auth.
        .target(
            name: "SupportCareServices",
            dependencies: [
                "SupportCareCore",
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(
            name: "SupportCareCoreTests",
            dependencies: ["SupportCareCore"],
            resources: [.copy("web_fixtures.json")]
        ),
    ]
)
