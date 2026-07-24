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

    func testAssignIncomingCardToSelectedExistingList() throws {
        launchExchangeSimulation()

        let assignButton = app.buttons["分到列表"]
        XCTAssertTrue(assignButton.waitForExistence(timeout: 5))
        assignButton.tap()

        XCTAssertTrue(
            app.staticTexts["exchange.listPicker.title"]
                .waitForExistence(timeout: 3),
            "点击分到列表后应显示列表选择弹窗"
        )
        XCTAssertTrue(
            app.buttons["exchange.listPicker.cancel"].waitForExistence(timeout: 2),
            "列表选择弹窗应显示取消按钮"
        )

        let listOptions = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "exchange.listPicker.option."
            )
        )
        let firstOption = listOptions.firstMatch
        XCTAssertTrue(firstOption.waitForExistence(timeout: 3), "弹窗应显示现有列表")
        let optionIdentifier = firstOption.identifier
        firstOption.tap()
        XCTAssertEqual(firstOption.value as? String, "已选择")
        attachScreenshot(named: "exchange-list-picker-selected")

        let confirmButton = app.buttons["exchange.listPicker.confirm"]
        XCTAssertTrue(confirmButton.isEnabled)
        confirmButton.tap()

        XCTAssertTrue(
            waitForNonExistence(app.buttons["拒绝"], timeout: 5),
            "确认列表后应完成收纳并关闭接收层"
        )

        let selectedListID = optionIdentifier.replacingOccurrences(
            of: "exchange.listPicker.option.",
            with: ""
        )
        app.buttons["名片夹"].tap()

        let listMode = app.buttons["card-holder-mode-列表"]
        XCTAssertTrue(listMode.waitForExistence(timeout: 3))
        listMode.tap()

        let selectedListRow = app.descendants(matching: .any)[
            "card-holder-list-\(selectedListID)"
        ]
        XCTAssertTrue(
            selectedListRow.waitForExistence(timeout: 4),
            "所选列表应继续存在于名片夹"
        )
        selectedListRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["模拟对方"].waitForExistence(timeout: 4),
            "收到的名片应归入刚才确认的列表"
        )
        attachScreenshot(named: "exchange-assigned-to-selected-list")
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

    func testUpwardCardDragPrimesRealDiscoveryGesture() throws {
        app = XCUIApplication()
        app.launchEnvironment["CARDA_ENABLE_EXCHANGE_SIMULATION"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["debug.simulateExchange"].waitForExistence(timeout: 4))

        let window = app.windows.firstMatch
        let dragStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)
        )
        let dragEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)
        )
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        let feedback = app.staticTexts["exchange.feedback"]
        XCTAssertTrue(
            feedback.waitForExistence(timeout: 1),
            "从当前名片内上划应进入真实交换手势链路并显示当前交换状态。\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            [
                "当前设备不支持近距离测距",
                "正在寻找附近可接收的人",
                "正在确认最近的接收者"
            ].contains(feedback.label),
            "真实上划应到达 NI 能力检查或附近发现阶段，实际状态：\(feedback.label)"
        )
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
