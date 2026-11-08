//
//  LockBandView.swift
//  CPE5S
//
//  Band / cell locking with live neighbour scan.
//

import SwiftUI

struct LockBandView: View {
    @EnvironmentObject var store: CPEStore

    @State private var neighbors: [NeighborCell] = []
    @State private var serving: SignalCell?
    @State private var scanning = false
    @State private var selectedBand = "auto"
    @State private var selectedPCI: String?
    @State private var alertText: String?
    @State private var working = false

    private let bands: [(String, String)] = [
        ("auto", "自动"), ("n78", "N78 3.5G"), ("n77", "N77 3.3G"),
        ("n41", "N41 2.5G"), ("n1", "N1 2.1G"), ("n28", "N28 700M")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                servingCard
                bandCard
                neighborCard
                applyCard
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task { await scan() }
        .alert("提示", isPresented: Binding(
            get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("好") { alertText = nil }
        } message: { Text(alertText ?? "") }
    }

    // MARK: Serving

    private var servingCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack {
                    SectionTitle(title: "当前接入", subtitle: "PCC", systemImage: "dot.radiowaves.left.and.right")
                    Button {
                        Task { await scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                            .rotationEffect(.degrees(scanning ? 360 : 0))
                            .animation(scanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                       value: scanning)
                    }
                }
                HStack(spacing: 10) {
                    bigMetric("PCI", serving?.pci ?? store.signal.pci)
                    bigMetric("频段", bandShort(serving?.band ?? store.signal.band))
                    bigMetric("SINR", store.signal.nrsinr,
                              tint: .signalColor(sinr: num(store.signal.nrsinr)))
                }
                HStack(spacing: 10) {
                    bigMetric("RSRP", store.signal.nrrsrp)
                    bigMetric("RSRQ", store.signal.nrrsrq)
                    bigMetric("带宽", serving?.bandwidth ?? "-")
                }
            }
        }
    }

    private func bigMetric(_ t: String, _ v: String, tint: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05))
        }
    }

    // MARK: Band picker

    private var bandCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                SectionTitle(title: "锁频频段", subtitle: "锁定后仅驻留该频段", systemImage: "square.grid.3x3")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(bands, id: \.0) { b in
                        Button {
                            selectedBand = b.0
                        } label: {
                            Text(b.1)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedBand == b.0 ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selectedBand == b.0 ? Color.cyan.opacity(0.22) : Color.white.opacity(0.05))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selectedBand == b.0 ? Color.cyan.opacity(0.6) : .white.opacity(0.1),
                                                      lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Neighbors

    private var neighborHeader: some View {
        HStack(spacing: 0) {
            Text("PCI").frame(width: 44, alignment: .leading)
            Text("频段").frame(width: 60, alignment: .leading)
            Text("RSRP").frame(maxWidth: .infinity, alignment: .trailing)
            Text("SINR").frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.35))
    }

    private func neighborRow(_ n: NeighborCell) -> some View {
        let selected = (selectedPCI == n.pci)
        return Button {
            toggleSelect(n)
        } label: {
            HStack(spacing: 0) {
                Text(n.pci)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, alignment: .leading)
                Text(bandShort(n.band))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 60, alignment: .leading)
                Text(n.rsrp)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(n.sinr)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.cellTint(n))
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(rowBackground(selected: selected))
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Color.cyan.opacity(0.16) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.cyan.opacity(0.5) : Color.clear,
                                  lineWidth: 0.8)
            }
    }

    private func toggleSelect(_ n: NeighborCell) {
        if selectedPCI == n.pci {
            selectedPCI = nil
        } else {
            selectedPCI = n.pci
            selectedBand = "auto"
        }
    }

    private var neighborCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack {
                    SectionTitle(title: "邻区列表", subtitle: "\(neighbors.count) 个", systemImage: "list.bullet")
                }
                if neighbors.isEmpty {
                    Text(scanning ? "扫描中…" : "暂无邻区数据")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 20)
                } else {
                    neighborHeader
                    ForEach(neighbors) { n in
                        neighborRow(n)
                    }
                }
            }
        }
    }

    // MARK: Apply

    private var applyCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack {
                    Text(selectedPCI != nil
                         ? "将锁定 PCI \(selectedPCI!)"
                         : (selectedBand == "auto" ? "当前：自动选网" : "将锁定频段 \(selectedBand.uppercased())"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if working { ProgressView().tint(.white).scaleEffect(0.8) }
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await applyLock() }
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("应用锁定")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [.cyan.opacity(0.75), .blue.opacity(0.75)],
                                                     startPoint: .leading, endPoint: .trailing))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)

                    Button {
                        Task { await unlock() }
                    } label: {
                        Text("解除")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                }
            }
        }
    }

    // MARK: Helpers

    private func num(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: "dB", with: "")
                .replacingOccurrences(of: "dBm", with: "")) ?? 0
    }

    private func bandShort(_ b: String) -> String {
        if b.contains("N78") { return "N78" }
        if b.contains("N77") { return "N77" }
        if b.contains("N41") { return "N41" }
        if b.contains("N1 ") || b.hasSuffix("N1)") { return "N1" }
        if b.contains("N28") { return "N28" }
        return b.isEmpty ? "-" : String(b.prefix(12))
    }

    // MARK: Scan

    private func scan() async {
        scanning = true
        if let s = try? await store.bridge.call("/api/device/signal") {
            let sc = SignalCell(
                arfcn: s.str("nrarfcn") ?? "",
                band: s.str("band") ?? "",
                bandwidth: s.str("nrdlbandwidth") ?? "",
                pci: s.str("pci") ?? "",
                rsrp: s.str("nrrsrp") ?? "",
                rsrq: s.str("nrrsrq") ?? "",
                rssi: s.str("nrrssi") ?? "",
                sinr: s.str("nrsinr") ?? "",
                isServing: true)
            serving = sc
        }
        var found: [NeighborCell] = []
        if let n = try? await store.bridge.call("/api/device/nbrcellinfo") {
            for b in CPEXML(raw: n.raw, isError: false).blocks("Cell") {
                guard let raw = b["_raw"] else { continue }
                let x = CPEXML(raw: raw, isError: false)
                let band = x.str("Band") ?? x.str("band") ?? ""
                if band.isEmpty && (x.str("nrrsrp") ?? "").isEmpty { continue }
                found.append(NeighborCell(
                    arfcn: x.str("NRARFCN") ?? x.str("arfcn") ?? "",
                    band: band.isEmpty ? "N77/N78" : band,
                    pci: x.str("PCI") ?? x.str("pci") ?? "",
                    rsrp: x.str("nrrsrp") ?? x.str("rsrp") ?? "-",
                    rsrq: x.str("nrrsrq") ?? x.str("rsrq") ?? "-",
                    rssi: x.str("nrrssi") ?? x.str("rssi") ?? "-",
                    sinr: x.str("nrsinr") ?? x.str("sinr") ?? "-"))
            }
        }
        // sort best first
        neighbors = found.sorted { $0.sinrValue > $1.sinrValue }
        scanning = false
    }

    // MARK: Lock

    private func applyLock() async {
        working = true
        defer { working = false }
        let body: String
        if let pci = selectedPCI {
            // cell lock: band N78, given PCI
            body = "<request><Band>\(bandNumber("n78"))</Band><LTEBand></LTEBand><NRBand>78</NRBand><PCI>\(pci)</PCI></request>"
        } else if selectedBand == "auto" {
            body = "<request></request>"
        } else {
            body = "<request><NRBand>\(selectedBand.replacingOccurrences(of: "n", with: ""))</NRBand></request>"
        }
        _ = await store.bridge.action("/api/net/net-mode", body: body)
        _ = await store.bridge.action("/api/device/netsel-rule", body: body)
        alertText = "锁定已应用，设备将重新搜网（约 30 秒）"
    }

    private func bandNumber(_ b: String) -> String {
        switch b {
        case "n78": return "78"
        case "n77": return "77"
        case "n41": return "41"
        case "n1": return "1"
        case "n28": return "28"
        default: return "0"
        }
    }

    private func unlock() async {
        working = true
        defer { working = false }
        selectedPCI = nil
        selectedBand = "auto"
        _ = await store.bridge.action("/api/net/net-mode", body: "<request></request>")
        _ = await store.bridge.action("/api/device/netsel-rule", body: "<request></request>")
        alertText = "已解除锁定，恢复自动选网"
    }
}
