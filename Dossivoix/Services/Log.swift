import os

/// Journal système (visible dans Xcode / Console.app). Rien n'est envoyé hors de l'iPhone.
enum Log {
    static let audio = Logger(subsystem: "work.lmandrelli.dossivoix", category: "audio")
    static let speech = Logger(subsystem: "work.lmandrelli.dossivoix", category: "speech")
}
