import XCTest

@MainActor
final class TurniereUITests: XCTestCase {
    func testEnglishLightAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your tournament. Your team."].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let privacy = app.descendants(matching: .any)["privacy-link"].firstMatch
        for _ in 0..<5 {
            if privacy.exists && privacy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertEqual(privacy.label, "Privacy")
        app.buttons["Done"].tap()
        app.staticTexts["Sommercup"].firstMatch.tap()
        XCTAssertTrue(app.buttons["choose-team"].waitForExistence(timeout: 5))
        app.buttons["choose-team"].tap()
        app.buttons["team-1"].tap()
        app.buttons["All team matches"].tap()
        XCTAssertTrue(app.buttons["Change team"].exists)
        capture(app, name: "en-team-light")
        app.terminate()
        app.launchArguments = ["--demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "dark"]
        app.launch()
        app.staticTexts["Sommercup"].firstMatch.tap()
        openSectionPicker(app)
        app.buttons["Standings"].tap()
        XCTAssertTrue(app.staticTexts["6 pts"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "en-standings-dark")
    }

    func testPlayerProposalsKeepOfficialScoreSeparate() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-server", "production", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.staticTexts["Sommercup"].firstMatch.tap()
        app.buttons["open-proposals"].tap()
        app.buttons["Sign in"].tap()
        app.textFields["account-email"].tap()
        app.textFields["account-email"].typeText("player@example.test")
        app.secureTextFields["account-password"].tap()
        app.secureTextFields["account-password"].typeText("password")
        app.buttons["account-sign-in"].tap()
        let first = app.textFields["proposal-score-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["proposal-submit"].isEnabled)
        first.tap(); first.typeText("7")
        let second = app.textFields["proposal-score-2"]
        second.tap(); second.typeText("10")
        app.swipeUp()
        app.buttons["proposal-submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["proposal-locked"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["proposal-submit"].exists)
        app.swipeDown()
        let official = app.descendants(matching: .any)["proposal-official-1"].firstMatch
        XCTAssertTrue(official.waitForExistence(timeout: 5))
        XCTAssertEqual(official.value as? String, "0")
        capture(app, name: "en-player-agreement")
    }

    func testFavoriteHasCourtAndOwnStandings() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-server", "production", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.staticTexts["Sommercup"].firstMatch.tap()
        app.buttons["choose-team"].tap()
        app.buttons["team-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["favorite-court"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["favorite-standings"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["6 pts"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "en-favorite-table")
    }

    private func openSectionPicker(_ app: XCUIApplication) {
        let picker = app.buttons["detail-section"]
        for _ in 0..<4 {
            if picker.exists && picker.isHittable { break }
            app.swipeDown()
        }
        picker.tap()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFavoriteSurvivesRelaunchAndStandingsRender() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance", "light"]
        app.launch()
        let tournament = app.staticTexts["Sommercup"].firstMatch
        XCTAssertTrue(tournament.waitForExistence(timeout: 10))
        tournament.tap()
        let choose = app.buttons["choose-team"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        app.buttons["team-1"].tap()
        XCTAssertTrue(app.buttons["Alle Teamspiele"].waitForExistence(timeout: 5))
        app.buttons["Alle Teamspiele"].tap()
        XCTAssertTrue(app.buttons["Team wechseln"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "favorite-team"
        attachment.lifetime = .keepAlways
        add(attachment)
        openSectionPicker(app)
        app.buttons["Tabelle"].tap()
        capture(app, name: "de-standings-online")
        app.terminate()
        app.launchArguments = ["--demo", "--demo-offline", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance", "light"]
        app.launch()
        app.buttons["Meine Turniere"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Blau-Weiß"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Sommercup"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Gespeicherter Stand wird angezeigt")).firstMatch.waitForExistence(timeout: 10))
        openSectionPicker(app)
        app.buttons["Tabelle"].tap()
        XCTAssertTrue(app.staticTexts["6 Pkt."].firstMatch.waitForExistence(timeout: 5))
        let table = XCTAttachment(screenshot: app.screenshot())
        table.name = "standings"
        table.lifetime = .keepAlways
        add(table)
    }
    func testInvalidCodeAndMissingTournament() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-AppleLanguages", "(de)"]
        app.launch()
        app.buttons["open-tournament"].tap()
        XCTAssertTrue(app.staticTexts["Bitte einen sechsstelligen Turniercode oder einen turnie.re-Turnierlink eingeben."].exists)
        app.textFields["tournament-code"].tap()
        app.textFields["tournament-code"].typeText("bad404")
        app.buttons["open-tournament"].tap()
        XCTAssertTrue(app.staticTexts["Turnier nicht geladen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Erneut versuchen"].exists)
    }
}
