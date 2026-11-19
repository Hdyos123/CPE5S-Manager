import Foundation

// 轻量数据模型（客户端用字典解析后映射到这里，字段名宽松）
struct SimInfo {
    var iccid: String?
    var imsi: String?
    var plmn: String?
    var iccidMasked: String {
        guard let s = iccid, s.count > 8 else { return iccid ?? "—" }
        return String(s.prefix(6)) + "****" + String(s.suffix(4))
    }
}

struct SysInfo {
    var netMode: String?
    var plmn: String?
}

struct SmsSession: Identifiable {
    var id = UUID()
    var index: Int          // 会话索引 / SmsSn
    var number: String?     // SrcAddr
    var snippet: String?    // lastData
    var time: String?       // SmsTime / Time
    var unread: Int         // MessageRead == false -> 1
    var isMe: Bool = false

    var display: String { (number?.isEmpty == false) ? number! : "未知号码" }
}

struct SmsMessage: Identifiable {
    var id = UUID()
    var sn: Int = 0         // SmsSn
    var content: String?    // TextContent / Message
    var time: String?       // SmsTime
    var isMe: Bool = false  // true = 我发出的

    var isIncoming: Bool { !isMe }
}

enum Fmt {
    static func bytes(_ v: Int64) -> String {
        let d = Double(v)
        if d >= 1_073_741_824 { return String(format: "%.2f GB", d / 1_073_741_824) }
        if d >= 1_048_576 { return String(format: "%.1f MB", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0f KB", d / 1024) }
        return "\(v) B"
    }

    static func rate(_ v: Int64) -> String {
        let d = Double(v)
        if d >= 1_000_000_000 { return String(format: "%.2f Gbps", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1f Mbps", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0f Kbps", d / 1_000) }
        return "\(v) bps"
    }

    static func dbm(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.0f dBm", v)
    }

    static func dB(_ v: Double?, unit: String) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.0f %@", v, unit)
    }

    /// 信号格 0~4
    static func bars(rsrp: Double?) -> Int {
        guard let r = rsrp else { return 0 }
        switch r {
        case ..<(-110): return 1
        case -110 ..< -95: return 2
        case -95 ..< -80: return 3
        default: return 4
        }
    }

    static func operatorName(_ plmn: String?) -> String {
        switch plmn {
        case "46000", "46002", "46004", "46007", "46008": return "中国移动"
        case "46001", "46006", "46009": return "中国联通"
        case "46003", "46005", "46011": return "中国电信"
        case "46015": return "中国广电"
        default: return plmn ?? "—"
        }
    }
}
