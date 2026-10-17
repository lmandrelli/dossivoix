import XCTest
@testable import DossivoixCore

final class PhrasesTests: XCTestCase {
    func testReadResultAnnouncesFolderName() throws {
        let decoded = TagDecoder.decode(try NDEFCodec.decode(Fixtures.smartVisionMessage))
        XCTAssertEqual(Phrases.readResult(decoded), "Dossier panneau solaire")
    }

    func testReadResultMentionsUnrecognizedParts() {
        let external = NDEFRecord(typeNameFormat: .external, type: Data("a:b".utf8), payload: Data([1]))
        let decoded = TagDecoder.decode([Fixtures.mediaText("Banque"), external])
        XCTAssertEqual(Phrases.readResult(decoded),
                       "Banque. Cette étiquette contient aussi des informations non reconnues.")
    }

    func testReadResultEmptyAndUnrecognized() {
        XCTAssertEqual(Phrases.readResult(TagDecoder.decode([])), "Étiquette vide.")
        let uri = NDEFRecord(typeNameFormat: .wellKnown, type: Data("U".utf8), payload: Data([0]))
        XCTAssertEqual(Phrases.readResult(TagDecoder.decode([uri])), "Étiquette d'un format non reconnu.")
    }

    func testCancelMessageDependsOnOperation() {
        XCTAssertEqual(Phrases.message(for: .userCanceled, during: .reading), "Lecture annulée.")
        XCTAssertEqual(Phrases.message(for: .userCanceled, during: .writing), "Écriture annulée.")
    }

    func testEveryErrorHasAMessage() {
        let errors: [TagError] = [
            .readingUnavailable, .userCanceled, .timeout, .systemBusy, .tagRemoved, .unreadable,
            .notNDEFCompatible, .readOnly, .insufficientCapacity(maxMessageLength: 137), .writeFailed,
            .differentTag, .unknown("x"),
        ]
        for error in errors {
            XCTAssertFalse(Phrases.message(for: error, during: .reading).isEmpty, "\(error)")
        }
    }
}
