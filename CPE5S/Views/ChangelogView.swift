//
//  Changelog.swift
//  CPE5S
//
//  Version history shown when tapping the version number in Settings.
//

import SwiftUI

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let isCurrent: Bool
    let sections: [(title: String, items: [String], icon: String, tint: Color)]
}

enum Changelog {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static let all: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.4.0",
            date: "2026-11-09",
            isCurrent: true,
            sections: [
                ("登录完全跑通", [
                    "已在真实网关上验证：state=0 / level=2，管理员登录成功",
                    "servernonce 使用未解码原始值参与 HMAC（base64 的 + / 被 XML 转义成 &#x2B; &#x2F;）",
                    "token 每次仅 32 位，取到后立即使用，中间不得插入其他请求",
                    "移除重试时的页面重载，避免会话 Cookie 被轮换导致 token 失配"
                ], "checkmark.seal.fill", .green)
            ]),
        ChangelogEntry(
            version: "1.3.3",
            date: "2026-11-09",
            isCurrent: false,
            sections: [
                ("登录密码校验修复（108006 根因）", [
                    "根因：固件返回的 servernonce 中 base64 的 + 和 / 被 XML 转义为 &#x2B; 和 &#x2F;，前端直接使用原始字符串参与 HMAC 计算",
                    "此前 App 会把实体解码后再计算，导致 proof 与网关不一致，永远返回密码错误",
                    "改为使用未解码的原始值，已与浏览器算出的 proof 逐字节比对完全一致"
                ], "key.horizontal.fill", .green)
            ]),
        ChangelogEntry(
            version: "1.3.0",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("原生网络层（彻底修复 125003）", [
                    "不再依赖 WebView 内的 fetch 完成登录与数据请求",
                    "改用原生 URLSession，SessionID 通过 Cookie 请求头显式携带，完全绕开 WebKit 的 ITP 限制",
                    "SCRAM-SHA256 算法用 Swift 重写（含手写 PBKDF2），已与固件算法逐字节比对一致",
                    "WebView 仅用于获取初始会话 Cookie 与加载加密库"
                ], "bolt.horizontal.circle.fill", .green)
            ]),
        ChangelogEntry(
            version: "1.2.0",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("125003 根因修复", [
                    "定位根因：WebKit 的 ITP 会隐藏 HttpOnly Cookie，导致 JS fetch 请求不带 SessionID，网关一律返回 125003",
                    "改为从原生层读取 SessionID，并显式通过 Cookie 请求头注入每次 fetch",
                    "已用真实网关验证：带 Cookie 后一次即可拿到 salt"
                ], "lock.shield.fill", .orange),
                ("界面", [
                    "登录页底部显示版本号，可直接点开检查更新",
                    "发现新版本时在登录页显示绿点提示"
                ], "arrow.triangle.2.circlepath", .cyan)
            ]),
        ChangelogEntry(
            version: "1.1.2",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("会话修复（125003）", [
                    "每次登录都重新加载网关页面，不再用 reload() 复用可能缺失 Cookie 的会话",
                    "登录前校验 SessionID Cookie 是否已下发，缺失则自动重试三次",
                    "页面打开时即预热隐藏 WebView（页面 + Cookie + forge.js），点登录即刻可用",
                    "会话无法建立时给出明确提示，而不是笼统的「握手失败」"
                ], "lock.shield.fill", .orange)
            ]),
        ChangelogEntry(
            version: "1.1.1",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("登录握手修复", [
                    "修正请求顺序：先查登录状态，再取令牌并「立即」发起握手，中间不再插入其他请求",
                    "该固件会在任意请求后使令牌失效，这是上次报 125003 的原因",
                    "握手返回 125003 时自动刷新令牌重试一次",
                    "已用真实网关验证：一次即可拿到 salt 并完成登录"
                ], "bolt.fill", .orange)
            ]),
        ChangelogEntry(
            version: "1.1.0",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("登录修复", [
                    "改用 callAsyncJavaScript 执行登录脚本（evaluateJavaScript 不支持 async/await，此前只会拿到 Promise 对象）",
                    "密码与用户名改为通过 arguments 传参，避免字符串拼进 JS 体导致的转义问题",
                    "等待页面内置的 forge.js 就绪后再发起握手，最多轮询 8 秒",
                    "密码错误时不再清空输入框，可直接重试"
                ], "key.fill", .orange),
                ("界面修复", [
                    "密码框占位符改为「请输入管理密码」，不再与提示文字混淆",
                    "网关地址、用户名、密码统一为同一套输入组件",
                    "密码显隐按钮移入输入框内，修复点击区域"
                ], "paintbrush.fill", .cyan),
                ("版本显示", [
                    "版本号改为读取构建设置（MARKETING_VERSION / CURRENT_PROJECT_VERSION）",
                    "修复此前 Info.plist 硬编码导致签名后始终显示 1.0 的问题",
                    "新增本更新日志页"
                ], "tag.fill", .green)
            ]),
        ChangelogEntry(
            version: "1.0.1",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("登录架构", [
                    "隐藏 WKWebView 挂载到 window 后执行 JS（未挂载时 iOS 会暂停 JS 执行）",
                    "会话 Cookie 持久化，重启 App 后可复用",
                    "接口返回 125003 时自动重新登录并重试一次"
                ], "network", .blue),
                ("用户代理", [
                    "新增 Desktop UA（Mac Safari 17.4），获取 PC 版完整字段",
                    "设置页可切换电脑版 / 移动版"
                ], "safari.fill", .purple)
            ]),
        ChangelogEntry(
            version: "1.0.0",
            date: "2026-11-08",
            isCurrent: false,
            sections: [
                ("首次发布", [
                    "登录页：默认 192.168.8.1 / admin，支持记住密码与自动登录",
                    "首页：上下行速率每秒刷新、RSRP / SINR / RSRQ / RSSI、当前小区、流量统计",
                    "短信：收发件箱、未读标记、新建短信、详情查看",
                    "控制：移动数据 / 飞行 / 漫游 / WLAN 开关、重启设备、重启移动网络、恢复出厂",
                    "锁频：邻区扫描（按 SINR 着色排序）、频段锁定、PCI 锁定",
                    "参数：设备 / 网络 / 射频 / 终端四组，点按复制",
                    "设置：会话状态、密码、刷新频率、关于"
                ], "sparkles", .yellow),
                ("视觉", [
                    "动态极光背景",
                    "全局毛玻璃材质与渐变描边",
                    "胶囊式底部导航栏，选中项弹性滑动",
                    "玻璃质感 App 图标"
                ], "circle.hexagongrid.fill", .pink)
            ])
    ]
}

// MARK: - View

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    ForEach(Changelog.all) { entry in
                        entryCard(entry)
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("更新日志")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("当前版本 v\(Changelog.appVersion) (\(Changelog.buildNumber))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }

    private func entryCard(_ e: ChangelogEntry) -> some View {
        GlassCard(radius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("v\(e.version)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if e.isCurrent {
                        Text("当前")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.cyan.opacity(0.18)))
                            .overlay(Capsule().strokeBorder(.cyan.opacity(0.45), lineWidth: 0.6))
                    }
                    Spacer()
                    Text(e.date)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.32))
                }

                ForEach(Array(e.sections.enumerated()), id: \.offset) { _, sec in
                    sectionBlock(sec.title, items: sec.items, icon: sec.icon, tint: sec.tint)
                }
            }
        }
    }

    private func sectionBlock(_ title: String, items: [String],
                              icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(tint.opacity(0.55))
                        .frame(width: 3.5, height: 3.5)
                        .padding(.top, 6)
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 2)
    }
}
