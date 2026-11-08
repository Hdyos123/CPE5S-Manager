//
//  HomeView.swift
//  CPE5S
//
//  Dashboard: live throughput, signal quality, serving cell.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: CPEStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                statusHeader
                speedCard
                signalCard
                cellCard
                trafficCard
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .refreshable { await store.refreshAll() }
    }

    // MARK: Header

    private var statusHeader: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.connected ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                                .shadow(color: (store.connected ? Color.green : Color.orange).opacity(0.8), radius: 4)
                            Text(store.connected ? "已连接" : "连接中…")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text(store.device.model)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(store.device.operatorName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        SignalBars(bars: store.signal.bars,
                                   height: 30,
                                   tint: .signalColor(sinr: sinrValue))
                        Text(store.device.networkType)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                HStack(spacing: 6) {
                    GlassPill(text: store.signal.band.replacingOccurrences(of: "@", with: " "),
                              icon: "antenna.radiowaves.left.and.right", tint: .cyan)
                    GlassPill(text: "PCI \(store.signal.pci)", icon: "dot.radiowaves.left.and.right")
                    Spacer()
                }
            }
        }
    }

    private var sinrValue: Double {
        Double(store.signal.nrsinr.replacingOccurrences(of: "dB", with: "")) ?? 0
    }

    // MARK: Speed

    private var speedCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack {
                    SectionTitle(title: "实时速率", subtitle: "每秒刷新", systemImage: "arrow.up.arrow.down")
                }
                HStack(spacing: 12) {
                    speedTile(title: "下载", value: Fmt.rateValue(store.traffic.dlRate),
                              unit: Fmt.rateUnit(store.traffic.dlRate),
                              icon: "arrow.down", tint: .cyan, raw: store.traffic.dlRate)
                    speedTile(title: "上传", value: Fmt.rateValue(store.traffic.ulRate),
                              unit: Fmt.rateUnit(store.traffic.ulRate),
                              icon: "arrow.up", tint: .green, raw: store.traffic.ulRate)
                }
            }
        }
    }

    private func speedTile(title: String, value: String, unit: String,
                           icon: String, tint: Color, raw: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            // live activity bar: log scale, 1MB/s = full
            GlassProgress(value: logScale(raw), tint: tint, height: 4)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
        }
    }

    private func logScale(_ v: Int) -> Double {
        guard v > 0 else { return 0 }
        let mb = Double(v) / 1_048_576.0
        return min(1.0, log10(1 + mb * 1000) / 3.0)
    }

    // MARK: Signal

    private var signalCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 14) {
                SectionTitle(title: "信号质量", subtitle: "5G NR", systemImage: "waveform.path")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metricTile("RSRP", store.signal.nrrsrp, tint: rsrpTint)
                    metricTile("SINR", store.signal.nrsinr, tint: .signalColor(sinr: sinrValue))
                    metricTile("RSRQ", store.signal.nrrsrq, tint: .white)
                    metricTile("RSSI", store.signal.nrrssi, tint: .white)
                }
            }
        }
    }

    private var rsrpTint: Color {
        let v = Double(store.signal.nrrsrp.replacingOccurrences(of: "dBm", with: "")) ?? -140
        if v >= -85 { return .green }
        if v >= -95 { return .yellow }
        if v >= -105 { return .orange }
        return .red
    }

    private func metricTile(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        }
    }

    // MARK: Serving cell

    private var cellCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                SectionTitle(title: "当前小区", subtitle: "PCC", systemImage: "dot.radiowaves.right")
                if let s = store.signal.serving {
                    HStack(spacing: 0) {
                        cellCol("PCI", s.pci)
                        cellCol("频段", s.band)
                        cellCol("带宽", s.bandwidth)
                        cellCol("SINR", s.sinr, tint: .signalColor(sinr: s.sinrValue))
                    }
                } else {
                    HStack(spacing: 0) {
                        cellCol("PCI", store.signal.pci)
                        cellCol("CELL ID", String(store.device.cellID.suffix(6)))
                        cellCol("TAC", "-")
                        cellCol("CQI", store.device.cqi)
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                HStack {
                    infoRow("小区标识", store.device.cellID)
                    infoRow("PLMN", store.device.plmn)
                }
            }
        }
    }

    private func cellCol(_ t: String, _ v: String, tint: Color = .white) -> some View {
        VStack(spacing: 3) {
            Text(t).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(_ t: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: Traffic

    private var trafficCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                SectionTitle(title: "流量统计", subtitle: "本月 / 本次", systemImage: "chart.bar.fill")
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本月已用").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        Text(Fmt.bytes(store.traffic.monthDown + store.traffic.monthUp))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("今日").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        Text(Fmt.bytes(store.traffic.todayUsed))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                VStack(spacing: 7) {
                    HStack {
                        Label("下载", systemImage: "arrow.down").font(.system(size: 10))
                            .foregroundStyle(.cyan.opacity(0.8))
                        Spacer()
                        Text(Fmt.bytes(store.traffic.currentDownload))
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    HStack {
                        Label("上传", systemImage: "arrow.up").font(.system(size: 10))
                            .foregroundStyle(.green.opacity(0.8))
                        Spacer()
                        Text(Fmt.bytes(store.traffic.currentUpload))
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    HStack {
                        Label("在线时长", systemImage: "clock").font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text(Fmt.duration(store.traffic.connectTime))
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
    }
}
