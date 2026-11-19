import SwiftUI

struct ParamsView: View {
    @ObservedObject var cpe: CpeClient
    @State private var rows: [(String, String)] = []
    @State private var loading = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("设备参数", systemImage: "list.bullet.rectangle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Button {
                                loadAll()
                            } label: {
                                Image(systemName: loading ? "hourglass" : "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }

                        ForEach(rows.indices, id: \.self) { i in
                            HStack(alignment: .top) {
                                Text(rows[i].0)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .frame(width: 96, alignment: .leading)
                                Text(rows[i].1)
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            if i < rows.count - 1 {
                                Divider().overlay(Color.white.opacity(0.07))
                            }
                        }

                        if rows.isEmpty {
                            Text("点击右上角刷新加载")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onAppear { if rows.isEmpty { loadAll() } }
    }

    private func loadAll() {
        loading = true
        var acc: [(String, String)] = []
        let group = DispatchGroup()
        let lock = NSLock()

        func add(_ k: String, _ v: String?) {
            lock.lock()
            acc.append((k, v ?? "—"))
            lock.unlock()
        }

        group.enter()
        cpe.api("/SimService/GetInfo") { raw in
            if let i = CpeClient.inner(raw) {
                add("ICCID", i["ICCID"] as? String)
                add("IMSI", i["IMSI"] as? String)
                add("PLMN", i["PLMN"] as? String)
            }
            group.leave()
        }
        group.enter()
        cpe.api("/NasMng/GetSysInfo") { raw in
            if let i = CpeClient.inner(raw) {
                add("网络制式", i["NetMode"] as? String)
                add("漫游状态", ((i["RoamStatus"] as? NSNumber)?.intValue ?? 0) == 0 ? "未漫游" : "漫游中")
                add("服务状态", "\((i["SrvStatus"] as? NSNumber)?.intValue ?? 0)")
            }
            group.leave()
        }
        group.enter()
        cpe.api("/NasMng/GetCellInfo") { raw in
            if let i = CpeClient.inner(raw) {
                add("小区 ID", (i["CellId"] as? NSNumber).map { "\($0.int64Value)" })
                add("PCI", (i["PhyCellId"] as? NSNumber).map { "\($0.intValue)" })
            }
            group.leave()
        }
        group.enter()
        cpe.api("/ommng/GetDeviceInfo") { raw in
            if let i = CpeClient.inner(raw) {
                for (k, label) in [("DeviceName", "设备名称"), ("ModelName", "型号"), ("SoftwareVersion", "软件版本"),
                                   ("HardwareVersion", "硬件版本"), ("IMEI", "IMEI"), ("SerialNumber", "序列号"),
                                   ("MacAddress", "MAC"), ("UpTime", "运行时长")] {
                    if let v = i[k] as? String { add(label, v) }
                }
            }
            group.leave()
        }
        group.enter()
        cpe.api("/NetStats/GetStats", payload: ["Interface": "rmnet_data0"]) { raw in
            if let i = CpeClient.inner(raw), let arr = i["Stats"] as? [[String: Any]], let s = arr.first {
                add("累计下载", Fmt.bytes((s["BytesReceived"] as? NSNumber)?.int64Value ?? 0))
                add("累计上传", Fmt.bytes((s["BytesSent"] as? NSNumber)?.int64Value ?? 0))
            }
            group.leave()
        }

        group.notify(queue: .main) {
            rows = acc
            loading = false
        }
    }
}
