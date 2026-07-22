import UIKit
import XCTest

final class CardHolderScrollStabilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private let seededReceivedCardName = "本地归档测试联系人"
    private let seededNameGroup = "B"
    private let seededOrganizationGroup = "C"
    private let cardHolderTestPhoneNumber = "13900019991"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CARDA_RESET_ACCOUNT_PROFILE"] = "1"
        app.launchEnvironment["CARDA_SEED_LOCAL_ACCOUNT_TEST_DATA"] = "1"
        app.launchEnvironment["CARDA_LOCAL_ACCOUNT_TEST_PHONE"] = cardHolderTestPhoneNumber
        app.launchEnvironment["CARDA_SEED_CARD_HOLDER_BATCH_TEST_DATA"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testListHeaderSurvivesSlowAndRepeatedFastDirectionChanges() throws {
        enterExpandedListMode()

        let window = app.windows.firstMatch
        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: true),
            "列表顶部导航初始状态应可交互"
        )
        let initialScreenshot = app.screenshot()
        let initialTitleDarkPixelCount = darkPixelCount(
            in: listHeaderTitleRect,
            screenshot: initialScreenshot
        )
        XCTAssertGreaterThan(
            initialTitleDarkPixelCount,
            500,
            "初始截图应包含可见的名片夹标题文字"
        )
        attachScreenshot(named: "01-list-expanded")

        let slowDragStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68)
        )
        let slowDragEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)
        )
        slowDragStart.press(forDuration: 0.12, thenDragTo: slowDragEnd)
        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: false),
            "慢速上滑后顶部导航应完成收起"
        )

        slowDragEnd.press(forDuration: 0.12, thenDragTo: slowDragStart)
        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: true),
            "慢速反向滚动后顶部导航应恢复"
        )

        for cycle in 1...10 {
            window.swipeUp(velocity: .fast)
            XCTAssertTrue(
                waitForVisibleButton("添加列表", expected: false),
                "第 \(cycle) 次快速上滑后顶部导航未收起"
            )

            if cycle == 1 {
                attachScreenshot(named: "02-first-fast-collapse")
            }

            window.swipeDown(velocity: .fast)
            XCTAssertTrue(
                waitForVisibleButton("添加列表", expected: true),
                "第 \(cycle) 次快速反向滚动后顶部导航未恢复"
            )
        }

        // Accessibility continues to expose a fully transparent SwiftUI Text,
        // so verify the rendered pixels after every interrupted animation has
        // had time to settle instead of relying only on `isHittable`.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let recoveredTitleDarkPixelCount = darkPixelCount(
            in: listHeaderTitleRect,
            screenshot: app.screenshot()
        )
        XCTAssertGreaterThanOrEqual(
            recoveredTitleDarkPixelCount,
            Int(Double(initialTitleDarkPixelCount) * 0.75),
            "快速反向滚动后名片夹标题不得停留在透明状态"
        )
        attachScreenshot(named: "03-after-ten-fast-cycles")

        // A successful tap after ten direction changes verifies that the header
        // did not merely reappear visually while retaining a disabled hit region.
        app.buttons["添加列表"].tap()
        XCTAssertTrue(
            app.staticTexts["创建新的列表"].waitForExistence(timeout: 2),
            "连续滚动后顶部导航应继续响应点击"
        )
    }

    func testListHeaderStartsExpandedAfterReturningFromAnotherPage() throws {
        enterExpandedListMode()

        let window = app.windows.firstMatch
        window.swipeUp(velocity: .fast)
        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: false),
            "离开列表页前应先确认顶部导航已收起"
        )

        app.buttons["我的名片"].tap()
        XCTAssertTrue(app.buttons["名片夹"].waitForExistence(timeout: 3))
        app.buttons["名片夹"].tap()

        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: true),
            "从其他页面返回列表页时顶部导航必须以展开状态出现"
        )
        // Keep the visual proof outside AppShell's page cross-fade window.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        attachScreenshot(named: "04-returned-list-header-expanded")
    }

    func testListHeaderCannotCollapseUntilAListIsExpanded() throws {
        enterListMode()

        let window = app.windows.firstMatch
        for cycle in 1...5 {
            window.swipeUp(velocity: .fast)
            XCTAssertTrue(
                waitForVisibleButton("添加列表", expected: true),
                "全部列表收起时，第 \(cycle) 次上滑不应收起顶部导航"
            )
        }

        let uncategorizedRow = uncategorizedListRow()
        XCTAssertTrue(uncategorizedRow.waitForExistence(timeout: 3))
        uncategorizedRow.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        window.swipeUp(velocity: .fast)
        XCTAssertTrue(
            waitForVisibleButton("添加列表", expected: false),
            "列表展开后，上滑仍应允许顶部导航收起"
        )
    }

    func testUserListCollapseReturnsToInitialOffsetAndExpandsHeader() throws {
        enterListMode()

        let window = app.windows.firstMatch
        let initialRow = uncategorizedListRow()
        XCTAssertTrue(initialRow.waitForExistence(timeout: 3))
        let initialRowMinY = initialRow.frame.minY

        for cycle in 1...3 {
            let collapsedRow = uncategorizedListRow()
            XCTAssertTrue(collapsedRow.waitForExistence(timeout: 2))
            collapsedRow.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            window.swipeUp(velocity: .fast)
            XCTAssertTrue(
                waitForVisibleButton("添加列表", expected: false),
                "第 \(cycle) 次展开并上滑后，顶部导航应进入收起状态"
            )

            let expandedRow = uncategorizedListRow()
            XCTAssertTrue(expandedRow.waitForExistence(timeout: 2))
            XCTAssertTrue(expandedRow.isHittable)
            expandedRow.tap()

            XCTAssertTrue(
                waitForVisibleButton("添加列表", expected: true),
                "第 \(cycle) 次点击收起时，顶部导航应同步展开"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            let resetRow = uncategorizedListRow()
            XCTAssertTrue(resetRow.waitForExistence(timeout: 2))
            XCTAssertEqual(
                resetRow.frame.minY,
                initialRowMinY,
                accuracy: 3,
                "第 \(cycle) 次点击收起后，列表应回到初始滚动位置"
            )
        }
    }

    func testRapidModeSwitchingAndScrollingKeepsChromeHeadersAndCardsVisible() throws {
        enterCardHolder()

        let window = app.windows.firstMatch
        let modeSequence = ["公司", "列表", "姓名"]

        for cycle in 0..<9 {
            let label = modeSequence[cycle % modeSequence.count]
            let modeButton = app.buttons[label]
            XCTAssertTrue(modeButton.waitForExistence(timeout: 2), "缺少模式按钮：\(label)")
            modeButton.tap()
            window.swipeUp(velocity: .fast)
            window.swipeDown(velocity: .fast)
        }

        assertModeChromeIsVisibleAndInsideCanvas()

        app.buttons["姓名"].tap()
        app.buttons["跳转到 \(seededNameGroup)"].tap()
        XCTAssertTrue(waitForVisibleText(seededNameGroup), "姓名模式分组标题应保持可见")
        XCTAssertTrue(waitForVisibleText(seededReceivedCardName), "姓名模式名片文字应保持可见")

        app.buttons["公司"].tap()
        app.buttons["跳转到 \(seededOrganizationGroup)"].tap()
        XCTAssertTrue(waitForVisibleText(seededOrganizationGroup), "公司模式分组标题应保持可见")
        XCTAssertTrue(waitForVisibleText(seededReceivedCardName), "公司模式名片文字应保持可见")

        attachScreenshot(named: "05-after-rapid-mode-scroll-stress")
    }

    func testModeTabsAcceptTapsAcrossFullLabelSurface() throws {
        enterCardHolder()

        tapCanvasPoint(x: 285, y: 145)
        XCTAssertTrue(app.buttons["跳转到 \(seededOrganizationGroup)"].waitForExistence(timeout: 2))
        app.buttons["跳转到 \(seededOrganizationGroup)"].tap()
        XCTAssertTrue(
            waitForVisibleText(seededReceivedCardName),
            "点击公司标签的非文字区域后应切换到公司模式"
        )

        tapCanvasPoint(x: 20, y: 145)
        XCTAssertTrue(
            app.buttons["添加列表"].waitForExistence(timeout: 2),
            "点击列表标签的非文字区域后应切换到列表模式"
        )

        tapCanvasPoint(x: 150, y: 145)
        XCTAssertTrue(app.buttons["跳转到 \(seededNameGroup)"].waitForExistence(timeout: 2))
        app.buttons["跳转到 \(seededNameGroup)"].tap()
        XCTAssertTrue(
            waitForVisibleText(seededReceivedCardName),
            "点击姓名标签的非文字区域后应切换到姓名模式"
        )

        attachScreenshot(named: "06-mode-tabs-full-label-hit-area")
    }

    func testListMultiSelectionCanClearAndExitIndependently() throws {
        enterListMode()

        let listRow = uncategorizedListRow()
        XCTAssertTrue(listRow.waitForExistence(timeout: 3))
        listRow.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        XCTAssertTrue(waitForVisibleText("名片夹"))
        app.buttons["多选"].tap()
        XCTAssertTrue(app.buttons["退出"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["取消选择"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["添加列表"].exists)
        XCTAssertTrue(
            waitForVisibleText("已选择 (0)"),
            "进入多选后标题应显示当前选择数量 0"
        )

        var card = firstMultiSelectCard()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertEqual(card.value as? String, "未选择")
        let cardIdentifier = card.identifier
        card.tap()

        XCTAssertTrue(waitForCardValue(identifier: cardIdentifier, expected: "已选择"))
        XCTAssertTrue(
            waitForVisibleText("已选择 (1)"),
            "选择一张名片后标题数量应更新为 1"
        )
        card = app.buttons[cardIdentifier]
        XCTAssertEqual(
            uncategorizedListRow().value as? String,
            "包含已选名片",
            "包含已选名片的列表应进入选中提示状态"
        )
        attachScreenshot(named: "07-list-multi-selection-badge")

        app.buttons["取消选择"].tap()
        XCTAssertTrue(app.buttons["退出"].exists, "取消选择后应保留多选模式")
        XCTAssertTrue(
            waitForVisibleText("已选择 (0)"),
            "清空选择后标题数量应恢复为 0"
        )
        XCTAssertEqual(firstMultiSelectCard().value as? String, "未选择")
        XCTAssertEqual(uncategorizedListRow().value as? String, "未包含已选名片")

        firstMultiSelectCard().tap()
        app.buttons["退出"].tap()
        XCTAssertTrue(app.buttons["多选"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["添加列表"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["取消选择"].exists)
        XCTAssertTrue(waitForVisibleText("名片夹"), "退出多选后应恢复名片夹标题")

        app.buttons["多选"].tap()
        XCTAssertEqual(firstMultiSelectCard().value as? String, "未选择")
        XCTAssertTrue(waitForVisibleText("已选择 (0)"))
        attachScreenshot(named: "07-list-multi-selection-cleared")
    }

    func testSelectedCardsMoveAsOneBatch() throws {
        enterListMode()

        let sourceRow = uncategorizedListRow()
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 3))
        sourceRow.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        app.buttons["多选"].tap()
        let selectableCards = visibleMultiSelectCards()
        XCTAssertGreaterThanOrEqual(selectableCards.count, 2)

        let firstCard = selectableCards[0]
        let secondCard = selectableCards[1]
        firstCard.tap()
        secondCard.tap()
        XCTAssertEqual(firstCard.value as? String, "已选择")
        XCTAssertEqual(secondCard.value as? String, "已选择")

        guard let targetRow = visibleTargetListRow(excluding: sourceRow.identifier) else {
            XCTFail("缺少可见的目标列表，无法验证批量拖放")
            return
        }
        let targetIdentifier = targetRow.identifier
        let initialTargetCount = listCount(from: targetRow.label)

        firstCard.press(
            forDuration: 0.75,
            thenDragTo: targetRow,
            withVelocity: .slow,
            thenHoldForDuration: 0.15
        )

        XCTAssertTrue(
            waitForListCount(
                identifier: targetIdentifier,
                expected: initialTargetCount + 2
            ),
            "两张已选名片应在一次拖放中移入目标列表"
        )
        XCTAssertTrue(app.buttons["退出"].exists, "移动成功后应继续停留在多选模式")
        XCTAssertEqual(
            app.buttons[targetIdentifier].value as? String,
            "未包含已选名片",
            "实际移入目标列表的名片应自动取消选择"
        )
        XCTAssertEqual(
            uncategorizedListRow().value as? String,
            "未包含已选名片",
            "来源列表不应继续保留已移动名片的选中状态"
        )
        attachScreenshot(named: "08-list-batch-move")
    }

    private func enterExpandedListMode() {
        enterListMode()

        let uncategorizedRow = uncategorizedListRow()
        XCTAssertTrue(uncategorizedRow.waitForExistence(timeout: 3))
        uncategorizedRow.tap()

        // Let the real list-height animation finish before the first gesture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func enterListMode() {
        let holderTab = app.buttons["名片夹"]
        XCTAssertTrue(holderTab.waitForExistence(timeout: 3))
        holderTab.tap()

        let listModeButton = app.buttons["列表"]
        XCTAssertTrue(listModeButton.waitForExistence(timeout: 3))
        listModeButton.tap()
        XCTAssertTrue(app.buttons["添加列表"].waitForExistence(timeout: 3))
    }

    private func uncategorizedListRow() -> XCUIElement {
        return app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "未分类（"))
            .firstMatch
    }

    private func listRow(named name: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(name)（"))
            .firstMatch
    }

    private func visibleTargetListRow(excluding sourceIdentifier: String) -> XCUIElement? {
        let canvas = app.windows.firstMatch.frame
        return app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-holder-list-"))
            .allElementsBoundByIndex
            .first { row in
                row.exists
                    && row.isHittable
                    && row.identifier != sourceIdentifier
                    && row.frame.intersects(canvas)
            }
    }

    private func listCount(from label: String) -> Int {
        guard
            let open = label.lastIndex(of: "（"),
            let close = label.lastIndex(of: "）"),
            open < close
        else {
            return 0
        }
        return Int(label[label.index(after: open)..<close]) ?? 0
    }

    private func waitForListCount(
        named name: String,
        expected: Int,
        timeout: TimeInterval = 4
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let row = listRow(named: name)
            if row.exists, listCount(from: row.label) == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func waitForListCount(
        identifier: String,
        expected: Int,
        timeout: TimeInterval = 4
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let row = app.buttons[identifier]
            if row.exists, listCount(from: row.label) == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func firstMultiSelectCard() -> XCUIElement {
        visibleMultiSelectCards().first ?? app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "cardHolder.multiSelect.card."
                )
            )
            .firstMatch
    }

    private func visibleMultiSelectCards() -> [XCUIElement] {
        let sourceRowBottom = uncategorizedListRow().frame.maxY
        let canvas = app.windows.firstMatch.frame
        return app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "cardHolder.multiSelect.card."
                )
            )
            .allElementsBoundByIndex
            .filter {
                $0.isHittable
                    && $0.frame.minY >= sourceRowBottom - 1
                    && $0.frame.intersects(canvas)
            }
    }

    private func waitForCardValue(
        identifier: String,
        expected: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let card = app.buttons[identifier]
            if card.exists, card.value as? String == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func enterCardHolder() {
        let holderTab = app.buttons["名片夹"]
        XCTAssertTrue(holderTab.waitForExistence(timeout: 3))
        holderTab.tap()
        XCTAssertTrue(app.buttons["姓名"].waitForExistence(timeout: 3))
    }

    private func assertModeChromeIsVisibleAndInsideCanvas() {
        let canvas = app.windows.firstMatch.frame
        XCTAssertTrue(waitForVisibleText("名片夹"), "名片夹标题应保持可见")

        for label in ["列表", "姓名", "公司"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.exists, "缺少模式按钮：\(label)")
            XCTAssertFalse(button.frame.isEmpty, "模式按钮 frame 为空：\(label)")
            XCTAssertTrue(button.frame.intersects(canvas), "模式按钮移出画板：\(label)")
        }
    }

    private func tapCanvasPoint(x: CGFloat, y: CGFloat) {
        let window = app.windows.firstMatch
        let frame = window.frame
        window.coordinate(
            withNormalizedOffset: CGVector(
                dx: x / frame.width,
                dy: y / frame.height
            )
        )
        .tap()
    }

    private func waitForVisibleText(
        _ label: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let canvas = app.windows.firstMatch.frame
            let hasVisibleMatch = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
                .contains { element in
                    element.exists
                        && !element.frame.isEmpty
                        && element.frame.intersects(canvas)
                }
            if hasVisibleMatch {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func waitForVisibleButton(
        _ label: String,
        expected: Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Rebuild the query on every pass. SwiftUI removes the accessibility
            // label when the complete header is outside the hit region, and a
            // retained XCUIElement can otherwise keep a stale pre-animation frame.
            let matches = app.buttons
                .matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
            let hasVisibleMatch = matches.contains { element in
                element.exists
                    && element.isHittable
                    && element.frame.intersects(app.windows.firstMatch.frame)
            }
            if hasVisibleMatch == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var listHeaderTitleRect: CGRect {
        CGRect(x: 155, y: 72, width: 92, height: 32)
    }

    private func darkPixelCount(
        in canvasRect: CGRect,
        screenshot: XCUIScreenshot
    ) -> Int {
        guard let cgImage = screenshot.image.cgImage else { return 0 }

        let canvasFrame = app.windows.firstMatch.frame
        guard canvasFrame.width > 0, canvasFrame.height > 0 else { return 0 }

        let scaleX = CGFloat(cgImage.width) / canvasFrame.width
        let scaleY = CGFloat(cgImage.height) / canvasFrame.height
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: cgImage.width,
            height: cgImage.height
        )
        let pixelRect = CGRect(
            x: (canvasRect.minX - canvasFrame.minX) * scaleX,
            y: (canvasRect.minY - canvasFrame.minY) * scaleY,
            width: canvasRect.width * scaleX,
            height: canvasRect.height * scaleY
        )
        .integral
        .intersection(imageBounds)

        guard
            !pixelRect.isEmpty,
            let croppedImage = cgImage.cropping(to: pixelRect)
        else {
            return 0
        }

        let width = croppedImage.width
        let height = croppedImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        return pixels.withUnsafeMutableBytes { buffer in
            guard
                let baseAddress = buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else {
                return 0
            }

            context.draw(
                croppedImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )

            var count = 0
            for pixelOffset in stride(from: 0, to: buffer.count, by: 4) {
                let red = Int(buffer[pixelOffset])
                let green = Int(buffer[pixelOffset + 1])
                let blue = Int(buffer[pixelOffset + 2])
                let alpha = Int(buffer[pixelOffset + 3])
                if alpha > 200, red < 96, green < 96, blue < 96 {
                    count += 1
                }
            }
            return count
        }
    }
}
