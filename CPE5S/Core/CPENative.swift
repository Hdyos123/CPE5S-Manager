//
//  CPENative.swift
//  CPE5S
//
//  Native HTTP client for the Huawei CPE gateway.
//
//  Why this exists: WebKit's ITP hides HttpOnly cookies (SessionID) from
//  script-initiated fetches, so the in-page login kept failing with 125003.
//  The web view is still used to obtain the session cookie and the crypto
//  bundle is no longer needed — SCRAM-SHA256 is implemented here in Swift.
//

import Foundation
import CryptoKit

// MARK: - SCRAM helpers

enum HWScram {

    /// pbkdf2(HMAC-SHA256) -> ClientKey/StoredKey -> proof, all hex.
    static func proof(password: String,
                      saltHex: String,
                      iterations: Int,
                      authMessage: String) -> String? {
        guard let salt = Data(hexString: saltHex) else { return nil }
        let pw = Data(password.utf8)
        let key = pbkdf2SHA256(password: pw, salt: salt, iterations: iterations, keyLength: 32)

        // firmware: A(e,t) = HMAC(key = t, msg = hexToBytes(e))  → t is the KEY
        let clientKey = hmac(key: Data("Client Key".utf8), message: key)
        let storedKey = Data(SHA256.hash(data: clientKey))
        let sig = hmac(key: Data(authMessage.utf8), message: storedKey)
        let proofBytes = xor(clientKey, sig)
        return proofBytes.hexString
    }

    static func hmac(key: Data, message: Data) -> Data {
        let k = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: k))
    }

    static func xor(_ a: Data, _ b: Data) -> Data {
        Data(zip(a, b).map { $0 ^ $1 })
    }

    /// PBKDF2-HMAC-SHA256 (CommonCrypto is unavailable on non-Apple toolchains,
    /// so this is a small, correct implementation).
    static func pbkdf2SHA256(password: Data, salt: Data,
                             iterations: Int, keyLength: Int) -> Data {
        let prf = SymmetricKey(data: password)
        var derived = Data()
        var block: UInt32 = 1
        while derived.count < keyLength {
            var msg = salt
            msg.append(contentsOf: withUnsafeBytes(of: block.bigEndian) { Array($0) })
            var u = Data(HMAC<SHA256>.authenticationCode(for: msg, using: prf))
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: prf))
                    t = xor(t, u)
                }
            }
            derived.append(t)
            block += 1
        }
        return derived.prefix(keyLength)
    }
}

// MARK: - Data helpers

extension Data {
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }
        var d = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        self = d
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Native client

/// Talks to the gateway over plain HTTP with an explicit Cookie header.
final class CPENative {

    var host: String
    private let session: URLSession

