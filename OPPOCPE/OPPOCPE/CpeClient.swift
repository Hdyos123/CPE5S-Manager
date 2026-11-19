import Foundation
import WebKit
import Combine

@MainActor
final class CpeClient: NSObject, ObservableObject {
    // 连接状态
    @Published var connected = false
    @Published var connecting = false
    @Published var lastError: String?

    // 首页
    @Published var signal5G: Band?
    @Published var signal4G: Band?
    @Published var netMode = "—"
    @Published var cellId: Int64 = 0
    @Published var pci: Int = 0
    @Published var plmn = "—"
    @Published var sim: SimInfo?
    @Published var downRate: Int64 = 0
    @Published var upRate: Int64 = 0
    @Published var downBytes: Int64 = 0
    @Published var upBytes: Int64 = 0
    @Published var terminals: [Term] = []
    /// 速率历史（1 秒 1 点，最多 60 点）
    @Published var downHistory: [Int64] = []
    @Published var upHistory: [Int64] = []
    @Published var wifiEnable = 0

    // 参数
    @Published var sysInfo: SysInfo?

    // 短信
    @Published var smsSessions: [SmsSession] = []
    @Published var smsMessages: [SmsMessage] = []

    struct Band {
        var rsrp: Double?
        var rsrq: Double?
        var sinr: Double?
    }
    struct Term: Identifiable {
        var id: String { (mac ?? "") + (ip ?? "") }
        var name: String?
        var ip: String?
        var mac: String?
        var ifname: String?
    }

    @AppStorage("cpe.host") var host = "192.168.0.1"
    @AppStorage("cpe.user") var user = "admin"
    @AppStorage("cpe.pwd") var pwd = ""
    @AppStorage("cpe.auto") var autoLogin = true

    private var webView: WKWebView?
    private var pollTimer: Timer?
    private var bridgeReady = false
    private var bridgeWaiters: [() -> Void] = []

    var isReady: Bool { webView != nil && bridgeReady }

    // MARK: - 启动 / 登录
    func connect(completion: @escaping (Bool, String) -> Void) {
        if webView != nil {
            login(completion: completion)
            return
        }
        connecting = true
        lastError = nil

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: CpeBridge.js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController = ucc

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        wv.isHidden = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        wv.navigationDelegate = self
        ucc.add(self, name: "cpeBridge")
        webView = wv

        guard let url = URL(string: "http://\(host)/") else {
            connecting = false
            completion(false, "地址无效")
            return
        }
        wv.load(URLRequest(url: url, timeoutInterval: 12))
        // 登录在 didFinish 后进行
        pendingCompletion = completion
    }

    private var pendingCompletion: ((Bool, String) -> Void)?

    func login(user u: String, pwd p: String, completion: @escaping (Bool, String) -> Void) {
        guard let wv = webView else {
            connect { ok, msg in
                if ok { completion(true, msg) } else { completion(false, msg) }
            }
            return
        }
        withBridge(wv) {
            let escU = u.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escP = p.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let js = "window.__cpe.init().then(function(){return window.__cpe.login(\"\(escU)\",\"\(escP)\")}).catch(function(e){return 'ERR:'+e.message})"
            wv.evaluateJavaScript(js) { res, err in
                Task { @MainActor in
                    self.connecting = false
                    if let e = err { completion(false, e.localizedDescription); return }
                    let txt = (res as? String) ?? ""
                    if txt.hasPrefix("ERR") { completion(false, String(txt.dropFirst(4))); return }
                    if let ok = self.parseLogin(txt) {
                        completion(ok.0, ok.1)
                    } else {
                        completion(false, "响应异常")
                    }
                }
            }
        }
    }

