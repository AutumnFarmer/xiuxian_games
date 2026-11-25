# 轮回录

iOS 单机修仙肉鸽刷子游戏。玩法规则见 [轮回录_设计文档.md](轮回录_设计文档.md)。

## 装到 iPhone 上

需要一台装了 Xcode 的 Mac，以及 Homebrew。

```bash
brew install xcodegen          # 只需要装一次
git clone https://github.com/AutumnFarmer/xiuxian_games.git
cd xiuxian_games
xcodegen generate              # 生成 LunHui.xcodeproj
open LunHui.xcodeproj
```

在 Xcode 里：

1. 用数据线连上 iPhone，顶部的运行目标选你的手机。
2. 第一次装机时，在 LunHui target 的 Signing & Capabilities 里确认 Team 是你的开发者账号（工程里预填了 X3ZQB66K6X）。如果 bundle id `com.zmc.lunhui` 冲突，改一个即可。
3. 按 ⌘R 运行。手机上第一次打开时，如果提示"未受信任的开发者"，到 设置 → 通用 → VPN 与设备管理 里信任你的开发者证书。
4. 手机需要打开开发者模式：设置 → 隐私与安全性 → 开发者模式。

以后更新：`git pull`，再 `xcodegen generate`，然后 ⌘R。存档在 App 自己的目录里，重新安装不会丢。

真机测试要看的点见 [测试清单.md](测试清单.md)。

## 工程结构

```
LunHui/
├── App/        入口 LunHuiApp、AppState（路由和存档）
├── Config/     配置结构体；Tables/ 下是 23 个 JSON 配置表，所有数值都在这里
├── Models/     Item、SaveData、RunState 等纯数据
├── Save/       SaveManager：save.json、run.json、备份
├── Meta/       局外逻辑：结算、法宝生成、洗练、本命、道心、顿悟生成
├── Battle/     BattleWorld（纯 Swift 战斗模拟）、BattleScene（SpriteKit 渲染）、
│               RunController（一世流程）、BattleFlow（战斗界面流程）、Skills/（24 个功法）
├── UI/         SwiftUI 界面
└── Util/       随机数、数字缩写、空间网格、对象池
LunHuiTests/    单元测试和无界面整世模拟
tools/          图标生成脚本
```

战斗逻辑全部在 `BattleWorld` 里按 1/60 秒固定步长计算，不依赖 SpriteKit，所以可以在命令行里直接跑：

```bash
swift test            # Linux 或 macOS 都行，跑的是核心逻辑测试
```

每次推送到 main，GitHub Actions 会在 macOS 上编译 App 并在模拟器里跑单元测试，结果在仓库的 Actions 页面。整世模拟测试在模拟器上太慢，只在命令行 `swift test` 里跑。提交信息里带 `[ui]` 时，CI 还会跑 UI 冒烟测试，截图推到 `ci-screenshots` 分支。

## 调数值

改 `LunHui/Config/Tables/*.json` 就行，不用动代码。调整顺序按设计文档第 21 章：先调 `balance.json` 的推荐战力和成长曲线，再调 `items.json` 的掉落，最后才调 `skills.json` 里单个功法的倍率。

Debug 版的洞府右上角有一个小虫图标，可以加资源、直接给指定品质和传说特效的法宝、改劫数、解锁全部流派、让下一世直接从任意一关开始（测 Boss、天劫、心魔影子），以及在战斗中显示帧率。

## 和设计文档不一样的地方

代码里标了 `自定：` 的地方是文档没写、开发时自己决定的。主要有：

- 心魔影子复制功法时，统一按功法标签生成镜像招式（投射物类朝玩家射弹，范围类在玩家脚下预警），没有给每个功法单独写影子版本。
- Boss 被击败或渡劫成功时，剩下的小怪一起爆开，关卡干净地结束。
- 秘境词缀的第 1 条一定是增益类，保证第 10 劫以下（只生效前 2 条）也有增益。
- 区域数量加了上限 300（`balance.json` 的 `caps.zones`），防止残留区、血河堆积过多。