    init(host: String) {
        self.host = host
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        // Let URLSession manage nothing for us: no cookie jar, no automatic
        // headers. Every request carries its own Cookie header explicitly, so
        // there is no chance of the framework overwriting our SessionID.
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        ]
        session = URLSession(configuration: cfg)
    }

    /// Set after the login page has been loaded by the web view.
    var sessionID: String = ""
    /// CSRF token (last 32 chars of /api/webserver/token).
    private(set) var token: String = ""

    private var base: URL? { URL(string: "http://\(host)") }

    // MARK: Requests

    @discardableResult
    func bootstrap() async -> Bool {
        guard let url = base else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !sessionID.isEmpty {
            req.setValue("SessionID=\(sessionID)", forHTTPHeaderField: "Cookie")
        }
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            // Always adopt the newest SessionID the gateway hands out: it must
            // match the token we are about to request.
            if let sid = Self.sessionID(from: http) {
                sessionID = sid
            }
            return !sessionID.isEmpty
        } catch {
            return false
        }
    }

    /// Pull SessionID out of any Set-Cookie header on the response.
    static func sessionID(from http: HTTPURLResponse) -> String? {
        var found: String?
        for (k, v) in http.allHeaderFields {
            let line = "\(k): \(v)"
            guard line.lowercased().contains("set-cookie") || k.description.lowercased() == "set-cookie" else { continue }
            if let r = line.range(of: "SessionID=") {
                let sid = line[r.upperBound...].prefix { $0 != ";" && $0 != " " }
                if !sid.isEmpty { found = String(sid) }
            }
        }
        return found
    }

    func refreshToken() async -> String {
        guard let s = await getText("/api/webserver/token") else { return "" }
        guard let full = CPEXML(raw: s, isError: false).str("token") else { return "" }
        let t = full.count > 32 ? String(full.suffix(32)) : full
        token = t
        return t
    }

    func getText(_ path: String) async -> String? {
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var req = URLRequest(url: url)
        if !sessionID.isEmpty {
            req.setValue("SessionID=\(sessionID)", forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, _) = try await session.data(for: req)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func postText(_ path: String, body: String, withToken: Bool = true) async -> String? {
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                     forHTTPHeaderField: "Content-Type")
        if !sessionID.isEmpty {
            req.setValue("SessionID=\(sessionID)", forHTTPHeaderField: "Cookie")
        }
        if withToken {
            if token.isEmpty { _ = await refreshToken() }
            req.setValue(token, forHTTPHeaderField: "__RequestVerificationToken")
        }
        do {
            let (data, _) = try await session.data(for: req)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: Login

    struct LoginResult {
        var ok: Bool
        var code: String?
        var stage: String?
    }

    /// Full SCRAM login. `nonce` is 32 random bytes as hex (64 chars).
    func login(user: String, password: String) async -> LoginResult {
        // 1) state
        if let st = await getText("/api/user/state-login") {
            let x = CPEXML(raw: st, isError: false)
            if x.str("State") == "0" { return LoginResult(ok: true, code: nil, stage: "already") }
            if let lock = x.str("lockstatus"), lock != "0" {
                return LoginResult(ok: false, code: "108007",
                                   stage: "剩余 " + (x.str("remainwaittime") ?? "?") + " 分钟")
            }
        }
        // 2) token goes stale almost immediately on this firmware: fetch a
        //    fresh one and derive a NEW nonce for every attempt (replaying a
        //    nonce is rejected).
        var nonce = ""
        var cx = CPEXML(raw: "", isError: false)

        for attempt in 0..<3 {
            _ = await refreshToken()
            nonce = Self.randomHex(32)
            if attempt > 0 {
                // Back off a little; do NOT re-fetch the page — that would
                // rotate the session cookie away from the token.
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            let body = "<request><username>\(user)</username>"
                + "<firstnonce>\(nonce)</firstnonce><mode>1</mode></request>"
            guard let resp = await postText("/api/user/challenge_login", body: body) else {
                return LoginResult(ok: false, code: nil, stage: "network")
            }
            cx = CPEXML(raw: resp, isError: false)
            if cx.str("salt") != nil { break }
            if cx.str("code") != "125003" { break }
        }
        // NOTE: servernonce must be used verbatim — its base64 `+`/`/` arrive
        // XML-escaped (&#x2B; / &#x2F;) and the firmware hashes the RAW text.
        guard let salt = cx.str("salt"),
              let iterStr = cx.str("iterations"),
              let srv = cx.rawStr("servernonce") else {
            return LoginResult(ok: false, code: cx.str("code"), stage: "challenge")
        }
        let iters = Int(iterStr) ?? 1000

        // 3) proof
        let authMsg = "\(nonce),\(srv),\(srv)"
        guard let proof = HWScram.proof(password: password, saltHex: salt,
                                        iterations: iters, authMessage: authMsg) else {
            return LoginResult(ok: false, code: nil, stage: "scram")
        }
        _ = await refreshToken()
        let authBody = "<request><clientproof>\(proof)</clientproof>"
            + "<finalnonce>\(srv)</finalnonce></request>"
        let auth = await postText("/api/user/authentication_login", body: authBody) ?? ""

        // 4) verify
        let st2 = await getText("/api/user/state-login") ?? ""
        let ok = CPEXML(raw: st2, isError: false).str("State") == "0"
        return LoginResult(ok: ok,
                           code: ok ? nil : CPEXML(raw: auth, isError: false).str("code"),
                           stage: "auth")
    }

    static func randomHex(_ bytes: Int) -> String {
        var d = Data(count: bytes)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return d.hexString
    }
}
