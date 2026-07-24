import XCTest

final class LinkedApplicationsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CARDA_SIMULATE_LINKED_APPS"] = "1"
        app.launchEnvironment["CARDA_ENABLE_EXCHANGE_SIMULATION"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSettingsContainsOnlyTheFiveConfirmedGroupsAndPersistsExchangePreference() throws {
        let avatar = app.buttons["用户头像"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 4))
        avatar.tap()

        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        for title in ["名片交换", "名片管理", "数据与存储", "交互与辅助功能", "帮助与关于"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 2), "缺少设置分组：\(title)")
        }
        XCTAssertTrue(app.staticTexts["名片"].exists)
        XCTAssertTrue(app.staticTexts["通用"].exists)
        XCTAssertFalse(app.buttons["隐私与安全"].exists)
        XCTAssertFalse(app.buttons["通知"].exists)
        attachScreenshot(named: "settings-two-titled-sections")

        app.buttons["名片交换"].tap()
        let discoverability = app.switches["允许附近的 Cardi 用户发现我"]
        XCTAssertTrue(discoverability.waitForExistence(timeout: 2))
        let originalValue = discoverability.value as? String
        discoverability.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let didUpdate = NSPredicate { object, _ in
            (object as? XCUIElement)?.value as? String != originalValue
        }
        expectation(for: didUpdate, evaluatedWith: discoverability)
        waitForExpectations(timeout: 2)
        let updatedValue = discoverability.value as? String
        XCTAssertNotEqual(originalValue, updatedValue)

        let backButton = app.buttons["返回"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        let backButtonIsHittable = NSPredicate(format: "hittable == true")
        expectation(for: backButtonIsHittable, evaluatedWith: backButton)
        waitForExpectations(timeout: 2)
        backButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["名片交换"].waitForExistence(timeout: 4))
        app.buttons["名片交换"].tap()
        XCTAssertTrue(discoverability.waitForExistence(timeout: 2))
        XCTAssertEqual(discoverability.value as? String, updatedValue)

        discoverability.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    func testExchangeDiagnosticsIsAlwaysVisibleAndStartsRecording() throws {
        let avatar = app.buttons["用户头像"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 4))
        avatar.tap()

        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 3))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["帮助与关于"].waitForExistence(timeout: 2))
        app.buttons["帮助与关于"].tap()

        let diagnostics = app.buttons["交换诊断"]
        XCTAssertTrue(
            diagnostics.waitForExistence(timeout: 2),
            "交换诊断应作为帮助与关于中的常驻入口"
        )
        diagnostics.tap()

        let testCode = app.textFields["diagnostics.testCode"]
        XCTAssertTrue(testCode.waitForExistence(timeout: 2))
        testCode.tap()
        testCode.typeText("123456")

        let start = app.buttons["开始记录"]
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(
            app.staticTexts["我的名片"].waitForExistence(timeout: 3),
            "开始诊断后应自动关闭账户 Sheet 并返回我的名片"
        )

        avatar.tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 3))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["帮助与关于"].waitForExistence(timeout: 2))
        app.buttons["帮助与关于"].tap()
        XCTAssertTrue(app.buttons["交换诊断"].waitForExistence(timeout: 2))
        app.buttons["交换诊断"].tap()
        XCTAssertTrue(app.staticTexts["记录中"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["结束本次记录"].exists)

        app.buttons["结束本次记录"].tap()
        XCTAssertTrue(app.staticTexts["已停止"].waitForExistence(timeout: 2))
        app.swipeUp()
        let export = app.buttons["导出诊断 JSON"]
        XCTAssertTrue(export.waitForExistence(timeout: 2))
        XCTAssertTrue(export.isEnabled)
    }

    func testBrowserListAndResetDefaultsStayInsideTheAccountSheet() throws {
        let avatar = app.buttons["用户头像"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 4))
        avatar.tap()

        let linkedApplications = app.buttons["关联应用"]
        XCTAssertTrue(linkedApplications.waitForExistence(timeout: 3))
        attachScreenshot(named: "account-sheet-grouped-actions")
        linkedApplications.tap()

        let browser = app.buttons["浏览器"]
        let mail = app.buttons["邮箱"]
        let maps = app.buttons["地图"]
        let reset = app.buttons["恢复默认设置"]
        XCTAssertTrue(browser.waitForExistence(timeout: 3))
        XCTAssertTrue(mail.exists)
        XCTAssertTrue(maps.exists)
        XCTAssertTrue(reset.exists)
        attachScreenshot(named: "linked-applications-overview")

        browser.tap()
        for name in [
            "Safari",
            "Google Chrome",
            "夸克浏览器",
            "QQ浏览器",
            "Microsoft Edge",
            "UC浏览器"
        ] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 2), "缺少浏览器选项：\(name)")
        }
        attachScreenshot(named: "linked-applications-browsers")

        app.buttons["Google Chrome"].tap()
        XCTAssertTrue(browser.waitForExistence(timeout: 2))
        XCTAssertEqual(browser.value as? String, "Google Chrome")

        reset.tap()
        let alert = app.alerts["恢复默认设置？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["取消"].tap()
        XCTAssertEqual(browser.value as? String, "Google Chrome")

        reset.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["恢复"].tap()
        XCTAssertEqual(browser.value as? String, "Safari")
        XCTAssertEqual(mail.value as? String, "邮件")
        XCTAssertEqual(maps.value as? String, "Apple 地图")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["用户头像"].waitForExistence(timeout: 4))
        app.buttons["用户头像"].tap()
        XCTAssertTrue(app.buttons["关联应用"].waitForExistence(timeout: 3))
        app.buttons["关联应用"].tap()

        XCTAssertEqual(app.buttons["浏览器"].value as? String, "Safari")
        XCTAssertEqual(app.buttons["邮箱"].value as? String, "邮件")
        XCTAssertEqual(app.buttons["地图"].value as? String, "Apple 地图")
    }

    func testMailPickerKeepsEverySupportedMailApplicationSelectable() throws {
        XCTAssertTrue(app.buttons["用户头像"].waitForExistence(timeout: 4))
        app.buttons["用户头像"].tap()
        XCTAssertTrue(app.buttons["关联应用"].waitForExistence(timeout: 3))
        app.buttons["关联应用"].tap()
        XCTAssertTrue(app.buttons["邮箱"].waitForExistence(timeout: 3))
        app.buttons["邮箱"].tap()

        for name in ["邮件", "QQ 邮箱", "网易邮箱大师", "Outlook", "Gmail"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 2), "缺少邮箱选项：\(name)")
        }
        attachScreenshot(named: "linked-applications-mail-without-icons")
    }

    func testRegistrationNoticeFollowsSubmitButtonWithoutOverlap() throws {
        app.terminate()
        app.launchEnvironment["CARDA_RESET_ACCOUNT_PROFILE"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["用户头像"].waitForExistence(timeout: 4))
        app.buttons["用户头像"].tap()

        let account = app.buttons["账户信息"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        XCTAssertTrue(app.staticTexts["登录 / 注册"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["注册"].tap()

        let submit = app.buttons["注册账户"]
        let notice = app.staticTexts["本地登录说明"]
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        XCTAssertTrue(notice.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(
            submit.frame.maxY,
            notice.frame.minY,
            "注册页说明文字不得与提交按钮重合"
        )
        attachScreenshot(named: "local-account-registration-footer-layout")
    }

    func testLocalAccountSavesLogsOutAndRestoresCardsByPhoneNumber() throws {
        let phoneNumber = "139\(String(Int(Date().timeIntervalSince1970)).suffix(8))"
        let password = "Carda-local-2026"

        app.terminate()
        app.launchEnvironment["CARDA_RESET_ACCOUNT_PROFILE"] = "1"
        app.launchEnvironment["CARDA_SEED_LOCAL_ACCOUNT_TEST_DATA"] = "1"
        app.launchEnvironment["CARDA_LOCAL_ACCOUNT_TEST_PHONE"] = phoneNumber
        app.launch()

        XCTAssertTrue(app.buttons["用户头像"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.descendants(matching: .any)["本地归档测试名片"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["用户头像"].tap()

        let account = app.buttons["账户信息"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertEqual(account.value as? String, "未登陆")
        account.tap()

        XCTAssertTrue(app.staticTexts["登录 / 注册"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls.buttons["登录"].exists)
        app.segmentedControls.buttons["注册"].tap()

        let registrationPhoneField = app.textFields["手机号"]
        let registrationPasswordField = app.secureTextFields["密码"]
        let passwordConfirmationField = app.secureTextFields["确认密码"]
        XCTAssertTrue(registrationPhoneField.exists)
        XCTAssertTrue(registrationPasswordField.exists)
        XCTAssertTrue(passwordConfirmationField.exists)
        registrationPhoneField.tap()
        registrationPhoneField.typeText(phoneNumber)
        registrationPasswordField.tap()
        registrationPasswordField.typeText(password)
        passwordConfirmationField.tap()
        passwordConfirmationField.typeText(password)
        attachScreenshot(named: "local-account-registration")
        app.buttons["注册账户"].tap()

        XCTAssertTrue(app.staticTexts["修改信息"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["添加头像"].exists)
        attachScreenshot(named: "account-profile-editor")

        let nameField = app.textFields["昵称"]
        let emailField = app.textFields["邮箱"]
        XCTAssertTrue(nameField.exists)
        XCTAssertFalse(app.textFields["手机号"].exists)
        XCTAssertTrue(app.staticTexts["手机号"].exists)
        XCTAssertTrue(emailField.exists)
        nameField.tap()
        nameField.typeText("Cardi 用户")
        emailField.tap()
        emailField.typeText("user@carda.local")

        let save = app.buttons["保存账户资料"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertEqual(account.value as? String, "Cardi 用户，user@carda.local")

        let logout = app.buttons["退出登录"]
        XCTAssertTrue(logout.exists)
        logout.tap()
        let logoutAlert = app.alerts["退出登录？"]
        XCTAssertTrue(logoutAlert.waitForExistence(timeout: 2))
        logoutAlert.buttons["退出"].tap()

        XCTAssertTrue(app.buttons["创建第一张名片"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any)["本地归档测试名片"].exists)
        attachScreenshot(named: "my-cards-empty-state-plus")

        app.buttons["用户头像"].tap()
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertEqual(account.value as? String, "未登陆")
        account.tap()

        XCTAssertTrue(app.staticTexts["登录 / 注册"].waitForExistence(timeout: 3))
        let loginPhoneField = app.textFields["手机号"]
        let loginPasswordField = app.secureTextFields["密码"]
        XCTAssertTrue(loginPhoneField.exists)
        XCTAssertTrue(loginPasswordField.exists)
        XCTAssertFalse(app.secureTextFields["确认密码"].exists)
        loginPhoneField.tap()
        loginPhoneField.typeText(phoneNumber)
        loginPasswordField.tap()
        loginPasswordField.typeText(password)
        app.buttons["登录账户"].tap()

        XCTAssertTrue(app.staticTexts["修改信息"].waitForExistence(timeout: 3))
        let restoredNameField = app.textFields["昵称"]
        let restoredEmailField = app.textFields["邮箱"]
        XCTAssertEqual(restoredNameField.value as? String, "Cardi 用户")
        XCTAssertEqual(restoredEmailField.value as? String, "user@carda.local")
        app.buttons["保存账户资料"].tap()

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)
                )
            )
        if account.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
                .press(
                    forDuration: 0.1,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)
                    )
                )
        }
        XCTAssertTrue(account.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["本地归档测试名片"]
                .waitForExistence(timeout: 4)
        )

        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.isHittable)
        cardHolder.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["本地归档测试联系人"]
                .waitForExistence(timeout: 4)
        )
    }

    func testSearchEntryKeepsRestingGlassSurfacesSeparated() throws {
        app.launch()

        let search = app.buttons["搜索"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        XCTAssertTrue(search.isHittable)
        search.tap()

        XCTAssertTrue(app.staticTexts["最近添加"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1)
        attachScreenshot(named: "search-resting-glass-surfaces")
    }

    func testMyCardsAndCardHolderShareTheSameAvatarEndpointGeometry() throws {
        app.terminate()
        app.launchEnvironment["CARDA_RESET_ACCOUNT_PROFILE"] = "1"
        app.launchEnvironment["CARDA_SEED_ACCOUNT_AVATAR"] = "1"
        app.launch()

        let myCardsAvatar = app.buttons["my-cards-account-avatar-button"]
        XCTAssertTrue(myCardsAvatar.waitForExistence(timeout: 4))
        XCTAssertEqual(myCardsAvatar.value as? String, "已设置头像")
        let myCardsAvatarFrame = myCardsAvatar.frame
        XCTAssertEqual(myCardsAvatarFrame.width, 44, accuracy: 2)
        XCTAssertEqual(myCardsAvatarFrame.height, 44, accuracy: 2)
        attachScreenshot(named: "my-cards-shared-account-avatar")

        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.isHittable)
        cardHolder.tap()

        let nameMode = app.buttons["姓名"]
        XCTAssertTrue(nameMode.waitForExistence(timeout: 3))
        nameMode.tap()

        let cardHolderAvatar = app.buttons["card-holder-morphing-avatar-list-control"]
        XCTAssertTrue(cardHolderAvatar.waitForExistence(timeout: 3))
        XCTAssertEqual(cardHolderAvatar.value as? String, "已设置头像")
        XCTAssertEqual(cardHolderAvatar.frame.width, myCardsAvatarFrame.width, accuracy: 2)
        XCTAssertEqual(cardHolderAvatar.frame.height, myCardsAvatarFrame.height, accuracy: 2)
        attachScreenshot(named: "card-holder-shared-account-avatar")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "CARDA_SEED_ACCOUNT_AVATAR")
        app.launch()
        Thread.sleep(forTimeInterval: 1)
    }

    func testCardHolderShowsRestoredSoftBottomEdge() throws {
        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.waitForExistence(timeout: 4))
        XCTAssertTrue(cardHolder.isHittable)
        cardHolder.tap()

        XCTAssertTrue(app.staticTexts["名片夹"].waitForExistence(timeout: 3))
        let nameMode = app.buttons["姓名"]
        XCTAssertTrue(nameMode.waitForExistence(timeout: 3))
        nameMode.tap()

        let window = app.windows.firstMatch
        window.swipeUp()
        window.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        attachScreenshot(named: "card-holder-restored-soft-bottom-edge")
    }

    func testFirstCardHolderEntryDefaultsToNameMode() throws {
        app.terminate()
        app.launchEnvironment["CARDA_RESET_DEFAULT_CARD_SORT"] = "1"
        app.launch()

        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.waitForExistence(timeout: 4))
        XCTAssertTrue(cardHolder.isHittable)
        cardHolder.tap()

        let nameMode = app.buttons["card-holder-mode-姓名"]
        let listMode = app.buttons["card-holder-mode-列表"]
        XCTAssertTrue(nameMode.waitForExistence(timeout: 3))
        XCTAssertEqual(nameMode.value as? String, "已选择")
        XCTAssertEqual(listMode.value as? String, "未选择")
        XCTAssertFalse(app.buttons["添加列表"].exists)
        attachScreenshot(named: "card-holder-first-entry-name-mode")
    }

    func testCardHolderNameToListHeaderMorphKeepsOneContinuousHeader() throws {
        let cardHolder = app.buttons["名片夹"]
        XCTAssertTrue(cardHolder.waitForExistence(timeout: 4))
        XCTAssertTrue(cardHolder.isHittable)
        cardHolder.tap()

        let nameMode = app.buttons["姓名"]
        XCTAssertTrue(nameMode.waitForExistence(timeout: 3))
        nameMode.tap()
        Thread.sleep(forTimeInterval: 0.8)

        let holderTitle = app.staticTexts["名片夹"].firstMatch
        XCTAssertTrue(holderTitle.waitForExistence(timeout: 2))
        let groupedTitleFrame = holderTitle.frame

        let listMode = app.buttons["列表"]
        XCTAssertTrue(listMode.waitForExistence(timeout: 2))
        listMode.tap()

        let addList = app.buttons["添加列表"]
        let multiSelect = app.buttons["多选"]
        XCTAssertTrue(addList.waitForExistence(timeout: 2))
        let addListIsHittable = NSPredicate(format: "hittable == true")
        expectation(for: addListIsHittable, evaluatedWith: addList)
        waitForExpectations(timeout: 2)
        let morphingRightControl = app.buttons["card-holder-morphing-avatar-list-control"]
        XCTAssertTrue(morphingRightControl.exists)
        XCTAssertTrue(multiSelect.exists)
        XCTAssertTrue(multiSelect.isHittable)

        let listTitleFrame = holderTitle.frame
        XCTAssertGreaterThan(
            listTitleFrame.midX,
            groupedTitleFrame.midX + 60,
            "标题应作为同一个元素从左侧缩放移动到顶部居中位置"
        )
        XCTAssertEqual(listTitleFrame.midX, 201, accuracy: 10)
        XCTAssertEqual(morphingRightControl.frame.width, 112, accuracy: 4)
        XCTAssertEqual(morphingRightControl.frame.height, 46, accuracy: 4)
        attachScreenshot(named: "card-holder-name-to-list-header-morph")

        nameMode.tap()
        XCTAssertTrue(morphingRightControl.waitForExistence(timeout: 2))
        let avatarIsHittable = NSPredicate(format: "hittable == true")
        expectation(for: avatarIsHittable, evaluatedWith: morphingRightControl)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(morphingRightControl.frame.width, 44, accuracy: 4)
        XCTAssertEqual(morphingRightControl.frame.height, 44, accuracy: 4)
        attachScreenshot(named: "card-holder-list-to-name-header-morph")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
