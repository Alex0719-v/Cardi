import XCTest

final class CardBackgroundTemplateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testEditorPreviewSwipesThroughEveryBackgroundTemplateInBothDirections() {
        let myCardsTab = app.buttons["我的名片"]
        XCTAssertTrue(myCardsTab.waitForExistence(timeout: 3))
        myCardsTab.tap()

        let createFirstCard = app.buttons["创建第一张名片"]
        if createFirstCard.waitForExistence(timeout: 1) {
            createFirstCard.tap()
        } else {
            let accountAvatar = app.buttons["my-cards-account-avatar-button"]
            XCTAssertTrue(accountAvatar.waitForExistence(timeout: 2))
            accountAvatar.tap()

            let addCard = app.buttons["添加名片"]
            XCTAssertTrue(addCard.waitForExistence(timeout: 2))
            addCard.tap()
        }

        let picker = app.descendants(matching: .any)["card-background-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertEqual(picker.value as? String, "名片底图一")

        let firstPhoneField = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.79))
        firstPhoneField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        app.typeText("19204902910\n")
        XCTAssertTrue(waitUntilHittable(picker))

        let firstTemplateScreenshot = picker.screenshot()
        addPreviewAttachment(firstTemplateScreenshot, name: "card-background-color1")
        let firstTemplateImage = firstTemplateScreenshot.pngRepresentation

        picker.swipeLeft()
        XCTAssertTrue(waitForValue("名片底图二", in: picker))
        let secondTemplateScreenshot = picker.screenshot()
        addPreviewAttachment(secondTemplateScreenshot, name: "card-background-color2")
        let secondTemplateImage = secondTemplateScreenshot.pngRepresentation
        XCTAssertNotEqual(firstTemplateImage, secondTemplateImage)

        picker.swipeLeft()
        XCTAssertTrue(waitForValue("名片底图三", in: picker))
        let thirdTemplateScreenshot = picker.screenshot()
        addPreviewAttachment(thirdTemplateScreenshot, name: "card-background-color3")
        let thirdTemplateImage = thirdTemplateScreenshot.pngRepresentation
        XCTAssertNotEqual(secondTemplateImage, thirdTemplateImage)
        XCTAssertNotEqual(firstTemplateImage, thirdTemplateImage)

        picker.swipeRight()
        XCTAssertTrue(waitForValue("名片底图二", in: picker))

        picker.swipeRight()
        XCTAssertTrue(waitForValue("名片底图一", in: picker))
    }

    private func waitForValue(_ value: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func waitUntilHittable(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func addPreviewAttachment(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
