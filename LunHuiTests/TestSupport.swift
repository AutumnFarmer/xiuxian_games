import Foundation
import XCTest
@testable import LunHui

/// 测试用的配置加载：命令行下从源码目录读 JSON，Xcode 里从 App 包读。
enum TestConfig {
    static let shared: GameConfig = {
        do {
            if let cfg = try? GameConfig.loadBundled() { return cfg }
            let here = URL(fileURLWithPath: #filePath)
            let tables = here.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("LunHui/Config/Tables")
            return try GameConfig.load(directory: tables)
        } catch {
            fatalError("配置加载失败：\(error)")
        }
    }()
}
