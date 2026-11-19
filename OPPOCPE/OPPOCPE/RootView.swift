import SwiftUI

struct RootView: View {
    @StateObject private var cpe = CpeClient()
    @State private var tab = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            if cpe.connected {
                VStack(spacing: 0) {
                    Group {
                        switch tab {
                        case 0: HomeView(cpe: cpe)
                        case 1: SmsView(cpe: cpe)
                        case 2: ControlView(cpe: cpe)
                        case 3: LockBandView(cpe: cpe)
                        case 4: ParamsView(cpe: cpe)
                        default: SettingsView(cpe: cpe)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    GlassTabBar(selection: $tab)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LoginView(cpe: cpe)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: cpe.connected)
    }
}

// MARK: - 玻璃底栏
struct GlassTabBar: View {
    @Binding var selection: Int

    private let items: [(String, String, String)] = [
        ("house.fill", "首页", "首页"),
        ("message.fill", "短信", "短信"),
        ("slider.horizontal.3", "控制", "控制"),
        ("antenna.radiowaves.left.and.right", "锁频", "锁频"),
        ("list.bullet.rectangle", "参数", "参数"),
        ("gearshape.fill", "设置", "设置"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selection = i
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].0)
                            .font(.system(size: 17, weight: selection == i ? .semibold : .regular))
                        Text(items[i].1)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(selection == i ? Color.white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(selection == i ? Color.white.opacity(0.16) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(selection == i ? Color.white.opacity(0.25) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

// MARK: - 登录页
struct LoginView: View {
    @ObservedObject var cpe: CpeClient
    @State private var host = "192.168.0.1"
    @State private var user = "admin"
    @State private var pwd = ""
    @State private var auto = true
    @State private var showPwd = false
    @FocusState private var focus: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 96, height: 96)
                    Circle()
                        .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        .frame(width: 96, height: 96)
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(spacing: 4) {
                    Text("OPPO CPE")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("无线数据终端控制台")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.bottom, 6)

                GlassCard {
                    VStack(spacing: 14) {
                        field(icon: "network", title: "网关地址") {
                            TextField("192.168.0.1", text: $host)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: 0)
                        }
                        field(icon: "person", title: "用户名") {
                            TextField("admin", text: $user)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: 1)
                        }
                        field(icon: "lock", title: "密码") {
                            HStack {
                                Group {
                                    if showPwd {
                                        TextField("密码", text: $pwd)
                                    } else {
                                        SecureField("密码", text: $pwd)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: 2)
                                Button { showPwd.toggle() } label: {
                                    Image(systemName: showPwd ? "eye.slash" : "eye")
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }

                        Toggle(isOn: $auto) {
                            Text("记住密码并自动登录")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .tint(Color(red: 0.35, green: 0.75, blue: 1.0))
                    }
                }

                Button {
                    focus = nil
                    cpe.host = host
                    cpe.user = user
                    cpe.pwd = pwd
                    cpe.autoLogin = auto
                    cpe.connect { _, _ in }
                } label: {
                    HStack(spacing: 8) {
                        if cpe.connecting {
                            ProgressView().tint(.white)
                        }
                        Text(cpe.connecting ? "正在登录…" : "登 录")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.62, blue: 1.0),
                                                          Color(red: 0.38, green: 0.36, blue: 0.95)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.45), radius: 16, y: 8)
                }
                .disabled(cpe.connecting)

                if let err = cpe.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5))
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            host = cpe.host
            user = cpe.user
            pwd = cpe.pwd
            auto = cpe.autoLogin
            if auto && !pwd.isEmpty {
                cpe.connect { _, _ in }
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            content()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
