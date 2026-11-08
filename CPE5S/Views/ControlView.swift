//
//  ControlView.swift
//  CPE5S
//
//  Device control: reboot, mobile data, airplane mode, WLAN, restore.
//

import SwiftUI

struct ControlView: View {
    @EnvironmentObject var store: CPEStore

    @State private var mobileData = true
    @State private var airplane = false
    @State private var wlanOn = false
    @State private var roamOn = false
    @State private var alertText: String?
    @State private var showRebootConfirm = false
    @State private var showRestoreConfirm = false
    @State private var working = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                headerCard
                toggleCard
                rebootCard
                restoreCard
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task { await loadState() }
        .alert("提示", isPresented: Binding(
            get: { alertText != nil },
            set: { if !$0 { alertText = nil } })) {
            Button("好") { alertText = nil }
        } message: { Text(alertText ?? "") }
        .confirmationDialog("确认重启设备？", isPresented: $showRebootConfirm, titleVisibility: .visible) {
            Button("重启", role: .destructive) { Task { await reboot() } }
            Button("取消", role: .cancel) {}
        } message: { Text("设备将断开连接约 1-2 分钟") }
        .confirmationDialog("恢复出厂设置？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复出厂", role: .destructive) { Task { await restore() } }
            Button("取消", role: .cancel) {}
        } message: { Text("所有配置将被清除，包括 WLAN 名称和密码。此操作不可撤销。") }
    }

    // MARK: Header

    private var headerCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("设备控制")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("在线 \(Fmt.duration(store.traffic.connectTime))")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    if working { ProgressView().tint(.white) }
                }
                HStack(spacing: 6) {
                    GlassPill(text: store.connected ? "在线" : "离线",
                              icon: store.connected ? "checkmark.circle" : "xmark.circle",
                              tint: store.connected ? .green : .orange)
                    GlassPill(text: store.device.networkType, icon: "wifi")
                    Spacer()
                }
            }
        }
    }

    // MARK: Toggles

    private var toggleCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 14) {
                SectionTitle(title: "网络开关", systemImage: "switch.2")
                toggleRow("移动数据", subtitle: "蜂窝网络开关", icon: "antenna.radiowaves.left.and.right",
                          tint: .cyan, isOn: $mobileData) { v in
                    await setMobileData(v)
                }
                Divider().overlay(Color.white.opacity(0.10))
                toggleRow("飞行模式", subtitle: "关闭所有无线信号", icon: "airplane",
                          tint: .orange, isOn: $airplane) { v in
                    await setAirplane(v)
                }
                Divider().overlay(Color.white.opacity(0.10))
                toggleRow("数据漫游", subtitle: "允许使用漫游网络", icon: "globe",
                          tint: .purple, isOn: $roamOn) { v in
                    await setRoaming(v)
                }
                Divider().overlay(Color.white.opacity(0.10))
                toggleRow("WLAN", subtitle: "无线局域网", icon: "wifi",
                          tint: .green, isOn: $wlanOn) { v in
                    await setWlan(v)
                }
            }
        }
    }

    private func toggleRow(_ title: String, subtitle: String, icon: String,
                           tint: Color, isOn: Binding<Bool>,
                           onChange: @escaping (Bool) async -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { nv in
                    isOn.wrappedValue = nv
                    Task { await onChange(nv) }
                }))
                .labelsHidden()
                .tint(tint)
        }
    }

    // MARK: Reboot / restore

    private var rebootCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                SectionTitle(title: "系统操作", systemImage: "gearshape.2")
                actionButton("重启设备", subtitle: "断开约 1-2 分钟",
                             icon: "power", tint: .orange) {
                    showRebootConfirm = true
                }
                actionButton("重启移动网络", subtitle: "重新拨号，不断开 Wi-Fi",
                             icon: "arrow.triangle.2.circlepath", tint: .cyan) {
                    Task { await reconnect() }
                }
            }
        }
    }

    private var restoreCard: some View {
        GlassCard(radius: 26, padding: 18) {
            actionButton("恢复出厂设置", subtitle: "清除所有配置，不可撤销",
                         icon: "exclamationmark.triangle", tint: .red) {
                showRestoreConfirm = true
            }
        }
    }

    private func actionButton(_ title: String, subtitle: String, icon: String,
                              tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load

    private func loadState() async {
        if let m = try? await store.bridge.call("/api/dialup/mobile-dataswitch") {
            mobileData = m.str("dataswitch") == "1"
        }
        if let p = try? await store.bridge.call("/api/device/control") {
            _ = p
        }
        if let w = try? await store.bridge.call("/api/wlan/status-switch-settings") {
            wlanOn = w.str("WifiStatus") == "1"
        }
    }

    // MARK: Actions

    private func setMobileData(_ on: Bool) async {
        working = true
        let b = "<request><dataswitch>\(on ? 1 : 0)</dataswitch></request>"
        _ = await store.bridge.action("/api/dialup/mobile-dataswitch", body: b)
        working = false
    }

    private func setAirplane(_ on: Bool) async {
        working = true
        let b = "<request><dataswitch>\(on ? 3 : 1)</dataswitch></request>"
        _ = await store.bridge.action("/api/dialup/mobile-dataswitch", body: b)
        working = false
    }

    private func setRoaming(_ on: Bool) async {
        working = true
        _ = await store.bridge.action("/api/dialup/connection",
                                      body: "<request><RoamAutoConnectEnable>\(on ? 1 : 0)</RoamAutoConnectEnable></request>")
        working = false
    }

    private func setWlan(_ on: Bool) async {
        working = true
        _ = await store.bridge.action("/api/wlan/status-switch-settings",
                                      body: "<request><WifiStatus>\(on ? 1 : 0)</WifiStatus></request>")
        working = false
    }

    private func reboot() async {
        working = true
        let r = await store.bridge.action("/api/device/control",
                                          body: "<request><Control>1</Control></request>")
        working = false
        if let r, r.isError {
            alertText = "重启请求失败"
        } else {
            alertText = "重启指令已发送，设备将在约 1 分钟后恢复"
        }
    }

    private func reconnect() async {
        working = true
        _ = await store.bridge.action("/api/dialup/mobile-dataswitch",
                                      body: "<request><dataswitch>0</dataswitch></request>")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        _ = await store.bridge.action("/api/dialup/mobile-dataswitch",
                                      body: "<request><dataswitch>1</dataswitch></request>")
        working = false
        alertText = "已重新拨号"
    }

    private func restore() async {
        working = true
        _ = await store.bridge.action("/api/device/control",
                                      body: "<request><Control>2</Control></request>")
        working = false
        alertText = "恢复出厂指令已发送"
    }
}
