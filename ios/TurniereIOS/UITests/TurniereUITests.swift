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
        app.buttons["detail-section"].tap()
        app.buttons["Standings"].tap()
        XCTAssertTrue(app.staticTexts["6 pts"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "en-standings-dark")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFavoriteSurvivesRelaunchAndStandingsRender() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
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
        app.buttons["detail-section"].tap()
        app.buttons["Tabelle"].tap()
        capture(app, name: "de-standings-online")
        app.terminate()
        app.launchArguments = ["--demo", "--demo-offline", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        app.buttons["Meine Turniere"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Blau-Weiß"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Sommercup"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Gespeicherter Stand wird angezeigt")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["detail-section"].tap()
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
