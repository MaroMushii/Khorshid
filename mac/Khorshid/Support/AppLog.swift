import os

/// Topic-keyed `Logger` instances for the app. All entries share the
/// `dev.MaroMushii.Khorshid` subsystem so `log show --predicate
/// 'subsystem == "dev.MaroMushii.Khorshid"'` picks them up regardless of
/// category. Tail any one category via `just logs <category>`.
///
/// Privacy note: unlike Pigeon (public channels only), Khorshid handles
/// encrypted content and keypair material. Never log ciphertext, private
/// keys, PAT values, or decrypted post bodies — even at .debug level.
/// Use `.pub(...)` only for IDs, counts, and status strings that contain
/// no PII or secret material.
enum AppLog {
    private static let subsystem = "dev.MaroMushii.Khorshid"

    /// Feed content lifecycle: Today feed init, refresh, hot-score updates.
    static let feed     = Logger(subsystem: subsystem, category: "Feed")
    /// MirrorClient: snapshot fetch, index, health.json, schema-version checks.
    static let mirror   = Logger(subsystem: subsystem, category: "Mirror")
    /// Networking: URLSession, retry logic, rate-limit backoff.
    static let net      = Logger(subsystem: subsystem, category: "Net")
    /// Identity: keypair generation, Keychain read/write, public-key derivation.
    static let identity = Logger(subsystem: subsystem, category: "Identity")
    /// Social layer: PAT pool selection, GitHub Issues API, comments, votes.
    static let social   = Logger(subsystem: subsystem, category: "Social")
    /// View lifecycle: channel switch, navigation, app launch/terminate.
    static let mount    = Logger(subsystem: subsystem, category: "Mount")

    /// Signposter for `os_signpost` intervals. Visible in Instruments under
    /// Points of Interest. Use for feed refresh, mirror fetch, key generation.
    static let signpost = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}

extension Logger {
    /// Log a `.notice`-level message with the entire interpolation marked
    /// `privacy: .public`. Use only for non-sensitive strings: IDs, counts,
    /// status codes — never ciphertext, keys, or PAT values.
    func pub(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }
}
