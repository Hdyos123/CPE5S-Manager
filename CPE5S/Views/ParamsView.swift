//
//  ParamsView.swift
//  CPE5S
//
//  Full parameter sheet — device info, WAN, radio params, hosts.
//

import SwiftUI

struct ParamsView: View {
    @EnvironmentObject var store: CPEStore
    @State private var group: Int = 0
    @State private var copied: String?

    private let groups = ["设备", "网络", "射频", "终端"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                groupPicker
                switch group {
                case 0: deviceGroup
                case 1: networkGroup
                case 2: radioGroup
                default: hostsGroup
                }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task { if store.device.imei == "-" { await store.refreshAll() } }
        .overlay(alignment: .top) {
            if let c = copied {
                Text("已复制 \(c)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.7))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var groupPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, t in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { group = i }
                } label: {
                    Text(t)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(group == i ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if group == i {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(.white.opacity(0.16)))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.6))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.06)))
        }
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        }
    }

    private var deviceGroup: some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(spacing: 0) {
                row("设备型号", store.device.model)
                row("序列号", store.device.serial)
                row("IMEI", store.device.imei)
                row("IMSI", store.device.imsi)
                row("本机号码", store.device.msisdn)
                row("硬件版本", store.device.hardware)
                row("软件版本", store.device.software)
                row("WebUI 版本", store.device.webUI)
                row("LAN MAC", store.device.mac)
                row("开机时长", Fmt.duration(store.device.uptime), last: true)
            }
        }
    }

    private var networkGroup: some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(spacing: 0) {
                row("网络类型", store.device.networkType)
                row("运营商", store.device.operatorName)
                row("PLMN", store.device.plmn)
                row("流量 WAN IP", store.device.wanIP)
                row("WAN IPv6", store.device.wanIPv6)
                row("本月下载", Fmt.bytes(store.traffic.monthDown))
                row("本月上传", Fmt.bytes(store.traffic.monthUp))
                row("今日用量", Fmt.bytes(store.traffic.todayUsed))
                row("累计下载", Fmt.bytes(store.traffic.totalDown))
                row("累计上传", Fmt.bytes(store.traffic.totalUp), last: true)
            }
        }
    }

    private var radioGroup: some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(spacing: 0) {
                row("频段", store.signal.band)
                row("PCI", store.signal.pci)
                row("CELL ID", store.device.cellID)
                row("RSRP", store.signal.nrrsrp)
                row("RSRQ", store.signal.nrrsrq)
                row("SINR", store.signal.nrsinr)
                row("RSSI", store.signal.nrrssi)
                row("5G MCS 上行", store.device.mcsUL)
                row("5G MCS 下行", store.device.mcsDL)
                row("RANK", store.device.rank)
                row("CQI", store.device.cqi, last: true)
            }
        }
    }

    private var hostsGroup: some View {
        VStack(spacing: 10) {
            ForEach(store.hosts) { h in
                GlassCard(radius: 18, padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: h.iface == "有线" ? "cable.connector" : "wifi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(h.active ? .green : .white.opacity(0.3))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill((h.active ? Color.green : Color.white).opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(h.active ? 1 : 0.5))
                                .lineLimit(1)
                            Text("\(h.ip) · \(h.mac)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(h.active ? "在线" : "离线")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(h.active ? .green : .white.opacity(0.3))
                            Text(h.iface)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }
            if store.hosts.isEmpty {
                Text("暂无终端")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 40)
            }
        }
    }

    private func row(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Button {
                UIPasteboard.general.string = v
                withAnimation { copied = k }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { copied = nil }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(k)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 86, alignment: .leading)
                    Text(v.isEmpty ? "-" : v)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            if !last {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.6)
            }
        }
    }
}
