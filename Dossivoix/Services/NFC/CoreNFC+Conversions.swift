@preconcurrency import CoreNFC
import DossivoixCore

extension NDEFRecord {
    /// Conversion depuis un enregistrement CoreNFC.
    init(_ payload: NFCNDEFPayload) {
        self.init(
            typeNameFormat: NDEFTypeNameFormat(rawValue: payload.typeNameFormat.rawValue) ?? .unknown,
            type: payload.type,
            identifier: payload.identifier,
            payload: payload.payload
        )
    }
}

extension NFCNDEFPayload {
    /// Conversion vers un enregistrement CoreNFC, pour l'écriture.
    convenience init(_ record: NDEFRecord) {
        self.init(
            format: NFCTypeNameFormat(rawValue: record.typeNameFormat.rawValue) ?? .unknown,
            type: record.type,
            identifier: record.identifier,
            payload: record.payload
        )
    }
}

extension TagWriteStatus {
    init(_ status: NFCNDEFStatus) {
        switch status {
        case .readWrite: self = .readWrite
        case .readOnly: self = .readOnly
        default: self = .notSupported
        }
    }
}

extension TagError {
    /// Traduction d'une erreur CoreNFC en erreur simple.
    init(nfcError error: Error) {
        guard let nfcError = error as? NFCReaderError else {
            self = .unknown(error.localizedDescription)
            return
        }
        switch nfcError.code {
        case .readerSessionInvalidationErrorUserCanceled:
            self = .userCanceled
        case .readerSessionInvalidationErrorSessionTimeout:
            self = .timeout
        case .readerSessionInvalidationErrorSystemIsBusy:
            self = .systemBusy
        case .readerErrorUnsupportedFeature, .readerErrorRadioDisabled:
            self = .readingUnavailable
        case .readerTransceiveErrorTagConnectionLost,
             .readerTransceiveErrorTagNotConnected,
             .readerTransceiveErrorRetryExceeded:
            self = .tagRemoved
        case .readerTransceiveErrorTagResponseError,
             .readerTransceiveErrorPacketTooLong:
            self = .unreadable
        case .ndefReaderSessionErrorTagNotWritable:
            self = .readOnly
        case .ndefReaderSessionErrorTagSizeTooSmall:
            self = .insufficientCapacity(maxMessageLength: 0)
        case .ndefReaderSessionErrorTagUpdateFailure:
            self = .writeFailed
        default:
            self = .unknown("NFCReaderError \(nfcError.code.rawValue) : \(nfcError.localizedDescription)")
        }
    }
}

extension Error {
    /// Vrai si CoreNFC signale une étiquette sans message NDEF (étiquette vide).
    var isZeroLengthNDEFMessage: Bool {
        (self as? NFCReaderError)?.code == .ndefReaderSessionErrorZeroLengthMessage
    }
}
