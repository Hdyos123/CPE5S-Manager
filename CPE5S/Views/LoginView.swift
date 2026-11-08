//
//  LoginView.swift
//  CPE5S
//
//  Gateway login gate. Frosted card over the aurora backdrop, with address,
//  username, password, remember + auto-login switches.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: CPEStore

    @AppStorage("cpe.host") private var storedHost = CPEBridge.defaultHost
    @AppStorage("cpe.user") private var storedUser = CPEBridge.defaultUser
    @AppStorage("cpe.remember") private var remember = true
    @AppStorage("cpe.autoLogin") private var autoLogin = true

    @State private var host = CPEBridge.defaultHost
    @State private var user = CPEBridge.defaultUser
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var triedAuto = false

    private var bridge: CPEBridge { store.bridge }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer(minLength: 46)
                    brand
                    formCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            host = storedHost.isEmpty ? CPEBridge.defaultHost : storedHost
            user = storedUser.isEmpty ? CPEBridge.defaultUser : storedUser
            if remember { password = bridge.password }
            Task { await autoLoginIfEnabled() }
        }
    }

    // MARK: Brand

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.62, blue: 1.0).opacity(0.85),
                                                  Color(red: 0.18, green: 0.36, blue: 0.95).opacity(0.9)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.9)
                    .frame(width: 78, height: 78)
                Image(systemName: "wifi.router.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.5), radius: 24, y: 10)

            Text("华为CPE管理")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("连接您的 5G CPE 网关")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Form

    private var formCard: some View {
        GlassCard(radius: 28, padding: 20) {
            VStack(spacing: 14) {
                field(label: "网关地址", icon: "network",
                      text: $host, placeholder: CPEBridge.defaultHost,
                      keyboard: .URL, secure: false,
                      toggle: nil)

                field(label: "用户名", icon: "person",
                      text: $user, placeholder: CPEBridge.defaultUser,
                      keyboard: .default, secure: false,
                      toggle: nil)

                passiveField

                if let errorText {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(errorText)
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.orange.opacity(0.12))
                    }
                    .transition(.opacity)
                }

                switches

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        }
                        Text(busy ? "正在连接…" : "登 录")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 1.0).opacity(0.9),
                                                          Color(red: 0.15, green: 0.4, blue: 0.95).opacity(0.92)],
                                                 startPoint: .leading, endPoint: .trailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                    }
                    .shadow(color: Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.45), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(busy || password.isEmpty)
                .opacity(password.isEmpty ? 0.55 : 1)
            }
        }
    }

    private func field(label: String, icon: String, text: Binding<String>,
                       placeholder: String, keyboard: UIKeyboardType,
                       secure: Bool, toggle: Binding<Bool>?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.leading, 2)
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18)
                TextField("", text: text, prompt: Text(placeholder))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
            }
        }
    }

    private var passiveField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("密码")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.leading, 2)
            HStack(spacing: 9) {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18)
                Group {
                    if showPassword {
                        TextField("", text: $password, prompt: Text("WebUI 管理密码"))
                    } else {
                        SecureField("", text: $password, prompt: Text("WebUI 管理密码"))
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(.white)

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
            }
        }
    }

    private var switches: some View {
        VStack(spacing: 0) {
            switchRow("记住密码", subtitle: "下次自动填入", isOn: $remember) {
                if !remember { }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.6)
            switchRow("自动登录", subtitle: "启动时直接连接", isOn: $autoLogin) { }
        }
    }

    private func switchRow(_ title: String, subtitle: String,
                          isOn: Binding<Bool>,
                          onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.cyan)
                .onChange(of: isOn.wrappedValue) { _ in onChange() }
        }
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func submit() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        let ok = await bridge.signIn(host: host, user: user, password: password,
                                     remember: remember, autoLogin: autoLogin)
        busy = false
        if ok {
            store.isLoggedIn = true
            await store.refreshAll()
            store.start(interval: 1.0)
        } else {
            errorText = bridge.lastError ?? "登录失败，请检查地址与密码"
            store.isLoggedIn = false
        }
    }

    private func autoLoginIfEnabled() async {
        guard !triedAuto else { return }
        triedAuto = true
        guard autoLogin, remember, !password.isEmpty else { return }
        busy = true
        let ok = await bridge.signIn(host: host, user: user, password: password,
                                     remember: remember, autoLogin: autoLogin)
        busy = false
        if ok {
            store.isLoggedIn = true
            await store.refreshAll()
            store.start(interval: 1.0)
        } else if let e = bridge.lastError {
            errorText = e
        }
    }
}
