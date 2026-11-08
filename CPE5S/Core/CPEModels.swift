//
//  CPEModels.swift
//  CPE5S
//
//  Data models + the store that polls the gateway.
//

import Foundation
import SwiftUI

// MARK: - Models

struct SignalCell: Identifiable, Equatable {
    var id = UUID()
    var arfcn: String = ""
    var band: String = ""
    var bandwidth: String = ""
    var pci: String = ""
    var rsrp: String = ""
    var rsrq: String = ""
    var rssi: String = ""
    var sinr: String = ""
    var isServing = false

    /// Numeric SINR for colouring.
    var sinrValue: Double { Double(sinr.replacingOccurrences(of: "dB", with: "")) ?? -99 }
    var rsrpValue: Double { Double(rsrp.replacingOccurrences(of: "dBm", with: "")) ?? -999 }
}

struct NeighborCell: Identifiable, Equatable {
    var id = UUID()
    var arfcn: String, band: String, pci: String
    var rsrp: String, rsrq: String, rssi: String, sinr: String
    var sinrValue: Double { Double(sinr.replacingOccurrences(of: "dB", with: "")) ?? -99 }
    var rsrpValue: Double { Double(rsrp.replacingOccurrences(of: "dBm", with: "")) ?? -999 }
}

struct CPEHost: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var ip: String
    var mac: String
    var iface: String
    var active: Bool
    var associatedSec: Int
}

struct CPESms: Identifiable, Equatable {
    var id = UUID()
    var index: String
    var phone: String
    var content: String
    var date: String
    var unread: Bool
    var box: String      // inbox / outbox
}

struct CPETraffic: Equatable {
    var currentDownload: Int = 0
    var currentUpload: Int = 0
    var dlRate: Int = 0
    var ulRate: Int = 0
    var monthDown: Int = 0
    var monthUp: Int = 0
    var todayUsed: Int = 0
    var connectTime: Int = 0
    var totalDown: Int = 0
    var totalUp: Int = 0
}

struct CPEDeviceInfo: Equatable {
    var model = "-"
    var software = "-"
    var webUI = "-"
    var imei = "-"
    var imsi = "-"
    var msisdn = "-"
    var serial = "-"
    var hardware = "-"
    var mac = "-"
    var wanIP = "-"
    var wanIPv6 = "-"
    var cellID = "-"
    var plmn = "-"
    var band = "-"
    var mcsUL = "-"
    var mcsDL = "-"
    var rank = "-"
    var cqi = "-"
    var uptime = 0
    var operatorName = "-"
    var networkType = "-"
}

struct CPESignalState: Equatable {
    var serving: SignalCell?
    var neighbors: [NeighborCell] = []
    var nrrsrp: String = "-"
    var nrrsrq: String = "-"
    var nrsinr: String = "-"
    var nrrssi: String = "-"
    var band: String = "-"
    var pci: String = "-"
    var mode: String = "-"
    var bars: Int = 0
}

// MARK: - Store

@MainActor
final class CPEStore: ObservableObject {

    @Published var device = CPEDeviceInfo()
    @Published var signal = CPESignalState()
    @Published var traffic = CPETraffic()
    @Published var hosts: [CPEHost] = []
    @Published var sms: [CPESms] = []
    @Published var smsUnread = 0
    @Published var connected = false
    @Published var isLoggedIn = false
    @Published var lastUpdate = Date()
    @Published var busy = false

    // Live rate smoothing
    private var prevDl = 0
    private var prevUl = 0
    private var prevTime = Date()
    private var task: Task<Void, Never>?

    let bridge = CPEBridge.shared

    func start(interval: TimeInterval = 1.0) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLive()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    // MARK: Live (1s): rate + signal

    func refreshLive() async {
        await bridge.boot()
        if let t = try? await bridge.call("/api/monitoring/traffic-statistics") {
            let now = Date()
            let dl = t.int("CurrentDownload") ?? 0
            let ul = t.int("CurrentUpload") ?? 0
            traffic.currentDownload = dl
            traffic.currentUpload = ul
            traffic.totalDown = t.int("TotalDownload") ?? traffic.totalDown
            traffic.totalUp = t.int("TotalUpload") ?? traffic.totalUp
            traffic.connectTime = t.int("CurrentConnectTime") ?? traffic.connectTime

            // Prefer firmware's advertised rate, fall back to delta.
            let fwDl = t.int("CurrentDownloadRate") ?? 0
            let fwUl = t.int("CurrentUploadRate") ?? 0
            let dt = max(0.2, now.timeIntervalSince(prevTime))
            let dDl = Double(max(0, dl - prevDl)) / dt
            let dUl = Double(max(0, ul - prevUl)) / dt
            traffic.dlRate = fwDl > 0 ? fwDl : Int(dDl)
            traffic.ulRate = fwUl > 0 ? fwUl : Int(dUl)
            prevDl = dl; prevUl = ul; prevTime = now
            connected = true
        } else {
            connected = false
        }

        if let s = try? await bridge.call("/api/device/signal") {
            signal.nrrsrp = s.str("nrrsrp") ?? s.str("rsrp") ?? "-"
            signal.nrrsrq = s.str("nrrsrq") ?? s.str("rsrq") ?? "-"
            signal.nrsinr = s.str("nrsinr") ?? s.str("sinr") ?? "-"
            signal.nrrssi = s.str("nrrssi") ?? s.str("rssi") ?? "-"
            signal.band = s.str("band") ?? s.str("bandInfo") ?? "-"
            signal.pci = s.str("pci") ?? "-"
            signal.mode = s.str("mode") ?? "-"
            signal.bars = CPEStore.bars(rsrp: signal.nrrsrp, sinr: signal.nrsinr)
        }
        lastUpdate = Date()
    }

