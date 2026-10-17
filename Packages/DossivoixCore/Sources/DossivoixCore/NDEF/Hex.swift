import Foundation

extension Data {
    /// Crée des données à partir d'une chaîne hexadécimale, par ex. "92 0A 04" ou "920a04".
    /// Les espaces, deux-points et tirets sont ignorés. Renvoie nil si la chaîne est invalide.
    public init?(hexString: String) {
        let digits = hexString.filter { !" :-\n\t".contains($0) }
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// Représentation hexadécimale lisible : "92 0A 04".
    public var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
