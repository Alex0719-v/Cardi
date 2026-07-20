import XCTest

final class CardExchangeSimulationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testMutualSimulationPresentsAndPersistsIncomingCard() throws {
        launchExchangeSimulation()

        XCTAssertTrue(app.buttons["debug.simulateExchange"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["拒绝"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["分到列表"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["收到的名片"].exists)
        attachScreenshot(named: "exchange-mutual-incoming")

        XCTAssertTrue(
            waitForNonExistence(app.buttons["拒绝"], timeout: 7),
            "互换来卡应在自动接收、保存和收纳动画完成后关闭"
        )
        assertReceivedCardAppearsInCardHolder()
        attachScreenshot(named: "exchange-mutual-persisted")
    }

    func testSingleDeliveryCanAutomaticallyFlipPersistAndReturn() throws {
        launchExchangeSimulation(singleDelivery: true, autoReturn: true)

        XCTAssertTrue(app.buttons["debug.simulateExchange"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["拒绝"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["收到的名片，向侧边翻转可回递"].exists,
            "单向来卡必须暴露可翻转回递状态"
        )
        attachScreenshot(named: "exchange-single-incoming")

        XCTAssertTrue(
            waitForNonExistence(app.buttons["拒绝"], timeout: 7),
            "自动翻转、保存、ACK 和回递动画应能完成"
        )
        assertReceivedCardAppearsInCardHolder()
        attachScreenshot(named: "exchange-single-returned")
    }

    private func launchExchangeSimulation(
        singleDelivery: Bool = false,
        autoReturn: Bool = false
    ) {
        app = XCUIApplication()
        app.launchEnvironment["CARDA_ENABLE_EXCHANGE_SIMULATION"] = "1"
        app.launchEnvironment["CARDA_AUTO_SIMULATE_EXCHANGE"] = "1"
        if singleDelivery {
            app.launchEnvironment["CARDA_SIMULATE_SINGLE_DELIVERY"] = "1"
        }
        if autoReturn {
            app.launchEnvironment["CARDA_AUTO_SIMULATE_RETURN"] = "1"
        }
        app.launch()
    }

    private func assertReceivedCardAppearsInCardHolder() {
        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.waitForExistence(timeout: 3))
        cardHolder.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["模拟对方"].waitForExistence(timeout: 5),
            "持久化 ACK 前保存的收到名片必须进入名片夹数据源"
        )
    }

    private func waitForNonExistence(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
