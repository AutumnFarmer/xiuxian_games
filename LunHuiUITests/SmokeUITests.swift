import XCTest

/// 冒烟测试：从第一次启动一路点到战斗，打完第一关，截图存进测试结果。
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

    func testFirstStage() {
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

        var insightShots = 0
        var midShot = false
        var lootSeen = false
        var k = 0
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            if app.buttons["insight-card-0"].exists {
                if insightShots < 2 { shot(app, "05_insight_\(insightShots)"); insightShots += 1 }
                app.buttons["insight-card-0"].tap()
                continue
            }
            if app.buttons["loot-continue"].exists {
                shot(app, "07_loot")
                lootSeen = true
                app.buttons["loot-continue"].tap()
                continue
            }
            if app.buttons["event-0"].exists {
                shot(app, "08_event")
                app.buttons["event-0"].tap()
                break
            }
            if app.buttons["death-confirm"].exists {
                shot(app, "09_death")
                break
            }
            // 摇杆：从屏幕中下方朝不同方向拖动并按住
            let a = Double(k) * 1.1
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + 0.16 * cos(a), dy: 0.62 + 0.08 * sin(a)))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 1.2)
            k += 1
            if k == 8, !midShot {
                shot(app, "06_battle_mid")
                midShot = true
            }
        }
        XCTAssertTrue(lootSeen, "第一关没有打完")
        sleep(3)
        shot(app, "10_stage2")
        if pause.exists, pause.isHittable {
            pause.tap()
            sleep(1)
            shot(app, "11_pause")
            if app.buttons["pause-resume"].waitForExistence(timeout: 5) { app.buttons["pause-resume"].tap() }
        }
        XCTAssertEqual(app.state, .runningForeground, "App 不在前台（可能崩溃了）")
    }
}
