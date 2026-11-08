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

    // Config
    let host = "192.168.8.1"
    var baseURL: String { "http://\(host)" }
    @AppStorage("cpe.password") var password: String = ""

    @Published var sessionReady = false
    @Published var lastError: String?
    @Published var isLoggingIn = false

    private var webView: WKWebView!
    private var bootContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        wv.isHidden = true
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
        await performLogin()
    }

    private func loadLoginPage() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            bootContinuation = c
            webView.load(URLRequest(url: URL(string: baseURL + "/")!))
            // safety timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                self?.bootContinuation?.resume()
                self?.bootContinuation = nil
            }
        }
    }

    private func performLogin() async {
        guard !password.isEmpty else {
            lastError = "未设置登录密码"; return
        }
        let js = Self.loginJS(password: password, user: "admin")
        guard let res = try? await evalDict(js) else {
            lastError = "登录脚本执行失败"; return
        }
        let ok = (res["ok"] as? Bool) ?? false
        sessionReady = ok
        if !ok {
            let code = (res["code"] as? String) ?? (res["stage"] as? String) ?? "?"
            lastError = Self.loginMessage(code)
        } else {
            lastError = nil
        }
    }

    static func loginMessage(_ code: String) -> String {
        switch code {
        case "108006": return "密码错误"
        case "108007": return "错误次数超限，已被锁定，请稍后再试"
        case "108003": return "该账号已在其他地方登录"
        case "125003": return "会话失效，请重试"
        case "challenge": return "握手失败（设备未响应）"
        default: return "登录失败（\(code)）"
        }
    }

    // MARK: API

    func call(_ path: String) async throws -> CPEXML {
        if !sessionReady { await boot() }
        let js = """
        (async () => {
          try {
            const r = await fetch("\(path)", {credentials:"include"});
            return await r.text();
          } catch (e) { return "__JSERR__" + e; }
        })()
        """
        var text = ""
        for _ in 0..<2 {
            text = (try? await evalString(js)) ?? ""
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
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
        let js = """
        (async () => {
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
        })()
        """
        guard let text = try? await evalString(js), !text.isEmpty else { return nil }
        return CPEXML(raw: text, isError: text.contains("<error>"))
    }

    // MARK: JS helpers

    private func evalString(_ js: String) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(js) { result, err in
                if let err = err { c.resume(throwing: err); return }
                if let s = result as? String { c.resume(returning: s); return }
                c.resume(returning: result.map { "\($0)" } ?? "")
            }
        }
    }

    private func evalDict(_ js: String) async throws -> [String: Any]? {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any]?, Error>) in
            webView.evaluateJavaScript("(async () => { return await (async () => { \(js) })(); })()") { result, err in
                if let err = err { c.resume(throwing: err); return }
                c.resume(returning: result as? [String: Any])
            }
        }
    }

    // MARK: Login JS (mirrors the firmware's own forge.js exactly)

    static func loginJS(password: String, user: String) -> String {
        let pw = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        const pwd = "\(pw)";
        const r=(e,t,n)=>forge.util.bytesToHex(forge.pbkdf2(e,t,n,32,"sha256"));
        const A=(e,t)=>{var n=forge.hmac.create();n.start("sha256",t);n.update(forge.util.hexToBytes(e));return n.digest().toHex();};
        const IK=e=>A(e,"Client Key");
        const C=e=>{var t=forge.md.sha256.create();t.update(forge.util.hexToBytes(e));return t.digest().toHex();};
        const U=(e,t,n,o)=>{var a=r(e,t,n),s=IK(a),uu=C(s),l=A(uu,o),p=forge.util.hexToBytes(s),f=forge.util.hexToBytes(l);return forge.util.bytesToHex(forge.util.xorBytes(p,f,p.length));};
        const tok=async()=>{const x=await fetch("/api/webserver/token",{credentials:"include"}).then(r=>r.text());
          const m=x.match(/<token>(.*?)<\\/token>/s); let t=m?m[1]:"";
          t=t.replace(/&#x2F;/g,"/").replace(/&#x2B;/g,"+").replace(/&#x3D;/g,"=");
          return t.length>32?t.substr(32):t;};
        const G=(x,k)=>{const m=x.match(new RegExp("<"+k+">(.*?)</"+k+">","s"));return m?m[1]:null;};

        if (typeof forge === "undefined") return {ok:false, stage:"noforge"};
        let t = await tok();
        const st0 = await fetch("/api/user/state-login",{credentials:"include",headers:{"__RequestVerificationToken":t}}).then(x=>x.text());
        if (G(st0,"State") === "0") return {ok:true, already:true};

        const fn = forge.util.bytesToHex(forge.random.getBytesSync(32));
        let cr = await fetch("/api/user/challenge_login",{method:"POST",credentials:"include",
          headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8","__RequestVerificationToken":t},
          body:"<request><username>\(user)</username><firstnonce>"+fn+"</firstnonce><mode>1</mode></request>"}).then(x=>x.text());
        const salt=G(cr,"salt"), iters=G(cr,"iterations"), srv=G(cr,"servernonce");
        if (!salt) return {ok:false, stage:"challenge", code:G(cr,"code"), raw:cr.slice(0,160)};

        const am = fn+","+srv+","+srv;
        const proof = U(pwd, forge.util.hexToBytes(salt), +iters, am);
        t = await tok();
        const ar = await fetch("/api/user/authentication_login",{method:"POST",credentials:"include",
          headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8","__RequestVerificationToken":t},
          body:"<request><clientproof>"+proof+"</clientproof><finalnonce>"+srv+"</finalnonce></request>"}).then(x=>x.text());
        const st2 = await fetch("/api/user/state-login",{credentials:"include"}).then(x=>x.text());
        const ok = G(st2,"State") === "0";
        return {ok: ok, code: ok ? "" : (G(ar,"code") || "?"), level: G(st2,"userlevel")};
        """
    }
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
