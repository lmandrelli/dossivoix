import Foundation

/// Capacité des étiquettes.
public enum TagCapacity {
    /// Mémoire utilisateur d'une NTAG 213, en octets.
    public static let ntag213UserMemory = 144

    /// Taille maximale d'un message NDEF pour une mémoire utilisateur donnée.
    /// Le message est rangé dans un bloc TLV : type 0x03, longueur (1 octet, ou 3 au-delà de 254),
    /// le message, puis le terminateur 0xFE.
    public static func maxMessageLength(userMemory: Int) -> Int {
        let withShortLength = userMemory - 3
        if withShortLength < 255 { return max(withShortLength, 0) }
        return userMemory - 5
    }

    /// 141 octets pour une NTAG 213. Sert à vérifier le nom avant d'approcher l'étiquette ;
    /// la capacité réelle donnée par l'étiquette est revérifiée au moment de l'écriture.
    public static let ntag213MaxMessageLength = maxMessageLength(userMemory: ntag213UserMemory)
}

/// Vérifie qu'un nom de dossier tient sur l'étiquette.
public struct CapacityCheck: Equatable, Sendable {
    /// Taille du message qui serait écrit.
    public let messageLength: Int
    /// Taille maximale acceptée.
    public let maxMessageLength: Int
    /// Longueur maximale du nom, en octets UTF-8 (une lettre accentuée compte pour 2).
    public let maxNameBytes: Int

    public var fits: Bool { messageLength <= maxMessageLength }
    /// Nombre d'octets en trop (0 si le nom tient).
    public var excessBytes: Int { max(messageLength - maxMessageLength, 0) }

    public init(
        folderName: String,
        format: SmartVisionFormat = .standard,
        maxMessageLength: Int = TagCapacity.ntag213MaxMessageLength
    ) {
        let name = FolderName.cleaned(folderName)
        self.messageLength = format.messageLength(forFolderName: name)
        self.maxMessageLength = maxMessageLength
        // Tout ce qui n'est pas le nom lui-même : en-têtes, marqueur, espace final.
        let overhead = messageLength - name.utf8.count
        self.maxNameBytes = max(maxMessageLength - overhead, 0)
    }
}
