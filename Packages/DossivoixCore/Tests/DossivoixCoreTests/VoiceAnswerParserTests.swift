import XCTest
@testable import DossivoixCore

final class VoiceAnswerParserTests: XCTestCase {
    private func assertParse(_ texts: [String], _ expected: VoiceAnswer?, file: StaticString = #filePath, line: UInt = #line) {
        for text in texts {
            XCTAssertEqual(VoiceAnswerParser.parse(text), expected, "« \(text) »", file: file, line: line)
        }
    }

    func testNormalizer() {
        XCTAssertEqual(TextNormalizer.normalize("  D’accord, C'EST ÇA ! "), "d accord c est ca")
        XCTAssertEqual(TextNormalizer.normalize("Écrire"), "ecrire")
    }

    func testYes() {
        assertParse(["Oui", "oui.", "Ouais", "D'accord", "d’accord", "C'est ça", "c'est bon", "OK",
                     "Oui c'est bon", "Exactement", "Parfait", "Remplacer", "Vas-y", "oui oui"], .yes)
    }

    func testNo() {
        assertParse(["Non", "non merci", "Ce n'est pas ça", "c'est pas ça", "Pas d'accord",
                     "Pas bon", "Garder", "nan"], .no)
    }

    func testRestart() {
        assertParse(["Recommencer", "recommence", "Refaire", "Encore une fois", "Réessayer"], .restart)
    }

    func testCancel() {
        assertParse(["Annuler", "annule", "Stop", "Arrête", "Laisse tomber"], .cancel)
    }

    func testAgainAndWrite() {
        assertParse(["Encore", "encore !", "Une autre", "Lire", "Oui encore"], .again)
        assertParse(["Écrire", "écris", "Écrire une étiquette", "Renommer", "Oui, écrire"], .write)
    }

    func testUnclearOrContradictoryAnswers() {
        assertParse(["", "euh", "panneau solaire", "non oui", "oui non"], nil)
    }

    func testStandaloneCancel() {
        XCTAssertTrue(VoiceAnswerParser.isStandaloneCancel("Annuler."))
        XCTAssertTrue(VoiceAnswerParser.isStandaloneCancel("stop"))
        XCTAssertFalse(VoiceAnswerParser.isStandaloneCancel("Annulation de contrat"))
        XCTAssertFalse(VoiceAnswerParser.isStandaloneCancel("Factures 2024"))
    }
}
