import SwiftUI

struct HomeView: View {
    @ObservedObject var cpe: CpeClient

    private var liveBand: CpeClient.Band? { cpe.signal5G ?? cpe.signal4G }
    private var liveName: String { cpe.signal5G != nil ? "5G NR" : (cpe.signal4G != nil ? "4G LTE" : "无信号") }
    private var level: Int { Fmt.bars(rsrp: liveBand?.rsrp) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header

                signalCard

                speedCard

                cellCard

                terminalCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .onAppear { Task { await cpe.refreshMeta() } }
        .refreshable {
            await cpe.refreshHome()
            await cpe.refreshMeta()
        }
    }

    // MARK: 顶部
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OPPO CPE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(Fmt.operatorName(cpe.plmn))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 8) {
                Pill(text: cpe.netMode, tint: Color(red: 0.4, green: 0.9, blue: 0.7))
                HStack(spacing: 6) {
                    Circle()
                        .fill(cpe.connected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(cpe.connected ? "在线" : "离线")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.8))
            }
        }
        .padding(.top, 4)
    }

    // MARK: 信号
    private var signalCard: some View {
        GlassCard(padding: 18) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: signalFraction)
                        .stroke(
                            AngularGradient(colors: [Color(red: 0.25, green: 0.95, blue: 0.7),
                                                     Color(red: 0.3, green: 0.7, blue: 1.0),
                                                     Color(red: 0.75, green: 0.5, blue: 1.0)],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: signalFraction)

                    VStack(spacing: 2) {
                        Text(Fmt.dbm(liveBand?.rsrp))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("RSRP")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SignalBars(level: level)
                        Text(liveName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 16) {
                        smallStat("SINR", Fmt.dB(liveBand?.sinr, unit: "dB"))
                        smallStat("RSRQ", Fmt.dB(liveBand?.rsrq, unit: "dB"))
                    }
                    if let s = cpe.sim {
                        HStack(spacing: 6) {
                            Image(systemName: "simcard.fill")
                                .font(.system(size: 10))
                            Text(s.iccidMasked)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
            }

            SpeedTrendChart(download: cpe.downHistory, upload: cpe.upHistory)
        }
    }

    private var signalFraction: CGFloat {
        guard let r = liveBand?.rsrp else { return 0.02 }
        // -70dBm 以上满格，-120dBm 为 0
        return max(0.02, min(1.0, (r + 120) / 50))
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    // MARK: 实时速率
    private var speedCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("实时速率", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("1s 刷新")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                HStack(spacing: 12) {
                    speedBlock(icon: "arrow.down.circle.fill", title: "下载",
                               value: Fmt.rate(cpe.downRate), total: Fmt.bytes(cpe.downBytes),
                               tint: Color(red: 0.3, green: 0.85, blue: 1.0))
                    Divider().overlay(Color.white.opacity(0.12)).frame(height: 46)
                    speedBlock(icon: "arrow.up.circle.fill", title: "上传",
                               value: Fmt.rate(cpe.upRate), total: Fmt.bytes(cpe.upBytes),
                               tint: Color(red: 0.55, green: 0.9, blue: 0.55))
                }

                GeometryReader { geo in
                    let total = max(1.0, Double(cpe.downRate + cpe.upRate))
                    let dRatio = CGFloat(Double(cpe.downRate) / total)
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.9),
                                                          Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.35)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, (geo.size.width - 3) * dRatio))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.55, green: 0.9, blue: 0.55).opacity(0.6))
                    }
                }
                .frame(height: 7)
            }
        }
    }

    private func speedBlock(icon: String, title: String, value: String, total: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 12))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("累计 " + total)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 小区
    private var cellCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("服务小区", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 0) {
                    MetricCell(title: "PCI", value: "\(cpe.pci)")
                    MetricCell(title: "Cell ID", value: cpe.cellId == 0 ? "—" : "\(cpe.cellId)", mono: true)
                    MetricCell(title: "PLMN", value: cpe.plmn, mono: true)
                }
            }
        }
    }

    // MARK: 在线终端
    private var terminalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("在线设备", systemImage: "desktopcomputer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Pill(text: "\(cpe.terminals.count)", tint: Color(red: 0.6, green: 0.8, blue: 1.0))
                }
                if cpe.terminals.isEmpty {
                    Text("暂无在线设备")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.vertical, 6)
                } else {
                    ForEach(cpe.terminals.prefix(5)) { t in
                        HStack(spacing: 10) {
                            Image(systemName: (t.ifname ?? "").contains("wlan") ? "wifi" : "cable.connector")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name ?? "未知设备")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("\(t.ip ?? "-")  ·  \(t.mac ?? "-")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.38))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}
