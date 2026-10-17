import Foundation

/// Format du nom de type (TNF) d'un enregistrement NDEF, codé sur 3 bits.
/// Les valeurs sont celles de la norme NFC Forum (et de `NFCTypeNameFormat` dans CoreNFC).
public enum NDEFTypeNameFormat: UInt8, Sendable, CaseIterable {
    case empty = 0x00
    case wellKnown = 0x01
    case media = 0x02
    case absoluteURI = 0x03
    case external = 0x04
    case unknown = 0x05
    case unchanged = 0x06
    case reserved = 0x07

    /// Nom lisible, utilisé dans l'écran Diagnostic.
    public var label: String {
        switch self {
        case .empty: "Vide"
        case .wellKnown: "Well-known (NFC Forum)"
        case .media: "Media (type MIME)"
        case .absoluteURI: "URI absolue"
        case .external: "Externe"
        case .unknown: "Inconnu"
        case .unchanged: "Inchangé (fragment)"
        case .reserved: "Réservé"
        }
    }
}

/// Un enregistrement NDEF, indépendant de CoreNFC.
/// L'app convertit les `NFCNDEFPayload` vers ce modèle (et inversement).
public struct NDEFRecord: Equatable, Sendable {
    public var typeNameFormat: NDEFTypeNameFormat
    public var type: Data
    public var identifier: Data
    public var payload: Data

    public init(typeNameFormat: NDEFTypeNameFormat, type: Data, identifier: Data = Data(), payload: Data) {
        self.typeNameFormat = typeNameFormat
        self.type = type
        self.identifier = identifier
        self.payload = payload
    }
}
