//
//  SettingsView.swift
//  CPE5S
//
//  Password, session, refresh, about.
//

import SwiftUI

struct SettingsView: View {
    static var appVersion: String {
        CPEBridge.appVersion + " (" + CPEBridge.appBuild + ")"
    }

    @EnvironmentObject var store: CPEStore
    @EnvironmentObject var updater: UpdateManager
    @AppStorage("cpe.password") private var password = ""
    @AppStorage("cpe.refresh") private var refreshInterval: Double = 1.0
    @State private var draftPassword = ""
    @State private var showPassword = false
    @State private var reconnecting = false
    @State private var message: String?
    @State private var showingChangelog = false
    @State private var showingUpdate = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                sessionCard
                passwordCard
                uaCard
                refreshCard
                aboutCard
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onAppear {
            draftPassword = password
            Task { await updater.check(silent: true) }
        }
        .sheet(isPresented: $showingUpdate) {
            UpdateSheet()
                .environmentObject(updater)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onAppear { Task { await updater.check() } }
        }
        .sheet(isPresented: $showingChangelog) {
            ChangelogView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    // MARK: Session

    private var sessionCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: store.bridge.sessionReady ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(store.bridge.sessionReady ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("会话状态")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(store.bridge.sessionReady ? "已登录 · 网关 \(store.bridge.host)" : "未登录")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    if store.bridge.isLoggingIn {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                }
                if let err = store.bridge.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(err).font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.orange.opacity(0.12)))
                }
                Button {
                    Task {
                        reconnecting = true
                        await store.bridge.boot(force: true)
                        reconnecting = false
                        message = store.bridge.sessionReady ? "已重新登录" : (store.bridge.lastError ?? "重连失败")
                    }
                } label: {
                    HStack {
                        Image(systemName: reconnecting ? "hourglass" : "arrow.clockwise")
                        Text(reconnecting ? "重连中…" : "重新连接")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
                .disabled(reconnecting)
            }
        }
    }

    // MARK: Password

    private var passwordCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "登录密码", subtitle: "WebUI 管理密码", systemImage: "key.fill")
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $draftPassword, prompt: Text("管理密码"))
                        } else {
                            SecureField("", text: $draftPassword, prompt: Text("管理密码"))
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .font(.system(size: 13))

                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                }

                Button {
                    password = draftPassword
                    Task {
                        await store.bridge.boot(force: true)
                        message = store.bridge.sessionReady ? "密码已保存，登录成功" : (store.bridge.lastError ?? "登录失败")
                    }
                } label: {
                    Text("保存并登录")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: [.cyan.opacity(0.7), .blue.opacity(0.75)],
                                                     startPoint: .leading, endPoint: .trailing))
                        }
                }
                .buttonStyle(.plain)
                .disabled(draftPassword.isEmpty)

                Text("密码仅保存在本机 Keychain 之外的应用偏好中，不会上传。")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: Refresh

    private var uaCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "浏览器标识", subtitle: "User-Agent", systemImage: "safari")
                Text("小程序按 UA 返回不同界面。电脑版字段更全（含邻区、MCS、RANK、CQI）。")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach([(true, "电脑版"), (false, "移动版")], id: \.0) { item in
                        let active = store.bridge.isDesktopUA == item.0
                        Button {
                            Task { await store.bridge.setUserAgent(desktop: item.0) }
                        } label: {
                            VStack(spacing: 3) {
                                Text(item.1)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.0 ? "PC WebUI" : "手机布局")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .foregroundStyle(active ? Color.white : Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(active ? Color.cyan.opacity(0.22) : Color.white.opacity(0.05))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(active ? Color.cyan.opacity(0.55) : Color.white.opacity(0.1),
                                                  lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Refresh

    private var refreshCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "刷新频率", subtitle: "首页实时数据", systemImage: "timer")
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { v in
                        Button {
                            refreshInterval = v
                            store.start(interval: v)
                        } label: {
                            Text(v < 1 ? "0.5秒" : "\(Int(v))秒")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(refreshInterval == v ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(refreshInterval == v ? Color.cyan.opacity(0.22) : Color.white.opacity(0.05))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(refreshInterval == v ? Color.cyan.opacity(0.55) : .white.opacity(0.1),
                                                      lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: About

    private var aboutCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: [.cyan.opacity(0.6), .blue.opacity(0.7)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("华为CPE管理")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("华为 5G CPE 5s 控制台")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Button { showingChangelog = true } label: {
                        HStack(spacing: 3) {
                            Text("v" + Self.appVersion)
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "info.circle")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.07)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Text("数据来源").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("内置 WKWebView · 网关直连")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack {
                    Text("最后更新").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(store.lastUpdate, style: .time)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Button { showingUpdate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text(updater.hasUpdate ? "发现新版本 v\(updater.latest?.version ?? "")" : "检查更新")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        if updater.hasUpdate {
                            Circle().fill(.green).frame(width: 6, height: 6)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(updater.hasUpdate ? .green : .white.opacity(0.65))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill((updater.hasUpdate ? Color.green : Color.white).opacity(0.08))
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
