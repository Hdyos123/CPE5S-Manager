import SwiftUI

struct ControlView: View {
    @ObservedObject var cpe: CpeClient
    @State private var confirmReboot = false
    @State private var confirmReset = false
    @State private var busy = false
    @State private var toast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("网络开关", systemImage: "switch.2")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        toggleRow(icon: "wifi", title: "Wi-Fi", subtitle: cpe.wifiEnable == 1 ? "已开启" : "已关闭",
                                  isOn: Binding(get: { cpe.wifiEnable == 1 },
                                                set: { cpe.setWifi($0) }))
                        Divider().overlay(Color.white.opacity(0.1))
                        toggleRow(icon: "antenna.radiowaves.left.and.right", title: "移动数据", subtitle: "蜂窝网络连接",
                                  isOn: Binding(get: { cpe.netMode != "无服务" }, set: { _ in }))
                            .disabled(true)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("网络模式", systemImage: "cellularbars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(["自动 (SA/NSA/4G)", "自动 (SA/4G)", "仅 5G (NSA)", "仅 5G (SA)", "仅 4G"], id: \.self) { m in
                            Button {
                                cpe.api("/NasMng/SetNetMode", payload: ["NetMode": m]) { _ in
                                    toast = "已提交：\(m)"
                                }
                            } label: {
                                HStack {
                                    Text(m)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.25))
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                GlassCard {
                    VStack(spacing: 12) {
                        Label("设备维护", systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        actionRow(icon: "arrow.clockwise.circle.fill", title: "重启设备",
                                  subtitle: "约 1-2 分钟恢复", tint: Color(red: 0.35, green: 0.75, blue: 1.0)) {
                            confirmReboot = true
                        }
                        actionRow(icon: "arrow.counterclockwise.circle.fill", title: "恢复出厂设置",
                                  subtitle: "清除全部配置，需谨慎", tint: Color(red: 1.0, green: 0.45, blue: 0.4)) {
                            confirmReset = true
                        }
                        actionRow(icon: "power.circle.fill", title: "断开连接",
                                  subtitle: "退出登录并停止轮询", tint: Color.white.opacity(0.7)) {
                            cpe.disconnect()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .alert("确认重启设备？", isPresented: $confirmReboot) {
            Button("取消", role: .cancel) {}
            Button("重启", role: .destructive) {
                busy = true
                cpe.reboot { ok in
                    busy = false
                    toast = ok ? "重启指令已发送" : "重启失败"
                }
            }
        } message: {
            Text("设备将断开所有连接，约 1-2 分钟后恢复。")
        }
        .alert("确认恢复出厂设置？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("恢复出厂", role: .destructive) {
                busy = true
                cpe.factoryReset { ok in
                    busy = false
                    toast = ok ? "已发送恢复指令" : "操作失败"
                }
            }
        } message: {
            Text("此操作会清除全部配置并重启设备，不可撤销。")
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { toast = nil }
                    }
            }
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.45, green: 0.8, blue: 1.0))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.35, green: 0.8, blue: 0.6))
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
