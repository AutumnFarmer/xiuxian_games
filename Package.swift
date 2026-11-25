// swift-tools-version:5.9
import PackageDescription

// 这个 Package 只用来在命令行（Linux 或 macOS）编译和测试核心逻辑。
// iOS App 用 project.yml（XcodeGen）生成 Xcode 工程，见 README。
// LunHui/ 下所有 iOS 专用文件都包在 `#if os(iOS)` 里，在这里会编译成空文件。
// 模块名和 Xcode 里的 App 模块同名（LunHui），测试里统一写 `@testable import LunHui`。
let package = Package(
    name: "LunHui",
    targets: [
        .target(
            name: "LunHui",
            path: "LunHui",
            exclude: ["Resources", "Config/Tables"]
        ),
        .testTarget(
            name: "LunHuiTests",
            dependencies: ["LunHui"],
            path: "LunHuiTests"
        ),
    ]
)
