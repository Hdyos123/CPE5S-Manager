import SwiftUI

struct SettingsView: View {
    @ObservedObject var cpe: CpeClient
    @State private var host = "192.168.0.1"
    @State private var user = "admin"
    @State private var pwd = ""
    @State private var auto = true
    @State private var saved = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("连接设置", systemImage: "network")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        labeledField("网关地址", text: $host, keyboard: .numbersAndPunctuation)
                        labeledField("用户名", text: $user)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("密码")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                            SecureField("密码", text: $pwd)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.07)))
                        }

                        Toggle(isOn: $auto) {
                            Text("自动登录")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .tint(Color(red: 0.35, green: 0.8, blue: 0.6))

                        Button {
                            cpe.host = host
                            cpe.user = user
                            cpe.pwd = pwd
                            cpe.autoLogin = auto
                            saved = true
                        } label: {
                            Text("保存设置")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.6, blue: 1.0),
                                                                  Color(red: 0.36, green: 0.38, blue: 0.92)],
                                                         startPoint: .leading, endPoint: .trailing)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("关于", systemImage: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        infoRow("应用", "OPPO CPE Manager")
                        infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        infoRow("会话", cpe.connected ? "已连接 • \(cpe.host)" : "未连接")
                        infoRow("刷新", "实时速率 1 秒 / 状态 2 秒")
                        infoRow("架构", "隐藏 WKWebView + WebCrypto")
                    }
                }

                Button {
                    cpe.disconnect()
                } label: {
                    Text("退出登录")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 1, green: 0.35, blue: 0.35).opacity(0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 1, green: 0.4, blue: 0.4).opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onAppear {
            host = cpe.host
            user = cpe.user
            pwd = cpe.pwd
            auto = cpe.autoLogin
        }
        .overlay(alignment: .bottom) {
            if saved {
                Text("已保存")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, 16)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        withAnimation { saved = false }
                    }
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(v).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }
    }
}
