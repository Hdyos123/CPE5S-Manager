import SwiftUI

// 锁频 / 锁小区：先用“网络模式 + 频段信息”可视化，
// 锁定操作走 /NasMng/SetNetMode 与预留的锁频接口（失败时提示设备不支持）。
struct LockBandView: View {
    @ObservedObject var cpe: CpeClient
    @State private var showNote = false
    @State private var toast: String?

    private let bands: [(String, String, String)] = [
        ("n78", "3.5 GHz", "5G 主力频段"),
        ("n41", "2.6 GHz", "5G 移动"),
        ("n28", "700 MHz", "5G 广覆盖"),
        ("n1", "2.1 GHz", "5G 通用"),
        ("B1", "2.1 GHz", "4G"),
        ("B3", "1.8 GHz", "4G 主力"),
        ("B8", "900 MHz", "4G 广覆盖"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("当前驻留", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Pill(text: cpe.netMode, tint: Color(red: 0.45, green: 0.9, blue: 0.7))
                        }
                        HStack(spacing: 0) {
                            MetricCell(title: "频段", value: cpe.signal5G != nil ? "n78" : "—")
                            MetricCell(title: "PCI", value: "\(cpe.pci)")
                            MetricCell(title: "Cell ID", value: cpe.cellId == 0 ? "—" : "\(cpe.cellId)")
                        }
                        HStack(spacing: 0) {
                            MetricCell(title: "RSRP", value: Fmt.dbm((cpe.signal5G ?? cpe.signal4G)?.rsrp))
                            MetricCell(title: "SINR", value: Fmt.dB((cpe.signal5G ?? cpe.signal4G)?.sinr, unit: "dB"))
                            MetricCell(title: "RSRQ", value: Fmt.dB((cpe.signal5G ?? cpe.signal4G)?.rsrq, unit: "dB"))
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("频段锁定", systemImage: "lock.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(bands, id: \.0) { b in
                                Button {
                                    toast = "该固件未开放锁频接口"
                                    showNote = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(b.0)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Text(b.2)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                        Spacer()
                                        Text(b.1)
                                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06)))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("锁小区（PCI）", systemImage: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("当前服务小区 PCI \(cpe.pci)，Cell ID \(cpe.cellId == 0 ? "—" : "\(cpe.cellId)")")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("该 OPPO 固件未在 WebUI 暴露锁频/锁小区接口，页面仅做展示；如需锁定请联系厂商或升级固件。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    .padding(.bottom, 16)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { toast = nil }
                    }
            }
        }
    }
}
