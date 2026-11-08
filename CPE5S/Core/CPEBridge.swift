//
//  CPEBridge.swift
//  CPE5S
//
//  Invisible WKWebView that logs into the Huawei 5G CPE 5s web UI and keeps
//  the session alive, then relays API calls from native Swift.
//

import Foundation
import UIKit
import WebKit
import SwiftUI

// MARK: - API result

struct CPEXML {
    let raw: String
    let isError: Bool

    /// Extract <tag>value</tag> from the response body.
    func str(_ key: String) -> String? {
        guard let range = raw.range(of: "<\(key)>") else { return nil }
        let rest = raw[range.upperBound...]
        guard let end = rest.range(of: "</\(key)>") else { return nil }
        let v = String(rest[..<end.lowerBound])
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#x2B;", with: "+")
            .replacingOccurrences(of: "&#x3D;", with: "=")
            .replacingOccurrences(of: "&#40;", with: "(")
            .replacingOccurrences(of: "&#41;", with: ")")
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func int(_ key: String) -> Int? { str(key).flatMap { Int($0) } }
    func double(_ key: String) -> Double? { str(key).flatMap { Double($0) } }
    func exists(_ key: String) -> Bool { raw.contains("<\(key)>") }

    /// Parse repeated <Host> blocks.
    var hostBlocks: [[String: String]] {
        var out: [[String: String]] = []
        var cursor = raw.startIndex
        while let s = raw.range(of: "<Host>", range: cursor..<raw.endIndex),
              let e = raw.range(of: "</Host>", range: s.upperBound..<raw.endIndex) {
            let block = CPEXML(raw: String(raw[s.upperBound..<e.lowerBound]), isError: false)
            let keys = ["HostName", "ActualName", "IpAddress", "MacAddress",
                        "InterfaceType", "Active", "AssociatedTime", "AssociatedSsid"]
            var d: [String: String] = [:]
            for k in keys { d[k] = block.str(k) ?? "" }
            out.append(d)
            cursor = e.upperBound
        }
        return out
    }

    /// Parse repeated <Sms> blocks (or Cell 5G neighbours).
    func blocks(_ tag: String) -> [[String: String]] {
        var out: [[String: String]] = []
        var cursor = raw.startIndex
        while let s = raw.range(of: "<\(tag)>", range: cursor..<raw.endIndex),
              let e = raw.range(of: "</\(tag)>", range: s.upperBound..<raw.endIndex) {
            out.append(["_raw": String(raw[s.upperBound..<e.lowerBound])])
            cursor = e.upperBound
        }
        return out
    }
}

// MARK: - Bridge

@MainActor
final class CPEBridge: NSObject, ObservableObject {

    static let shared = CPEBridge()

    // Config — persisted so the login screen can pre-fill next time.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static let defaultHost = "192.168.8.1"
    static let defaultUser = "admin"

    var host: String {
        get { UserDefaults.standard.string(forKey: "cpe.host") ?? Self.defaultHost }
        set { UserDefaults.standard.set(newValue, forKey: "cpe.host") }
    }
    var user: String {
        get { UserDefaults.standard.string(forKey: "cpe.user") ?? Self.defaultUser }
        set { UserDefaults.standard.set(newValue, forKey: "cpe.user") }
    }
    var baseURL: String { "http://\(host)" }
    /// Persisted password (only when "记住密码" is on).
    @AppStorage("cpe.password") var password: String = ""
    /// In-memory password used for session re-auth; survives even when the
    /// user opted out of remembering it.
    var sessionSecret: String = ""
    /// Gateway session cookie, mirrored from the web view's cookie store.
    var sessionID: String = ""
    /// Native HTTP client (used once logged in).
    var native: CPENative?

    @Published var sessionReady = false
    @Published var lastError: String?
    @Published var isLoggingIn = false

    // MARK: Login state (drives the login gate)

    @Published var isLoggedIn = false

    /// Whether a password is stored and auto-login is enabled.
    var autoLoginEnabled: Bool {
        UserDefaults.standard.object(forKey: "cpe.autoLogin") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "cpe.autoLogin")
    }