    static func bars(rsrp: String, sinr: String) -> Int {
        let r = Double(rsrp.replacingOccurrences(of: "dBm", with: "")) ?? -140
        let s = Double(sinr.replacingOccurrences(of: "dB", with: "")) ?? 0
        if r <= -115 || s < -3 { return 1 }
        if r <= -105 || s < 3 { return 2 }
        if r <= -95 || s < 8 { return 3 }
        if r <= -85 || s < 15 { return 4 }
        return 5
    }

    // MARK: Full refresh

    func refreshAll() async {
        busy = true
        defer { busy = false }
        await bridge.boot()

        // Device info
        if let d = try? await bridge.call("/api/device/information") {
            var x = CPEDeviceInfo()
            x.model = d.str("DeviceName") ?? "-"
            x.software = d.str("SoftwareVersion") ?? "-"
            x.webUI = d.str("WebUIVersion") ?? "-"
            x.imei = d.str("Imei") ?? "-"
            x.imsi = d.str("Imsi") ?? "-"
            x.msisdn = d.str("Msisdn") ?? "-"
            x.serial = d.str("SerialNumber") ?? "-"
            x.hardware = d.str("HardwareVersion") ?? "-"
            x.mac = d.str("MacAddress1") ?? "-"
            device = x
        }
        // Extended (PC-version fields)
        if let e = try? await bridge.call("/api/device/basic_information") {
            if let ip = e.str("WanIPAddress"), !ip.isEmpty { device.wanIP = ip }
            if let ip6 = e.str("WanIPv6Address"), !ip6.isEmpty { device.wanIPv6 = ip6 }
        }
        if let b = try? await bridge.call("/api/device/boot_time") {
            device.uptime = b.int("bootTime") ?? b.int("BootTime") ?? 0
        }
        if let p = try? await bridge.call("/api/net/current-plmn") {
            device.operatorName = p.str("FullName") ?? "-"
        }
        if let st = try? await bridge.call("/api/monitoring/status") {
            device.networkType = Self.networkType(st.int("CurrentNetworkType") ?? 0)
        }
        // Signal details
        if let s = try? await bridge.call("/api/device/signal") {
            device.cellID = s.str("cell_id") ?? "-"
            device.plmn = s.str("plmn") ?? "-"
            device.band = s.str("band") ?? "-"
            device.mcsUL = s.str("nrulmcs") ?? "-"
            device.mcsDL = s.str("nrdlmcs") ?? "-"
        }
        if let sc = try? await bridge.call("/api/device/status_info") {
            device.rank = sc.str("rank") ?? device.rank
            device.cqi = sc.str("cqi") ?? device.cqi
        }
        // Traffic (month/day)
        if let m = try? await bridge.call("/api/monitoring/month_statistics") {
            traffic.monthDown = m.int("CurrentMonthDownload") ?? 0
            traffic.monthUp = m.int("CurrentMonthUpload") ?? 0
            traffic.todayUsed = m.int("CurrentDayUsed") ?? 0
        }
        // Hosts
        if let h = try? await bridge.call("/api/lan/HostInfo") {
            hosts = h.hostBlocks.compactMap { d in
                guard let ip = d["IpAddress"], !ip.isEmpty else { return nil }
                let nm = (d["ActualName"].flatMap { $0.isEmpty ? nil : $0 })
                    ?? (d["HostName"].flatMap { $0.isEmpty ? nil : $0 })
                    ?? "未知设备"
                return CPEHost(name: nm,
                               ip: ip.components(separatedBy: ";").first ?? ip,
                               mac: d["MacAddress"] ?? "",
                               iface: d["InterfaceType"] == "Ethernet" ? "有线" : "Wi-Fi",
                               active: d["Active"] == "1",
                               associatedSec: Int(d["AssociatedTime"] ?? "0") ?? 0)
            }
        }
        // SMS count
        if let c = try? await bridge.call("/api/sms/sms-count") {
            smsUnread = c.int("LocalUnread") ?? 0
        }
        lastUpdate = Date()
    }

    static func networkType(_ code: Int) -> String {
        switch code {
        case 19, 20, 30: return "5G NR"
        case 9, 10, 11, 12: return "4G LTE"
        case 3, 4: return "3G"
        case 1, 2: return "2G"
        default: return "未知"
        }
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func bytes(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_099_511_627_776 { return String(format: "%.2f TB", d / 1_099_511_627_776) }
        if d >= 1_073_741_824 { return String(format: "%.2f GB", d / 1_073_741_824) }
        if d >= 1_048_576 { return String(format: "%.1f MB", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0f KB", d / 1024) }
        return "\(v) B"
    }

    static func rate(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_048_576 { return String(format: "%.2f", d / 1_048_576) + " MB/s" }
        if d >= 1024 { return String(format: "%.0f", d / 1024) + " KB/s" }
        return "\(v) B/s"
    }

    static func rateValue(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_048_576 { return String(format: "%.1f", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0f", d / 1024) }
        return "\(v)"
    }

    static func rateUnit(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_048_576 { return "MB/s" }
        if d >= 1024 { return "KB/s" }
        return "B/s"
    }

    static func duration(_ sec: Int) -> String {
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d)天 \(h)小时" }
        if h > 0 { return "\(h)小时 \(m)分" }
        return "\(m)分"
    }
}
