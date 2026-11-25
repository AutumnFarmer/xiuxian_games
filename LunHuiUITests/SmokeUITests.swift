import XCTest

/// 冒烟测试：从第一次启动一路点到战斗，打完练气三关（含第一个 Boss），沿途截图存进测试结果。
/// CI 会把截图推到 ci-screenshots 分支，方便检查界面。
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testFirstRealm() {
        let app = XCUIApplication()
        app.launch()

        let go = app.buttons["first-launch-go"]
        if go.waitForExistence(timeout: 15) {
            shot(app, "01_first_launch")
            go.tap()
        }
        let depart = app.buttons["cave-depart"]
        XCTAssertTrue(depart.waitForExistence(timeout: 15), "洞府没有出现")
        sleep(1)
        shot(app, "02_cave")
        depart.tap()

        let start = app.buttons["prepare-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "出发准备没有出现")
        sleep(1)
        shot(app, "03_prepare")
        start.tap()

        let pause = app.buttons["battle-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "战斗界面没有出现")
        sleep(3)
        shot(app, "04_battle_start")

        var taken = Set<String>()
        func once(_ name: String) {
            guard !taken.contains(name) else { return }
            taken.insert(name)
            shot(app, name)
        }
        var insights = 0
        var stagesDone = 0
        var k = 0
        var bossSeenAt = -1
        let began = Date()
        while Date().timeIntervalSince(began) < 480 {
            if app.buttons["insight-card-0"].exists {
                if insights < 2 { shot(app, "05_insight_\(insights)") }
                insights += 1
                app.buttons["insight-card-0"].tap()
                continue
            }
            if app.buttons["loot-continue"].exists {
                stagesDone += 1
                once("07_loot_stage\(stagesDone)")
                app.buttons["loot-continue"].tap()
                continue
            }
            if app.buttons["event-0"].exists {
                once("08_event_stage\(stagesDone)")
                // 灵石不够的机缘是禁用的，挑第一张能选的
                for i in 0..<3 {
                    let b = app.buttons["event-\(i)"]
                    if b.exists, b.isEnabled {
                        b.tap()
                        break
                    }
                }
                continue
            }
            if app.buttons["death-confirm"].exists {
                shot(app, "09_death")
                break
            }
            if stagesDone >= 3 { break }
            // 摇杆：从屏幕中下方朝不同方向拖动并按住
            let a = Double(k) * 1.1
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + 0.16 * cos(a), dy: 0.62 + 0.08 * sin(a)))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 1.2)
            k += 1
            if k == 10 { once("06_battle_stage1_a") }
            if k == 30 { once("06_battle_stage1_b") }
            if stagesDone == 1, k % 15 == 0 { once("06_battle_stage2") }
            if bossSeenAt < 0, app.staticTexts["啸月狼王"].exists { bossSeenAt = k }
            if bossSeenAt >= 0, k == bossSeenAt + 3 { once("12_boss_fight") }
        }
        XCTAssertGreaterThanOrEqual(stagesDone, 1, "第一关没有打完")
        sleep(2)
        shot(app, "10_after_loop")
        if pause.exists, pause.isHittable {
            pause.tap()
            sleep(1)
            shot(app, "11_pause")
            if app.buttons["pause-resume"].waitForExistence(timeout: 5) { app.buttons["pause-resume"].tap() }
        }
        XCTAssertEqual(app.state, .runningForeground, "App 不在前台（可能崩溃了）")
    }
}