    private func parseLogin(_ txt: String) -> (Bool, String)? {
        guard let d = txt.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let inner = (o["data"] as? [String: Any]) ?? o
        if (inner["isCheckedPass"] as? Bool) == true {
            connected = true
            lastError = nil
            startPolling()
            return (true, "登录成功")
        }
        let code = inner["ErrorCode"] as? Int ?? -1
        let left = inner["LeftCount"] as? Int
        if code == 2 {
            return (false, "密码错误" + (left.map { "，剩余 \($0) 次" } ?? ""))
        }
        return (false, "登录失败（错误码 \(code)）")
    }

    private func withBridge(_ wv: WKWebView, _ action: @escaping () -> Void) {
        if bridgeReady { action(); return }
        bridgeWaiters.append(action)
        // 兜底：bridge 可能已经注入但回调没到
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, !self.bridgeReady else { return }
            wv.evaluateJavaScript("!!(window.__cpe && window.__cpe.api)") { v, _ in
                Task { @MainActor in
                    if (v as? Bool) == true { self.flushWaiters() }
                }
            }
        }
    }

    private func flushWaiters() {
        guard !bridgeReady else { return }
        bridgeReady = true
        let ws = bridgeWaiters
        bridgeWaiters = []
        guard let wv = webView else { return }
        var q = DispatchQueue.main
        for w in ws { q.async { w() } }
    }

    func disconnect() {
        stopPolling()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.removeFromSuperview()
        webView = nil
        bridgeReady = false
        bridgeWaiters.removeAll()
        connected = false
    }

    // MARK: - 请求封装
    /// 网关对畸形加密体极敏感（会导致后端 CGI 卡死），因此：
    /// 1) 所有请求串行排队，绝并发；
    /// 2) 每个请求前确保 bridge 已初始化（key/iv/pem 齐全）；
    /// 3) 失败即停，不重试。
    private var queue: [(String, [String: Any], ((String?) -> Void)?)] = []
    private var busy = false

    func api(_ path: String, payload: [String: Any] = [:], done: ((String?) -> Void)? = nil) {
        queue.append((path, payload, done))
        if queue.count > 12 { queue.removeFirst(queue.count - 12) }  // 防止积压
        drain()
    }

    private func drain() {
        guard !busy, !queue.isEmpty else { return }
        guard let wv = webView, bridgeReady else { return }
        busy = true
        let (path, payload, done) = queue.removeFirst()
        let js = "window.__cpe.api('\(path)', \(Self.json(payload)))"
        wv.evaluateJavaScript(js) { res, err in
            Task { @MainActor in
                if let e = err {
                    self.lastError = e.localizedDescription
                    done?(nil)
                } else {
                    done?(res as? String)
                }
                self.busy = false
                // 轻微间隔，避免网关处理不过来
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.drain() }
            }
        }
    }

    /// 明文接口（/webCgi/*），同样排队
    func plain(_ path: String, payload: [String: Any] = [:], done: ((String?) -> Void)? = nil) {
        guard let wv = webView, bridgeReady else { done?(nil); return }
        let js = "window.__cpe.plain('\(path)', \(Self.json(payload)))"
        wv.evaluateJavaScript(js) { res, err in
            Task { @MainActor in
                if let e = err { self.lastError = e.localizedDescription; done?(nil); return }
                done?(res as? String)
            }
        }
    }

    static func json(_ o: [String: Any]) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    /// 从 {"code":0,"data":{...}} 或裸 {...} 中取内层字典
    static func inner(_ raw: String?) -> [String: Any]? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let inner = o["data"] as? [String: Any] { return inner }
        return o
    }

    // MARK: - 轮询
    private var tick = 0

    func startPolling() {
        pollTimer?.invalidate()
        tick = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollOnce() }
        }
        Task { @MainActor in
            await self.pollOnce()
            self.refreshMetaLight()
        }
    }

    /// 每次轮询只发 1~2 个请求，状态类请求 10 秒才发一次
    private func pollOnce() async {
        tick += 1
        await refreshHome()
        if tick % 5 == 0 { refreshMetaLight() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshHome() async {
        guard connected, bridgeReady else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            api("/NasMng/GetSignal") { raw in
                Task { @MainActor in
                    if let i = Self.inner(raw) {
                        if let g5 = i["5G"] as? [String: Any] {
                            self.signal5G = Band(rsrp: g5["Rsrp"] as? Double, rsrq: g5["Rsrq"] as? Double, sinr: g5["Sinr"] as? Double)
                        }
                        if let g4 = i["4G"] as? [String: Any] {
                            self.signal4G = Band(rsrp: g4["Rsrp"] as? Double, rsrq: g4["Rsrq"] as? Double, sinr: g4["Sinr"] as? Double)
                        }
                        if let m = i["NetMode"] as? String { self.netMode = m }
                    }
                    c.resume()
                }
            }
        }
        api("/NetStats/GetStats", payload: ["Interface": "rmnet_data0"]) { raw in
            Task { @MainActor in
                if let i = Self.inner(raw), let arr = i["Stats"] as? [[String: Any]], let s = arr.first {
                    self.downRate = (s["RateReceived"] as? NSNumber)?.int64Value ?? 0
                    self.upRate = (s["RateSent"] as? NSNumber)?.int64Value ?? 0
                    self.downBytes = (s["BytesReceived"] as? NSNumber)?.int64Value ?? 0
                    self.upBytes = (s["BytesSent"] as? NSNumber)?.int64Value ?? 0
                    self.downHistory.append(self.downRate)
                    self.upHistory.append(self.upRate)
                    if self.downHistory.count > 60 { self.downHistory.removeFirst() }
                    if self.upHistory.count > 60 { self.upHistory.removeFirst() }
                }
            }
        }
    }

    /// 只刷新首页需要的元信息（信号/小区/运营商），不碰列表类接口
    func refreshMetaLight() {
        guard connected else { return }
        api("/NasMng/GetCellInfo") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) {
                    self.cellId = (i["CellId"] as? NSNumber)?.int64Value ?? 0
                    self.pci = (i["PhyCellId"] as? NSNumber)?.intValue ?? 0
                }
            }
        }
        api("/NasMng/GetSysInfo") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) {
                    if let p = i["Plmn"] as? String { self.plmn = p }
                    self.sysInfo = SysInfo(netMode: i["NetMode"] as? String, plmn: i["Plmn"] as? String)
                }
            }
        }
    }

    func refreshMeta() async {
        guard connected else { return }
        api("/NasMng/GetCellInfo") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) {
                    self.cellId = (i["CellId"] as? NSNumber)?.int64Value ?? 0
                    self.pci = (i["PhyCellId"] as? NSNumber)?.intValue ?? 0
                }
            }
        }
        api("/NasMng/GetSysInfo") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) {
                    if let p = i["Plmn"] as? String { self.plmn = p }
                    self.sysInfo = SysInfo(netMode: i["NetMode"] as? String, plmn: i["Plmn"] as? String)
                }
            }
        }
        api("/SimService/GetInfo") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) {
                    self.sim = SimInfo(iccid: i["ICCID"] as? String, imsi: i["IMSI"] as? String, plmn: i["PLMN"] as? String)
                }
            }
        }
        api("/Wifi/GetEnable") { raw in
            Task { @MainActor in
                if let i = Self.inner(raw) { self.wifiEnable = (i["Enable"] as? NSNumber)?.intValue ?? 0 }
            }
        }
        loadTerminals()
    }

    func loadTerminals() {
        api("/TerminalMgr/GetOnlineTerminal") { raw in
            Task { @MainActor in
                guard let i = Self.inner(raw), let arr = i["OnlineTerminal"] as? [[String: Any]] else { return }
                self.terminals = arr.map {
                    Term(name: $0["Name"] as? String, ip: $0["IpAddr"] as? String,
                         mac: $0["Mac"] as? String, ifname: $0["IfName"] as? String)
                }
            }
        }
    }

    func refreshStats() async {
        guard connected else { return }
        await refreshHome()
    }

    // MARK: - 短信
    func loadSms() {
        api("/Sms/GetSmsSession") { raw in
            Task { @MainActor in
                guard let i = Self.inner(raw) else { return }
                let arr = (i["SmsSession"] ?? i["Sessions"] ?? i["List"] ?? i["data"]) as? [[String: Any]] ?? []
                self.smsSessions = arr.enumerated().map { (idx, d) in
                    let read = (d["MessageRead"] as? Bool) ?? ((d["MessageRead"] as? NSNumber)?.intValue ?? 1) != 0
                    return SmsSession(
                        index: (d["SmsSn"] as? NSNumber)?.intValue ?? (d["Index"] as? NSNumber)?.intValue ?? idx,
                        number: d["SrcAddr"] as? String ?? d["Number"] as? String,
                        snippet: d["lastData"] as? String ?? d["Snippet"] as? String,
                        time: d["SmsTime"] as? String ?? d["Time"] as? String,
                        unread: read ? 0 : 1,
                        isMe: (d["isMe"] as? Bool) ?? false)
                }
            }
        }
    }

    func loadSmsDetail(index: Int) {
        api("/Sms/GetSessionContext", payload: ["SmsSn": index, "Index": index]) { raw in
            Task { @MainActor in
                guard let i = Self.inner(raw) else { return }
                let arr = (i["Sms"] ?? i["Messages"] ?? i["List"] ?? i["data"]) as? [[String: Any]] ?? []
                self.smsMessages = arr.map { d in
                    SmsMessage(
                        sn: (d["SmsSn"] as? NSNumber)?.intValue ?? 0,
                        content: d["TextContent"] as? String ?? d["Message"] as? String ?? d["Content"] as? String,
                        time: d["SmsTime"] as? String ?? d["Time"] as? String,
                        isMe: (d["isMe"] as? Bool) ?? false)
                }
            }
        }
    }

    func sendSms(number: String, content: String, done: @escaping (Bool) -> Void) {
        api("/Sms/SendSms", payload: ["SrcAddr": number, "Number": number, "TextContent": content, "Content": content]) { raw in
            Task { @MainActor in
                let ok = Self.inner(raw).map { (($0["ErrorCode"] as? NSNumber)?.intValue ?? -1) == 0 } ?? false
                done(ok)
            }
        }
    }

    // MARK: - 控制
    func reboot(done: @escaping (Bool) -> Void) {
        api("/ommng/Reboot") { raw in
            Task { @MainActor in done(raw != nil) }
        }
    }

    func factoryReset(done: @escaping (Bool) -> Void) {
        api("/ommng/Reset") { raw in
            Task { @MainActor in done(raw != nil) }
        }
    }

    func setWifi(_ on: Bool) {
        api("/Wifi/SetEnable", payload: ["Enable": on ? 1 : 0]) { _ in
            Task { @MainActor in self.wifiEnable = on ? 1 : 0 }
        }
    }
}

extension CpeClient: WKScriptMessageHandler {
    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], (d["type"] as? String) == "ready" else { return }
        Task { @MainActor in
            self.flushWaiters()
            if let p = self.pendingCompletion {
                self.pendingCompletion = nil
                self.connecting = true
                self.login(user: self.user, pwd: self.pwd, completion: p)
            }
        }
    }
}

extension CpeClient: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let wv = webView
            wv.evaluateJavaScript("!!(window.__cpe)") { v, _ in
                let ok = (v as? Bool) == true
                Task { @MainActor in
                    if ok { self.flushWaiters() }
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.connecting = false
            self.lastError = "无法连接 \(self.host)"
            if let p = self.pendingCompletion {
                self.pendingCompletion = nil
                p(false, "无法连接 \(self.host)")
            }
        }
    }
}