    var rememberPassword: Bool {
        UserDefaults.standard.object(forKey: "cpe.remember") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "cpe.remember")
    }

    /// Load the gateway page and establish a session without logging in.
    /// Safe to call repeatedly; used to warm the hidden web view.
    func prepare() async {
        if sessionReady { return }
        if !(await hasSessionCookie()) {
            await loadLoginPage()
        } else {
            await waitForForge()
        }
    }

    /// Sign in with explicit credentials from the login screen.
    @discardableResult
    func signIn(host: String, user: String, password: String,
                remember: Bool, autoLogin: Bool) async -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedUser = user.trimmingCharacters(in: .whitespaces)
        self.host = trimmedHost.isEmpty ? Self.defaultHost : trimmedHost
        self.user = trimmedUser.isEmpty ? Self.defaultUser : trimmedUser

        // Keep the password in memory for this attempt regardless of `remember`;
        // only decide about persistence after the login succeeds.
        self.sessionSecret = password
        if remember { self.password = password }
        UserDefaults.standard.set(remember, forKey: "cpe.remember")
        UserDefaults.standard.set(autoLogin, forKey: "cpe.autoLogin")

        sessionReady = false
        lastError = nil
        await boot(force: true)

        if sessionReady && !remember {
            // Keep sessionSecret in memory so auto re-auth still works this run.
            UserDefaults.standard.removeObject(forKey: "cpe.password")
            self.password = ""
        }
        isLoggedIn = sessionReady
        return sessionReady
    }

    func signOut() {
        isLoggedIn = false
        sessionReady = false
        lastError = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    // MARK: User-Agent

    /// Desktop UA — the full PC web UI (all menus / fields) is served to this.
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    /// Mobile UA — the small handset layout.
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .components(separatedBy: " ").first ?? "17.0"
    }

    /// Current UA mode (persisted).
    var isDesktopUA: Bool {
        UserDefaults.standard.object(forKey: "cpe.desktopUA") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "cpe.desktopUA")
    }

    /// Swap the UA and reload; the session cookie survives.
    func setUserAgent(desktop: Bool) async {
        webView.customUserAgent = desktop ? Self.desktopUA : Self.mobileUA
        UserDefaults.standard.set(desktop, forKey: "cpe.desktopUA")
        objectWillChange.send()
        await boot(force: true)
    }

    /// Ask the page what it sees — handy for debugging which layout is served.
    func debugUserAgent() async -> String {
        (try? await evalString("navigator.userAgent")) ?? "-"
    }

    private var webView: WKWebView!
    private var bootContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        // Safari-like UA so the firmware's Vue app renders the same code paths
        // it serves to a real browser (a bare WKWebView UA gets a reduced page).
        cfg.applicationNameForUserAgent = "Version/\(CPEBridge.osVersion) Mobile/15E148 Safari/604.1"
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        wv.isHidden = true
        wv.customUserAgent = UserDefaults.standard.object(forKey: "cpe.desktopUA") == nil
            ? CPEBridge.desktopUA
            : (UserDefaults.standard.bool(forKey: "cpe.desktopUA") ? CPEBridge.desktopUA : CPEBridge.mobileUA)
        wv.navigationDelegate = self
        webView = wv
    }

    /// A 0-size container so the WKWebView is attached to a window
    /// (a detached WKWebView will not run JS reliably).
    func attach(to window: UIWindow) {
        guard webView.superview == nil, let root = window.rootViewController?.view else { return }
        webView.frame = CGRect(x: -10, y: -10, width: 1, height: 1)
        webView.alpha = 0.01
        root.addSubview(webView)
    }

    // MARK: Boot + login

    func boot(force: Bool = false) async {
        if sessionReady && !force { return }
        guard !isLoggingIn else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        await loadLoginPage()

        // Already logged in?
        if let st = try? await call("/api/user/state-login"),
           st.str("State") == "0" {
            sessionReady = true
            lastError = nil
            return
        }
        if sessionSecret.isEmpty && password.isEmpty {
            lastError = "请先输入密码"
            return
        }
        await performLogin()
    }

    private func loadLoginPage() async {
        // Always do a fresh navigation. A reload() can reuse a WebView whose
        // session cookie was never (re)established, which makes every token
        // come back "expired" (125003) on challenge_login.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            bootContinuation = c
            let target = URL(string: baseURL + "/")!
            var req = URLRequest(url: target)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.timeoutInterval = 20
            webView.load(req)
            // safety timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.bootContinuation?.resume()
                self?.bootContinuation = nil
            }
        }
        // Make sure the page's own forge.js is available before we touch it.
        await waitForForge()
        // Confirm the gateway actually handed us a session cookie.
        await ensureSessionCookie()
    }

    /// The firmware issues `SessionID` on the first GET /. Without it every
    /// authenticated call answers 125003, so verify (and re-fetch if needed).
    @discardableResult
    private func ensureSessionCookie() async -> Bool {
        for _ in 0..<3 {
            let ok = await hasSessionCookie()
            if ok { return true }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                webView.load(URLRequest(url: URL(string: baseURL + "/")!))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.resume() }
            }
        }
        return await hasSessionCookie()
    }

    /// Read the gateway session cookie value (needed because ITP may drop it
    /// from JS fetch requests; we then attach it explicitly).
    private func sessionCookieValue() async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            webView.configuration.websiteDataStore.httpCookieStore
                .getAllCookies { cookies in
                    let v = cookies.first { $0.name == "SessionID" }?.value ?? ""
                    c.resume(returning: v)
                }
        }
    }

    private func hasSessionCookie() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            webView.configuration.websiteDataStore.httpCookieStore
                .getAllCookies { cookies in
                    c.resume(returning: cookies.contains { $0.name == "SessionID" && !$0.value.isEmpty })
                }
        }
    }

    /// Poll until `forge` exists in the page (the firmware's crypto bundle).
    private func waitForForge(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        let probe = "return typeof forge !== 'undefined' && typeof forge.pbkdf2 === 'function';"
        while Date() < deadline {
            if let v = try? await runAsync(probe), let ok = v as? Bool, ok {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func performLogin() async {
        let secret = sessionSecret.isEmpty ? password : sessionSecret
        guard !secret.isEmpty else {
            lastError = "请先输入密码"; return
        }
        // Make sure we have the session cookie the firmware issued on GET /.
        if sessionID.isEmpty {
            sessionID = await sessionCookieValue()
        }
        if sessionID.isEmpty {
            lastError = "无法建立网关会话（Cookie 未下发），请确认手机已连接该设备"
            return
        }
        let client = CPENative(host: host)
        client.sessionID = sessionID
        let r = await client.login(user: user, password: secret)
        sessionReady = r.ok
        if r.ok {
            lastError = nil
            sessionID = client.sessionID
            native = client
        } else {
            var msg = Self.loginMessage(r.code ?? r.stage ?? "?")
            if let st = r.stage, st != "auth", st != "already" { msg += " · \(st)" }
            lastError = msg
        }
    }

    static func loginMessage(_ code: String) -> String {
        switch code {
        case "108006": return "密码错误"
        case "108007": return "错误次数超限，已被锁定，请稍后再试"
        case "108003": return "该账号已在其他地方登录"
        case "125003": return "会话令牌失效（请重试，或确认未在其他设备登录）"
        case "challenge": return "握手失败（设备未响应，请确认地址）"
        case "noforge": return "页面未加载完成（加密库缺失），请重试"
        case "nosalt": return "设备未返回密钥参数"
        default: return "登录失败（\(code)）"
        }
    }

    // MARK: API

    func call(_ path: String) async throws -> CPEXML {
        if !sessionReady { await boot() }

        // Prefer the native client: no ITP sandbox, cookies are explicit.
        if let n = native, !n.sessionID.isEmpty {
            if let text = await n.getText(path) {
                if text.contains("125003") {
                    sessionReady = false
                    await boot(force: true)
                } else if !text.isEmpty {
                    return CPEXML(raw: text, isError: text.contains("<error>"))
                }
            }
        }

        // Fallback: in-page fetch with an explicitly attached cookie.
        let js = """
          try {
            const r = await fetch("\(path)", {credentials:"include",
              headers: sid ? {Cookie: "SessionID=" + sid} : {}});
            return await r.text();
          } catch (e) { return "__JSERR__" + e; }
        """
        var text = ""
        for _ in 0..<2 {
            text = (try? await runAsync("return await (async () => { \(js) })();",
                                        arguments: ["sid": sessionID])) as? String ?? ""
            if text.hasPrefix("__JSERR__") || text.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            if text.contains("125003") {
                sessionReady = false
                await boot(force: true)
                continue
            }
            break
        }
        guard !text.isEmpty else { throw CPEBridgeError.empty }
        return CPEXML(raw: text, isError: text.contains("<error>"))
    }

    /// Fire an action endpoint, e.g. reboot.
    @discardableResult
    func action(_ path: String, body: String = "<request></request>") async -> CPEXML? {
        if let n = native, !n.sessionID.isEmpty {
            if let text = await n.postText(path, body: body) {
                return CPEXML(raw: text, isError: text.contains("<error>"))
            }
        }
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
        let js = """
          try {
            const tok = await (await fetch("/api/webserver/token",{credentials:"include"})).text();
            const m = tok.match(/<token>(.*?)<\\/token>/s);
            let t = m ? m[1] : "";
            t = t.replace(/&#x2F;/g,"/").replace(/&#x2B;/g,"+").replace(/&#x3D;/g,"=");
            if (t.length > 32) t = t.substr(32);
            const r = await fetch("\(path)", {
              method: "POST", credentials: "include",
              headers: {"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8",
                        "__RequestVerificationToken": t},
              body: "\(escaped)"
            });
            return await r.text();
          } catch(e) { return "__JSERR__" + e; }
        """
        guard let text = try? await evalString(js), !text.isEmpty else { return nil }
        return CPEXML(raw: text, isError: text.contains("<error>"))
    }

    // MARK: JS helpers

    /// Run an async JS expression and bridge the resolved value back to Swift.
    /// `callAsyncJavaScript` understands `await` and unwraps the returned promise;
    /// `evaluateJavaScript` does not (it hands back an opaque Promise object).
    private func runAsync(_ body: String,
                          arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Any?, Error>) in
            webView.callAsyncJavaScript(body,
                                        arguments: arguments,
                                        in: nil,
                                        in: .page) { result in
                switch result {
                case .failure(let err):
                    c.resume(throwing: err)
                case .success(let value):
                    c.resume(returning: value)
                }
            }
        }
    }

    private func evalString(_ js: String) async throws -> String {
        let v = try await runAsync("return String(await (async () => { \(js) })());")
        if let s = v as? String { return s }
        if let s = v as? NSString { return s as String }
        return v.map { "\($0)" } ?? ""
    }

    private func evalDict(_ js: String) async throws -> [String: Any]? {
        let v = try await runAsync("return await (async () => { \(js) })();")
        if let d = v as? [String: Any] { return d }
        if let d = v as? NSDictionary { return d as? [String: Any] }
        return nil
    }

    // MARK: Login JS (mirrors the firmware's own forge.js exactly)

    /// Login body executed inside the page. Credentials arrive via `arguments`
    /// so no string interpolation happens (avoids quoting / scope issues).
    static let loginBody = """
    try {
      // forge.js ships with the web UI; wait briefly if not parsed yet.
      for (let i = 0; i < 40 && typeof forge === "undefined"; i++) {
        await new Promise(r => setTimeout(r, 100));
      }
      if (typeof forge === "undefined") return {ok:false, stage:"noforge"};

      // Cookie header injected from native. WebKit may hide HttpOnly cookies
      // from JS fetches, so we always send it explicitly.
      const CK = sid ? {Cookie: "SessionID=" + sid} : {};
      const H = (extra) => Object.assign({}, CK, extra || {});

      const r = (e,t,n) => forge.util.bytesToHex(forge.pbkdf2(e,t,n,32,"sha256"));
      const A = (e,t) => { const m = forge.hmac.create(); m.start("sha256", t); m.update(forge.util.hexToBytes(e)); return m.digest().toHex(); };
      const IK = e => A(e, "Client Key");
      const SH = e => { const m = forge.md.sha256.create(); m.update(forge.util.hexToBytes(e)); return m.digest().toHex(); };
      const MK = (e,t,n,o) => {
        const a = r(e,t,n), s = IK(a), u = SH(s), l = A(u,o);
        const p = forge.util.hexToBytes(s), f = forge.util.hexToBytes(l);
        return forge.util.bytesToHex(forge.util.xorBytes(p,f,p.length));
      };
      const tok = async () => {
        const x = await fetch("/api/webserver/token", {credentials:"include", headers: H()}).then(r => r.text());
        const m = x.match(new RegExp("<token>([\\s\\S]*?)<\\/token>"));
        let t = m ? m[1] : "";
        t = t.replace(/&#x2F;/g,"/").replace(/&#x2B;/g,"+").replace(/&#x3D;/g,"=");
        return t.length > 32 ? t.substr(32) : t;
      };
      const G = (x,k) => {
        const m = x.match(new RegExp("<" + k + ">([\\s\\S]*?)<\\/" + k + ">"));
        return m ? m[1] : null;
      };

      // 1) session check (no token needed)
      const st0 = await fetch("/api/user/state-login", {credentials:"include",
        headers: H()}).then(x => x.text());
      if (G(st0,"State") === "0") return {ok:true, already:true};
      if (G(st0,"lockstatus") && G(st0,"lockstatus") !== "0") {
        return {ok:false, stage:"locked", code:"108007", err:"剩余 " + G(st0,"remainwaittime") + " 分钟"};
      }

      // 2) grab a fresh token IMMEDIATELY before the handshake — the firmware
      //    invalidates it as soon as any other request intervenes.
      let t = await tok();
      const fn = forge.util.bytesToHex(forge.random.getBytesSync(32));
      let cr = await fetch("/api/user/challenge_login", {method:"POST", credentials:"include",
        headers: H({"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8",
                 "__RequestVerificationToken": t}),
        body: "<request><username>" + usr + "</username><firstnonce>" + fn +
              "</firstnonce><mode>1</mode></request>"}).then(x => x.text());

      // 3) token races are common on this firmware: refresh and retry once.
      if (cr.indexOf("125003") >= 0) {
        await new Promise(r => setTimeout(r, 400));
        t = await tok();
        cr = await fetch("/api/user/challenge_login", {method:"POST", credentials:"include",
          headers: H({"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8",
                   "__RequestVerificationToken": t}),
          body: "<request><username>" + usr + "</username><firstnonce>" + fn +
                "</firstnonce><mode>1</mode></request>"}).then(x => x.text());
      }

      const salt = G(cr,"salt"), iters = G(cr,"iterations"), srv = G(cr,"servernonce");
      if (!salt) return {ok:false, stage:"challenge", code:G(cr,"code"), err:cr.slice(0,120)};

      const am = fn + "," + srv + "," + srv;
      const proof = MK(pwd, forge.util.hexToBytes(salt), +iters, am);

      t = await tok();
      const ar = await fetch("/api/user/authentication_login", {method:"POST", credentials:"include",
        headers: H({"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8",
                 "__RequestVerificationToken": t}),
        body: "<request><clientproof>" + proof + "</clientproof><finalnonce>" + srv +
              "</finalnonce></request>"}).then(x => x.text());

      const st2 = await fetch("/api/user/state-login", {credentials:"include",
        headers: H()}).then(x => x.text());
      const ok = G(st2,"State") === "0";
      return {ok: ok, code: ok ? "" : (G(ar,"code") || "?"), level: G(st2,"userlevel")};
    } catch (e) {
      return {ok:false, stage:"exception", err: String(e)};
    }
    """
}

enum CPEBridgeError: Error { case empty }

extension CPEBridge: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.bootContinuation?.resume()
            self.bootContinuation = nil
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.bootContinuation?.resume()
            self.bootContinuation = nil
        }
    }
}
