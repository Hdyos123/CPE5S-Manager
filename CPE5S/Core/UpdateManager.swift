//
//  UpdateManager.swift
//  CPE5S
//
//  In-app update: checks GitHub releases, downloads the IPA, and hands it
//  to the system installer (or a "share to AltStore" fallback).
//

import Foundation
import SwiftUI

// MARK: - Model

struct ReleaseInfo: Decodable, Identifiable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
        let size: Int
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, body, assets
        case tagName = "tag_name"
        case publishedAt = "published_at"
    }

    var version: String {
        tagName.replacingOccurrences(of: "v", with: "")
    }

    var ipaAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".ipa") }
    }

    var manifestURL: String? {
        // OTA manifests are uploaded alongside the IPA by CI.
        assets.first { $0.name == "manifest.plist" }?.browserDownloadUrl
    }
}

// MARK: - Manager

@MainActor
final class UpdateManager: ObservableObject {

    /// Set to your repository.
    static let repo = "Hdyos123/CPE5S-Manager"
    static let apiBase = "https://api.github.com/repos/\(repo)/releases/latest"

    @Published var latest: ReleaseInfo?
    @Published var checking = false
    @Published var downloading = false
    @Published var progress: Double = 0
    @Published var errorText: String?
    @Published var hasUpdate = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: Check

    func check(silent: Bool = false) async {
        if checking { return }
        checking = true
        if !silent { errorText = nil }
        defer { checking = false }

        guard let url = URL(string: Self.apiBase) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                if !silent { errorText = "暂时无法获取版本信息" }
                return
            }
            let rel = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            latest = rel
            hasUpdate = Self.isNewer(rel.version, than: currentVersion)
                || (rel.version == currentVersion && Self.buildOf(rel) > (Int(currentBuild) ?? 0))
        } catch {
            if !silent { errorText = "检查失败：\(error.localizedDescription)" }
        }
    }

    static func parse(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parse(a), y = parse(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func buildOf(_ r: ReleaseInfo) -> Int {
        // Tag may be "v1.1.2+5"; fall back to 0.
        guard let plus = r.tagName.split(separator: "+").last,
              r.tagName.contains("+") else { return 0 }
        return Int(plus) ?? 0
    }

    // MARK: Install

    /// OTA install via itms-services (requires a properly signed IPA).
    func installOTA() {
        guard let m = latest?.manifestURL,
              let url = URL(string: "itms-services://?action=download-manifest&url="
                            + (m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m)) else {
            errorText = "该版本未提供 OTA 安装包"
            return
        }
        UIApplication.shared.open(url)
    }

    /// Download the IPA to disk, then hand it to the share sheet so the user
    /// can pick AltStore / Sideloadly.
    func downloadAndShare() async -> URL? {
        guard let asset = latest?.ipaAsset, let url = URL(string: asset.browserDownloadUrl) else {
            errorText = "未找到安装包"
            return nil
        }
        downloading = true
        progress = 0
        defer { downloading = false }

        do {
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                errorText = "下载失败"; return nil
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(asset.name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            progress = 1
            return dest
        } catch {
            errorText = "下载失败：\(error.localizedDescription)"
            return nil
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Dialog

struct UpdateSheet: View {
    @EnvironmentObject var updater: UpdateManager
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        ZStack {
            AuroraBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    if let rel = updater.latest {
                        versionCard(rel)
                        if let body = rel.body, !body.isEmpty {
                            notesCard(body)
                        }
                        actions(rel)
                    } else {
                        checking
                    }
                    Spacer(minLength: 20)
                }
                .padding(18)
            }
        }
        .sheet(isPresented: $showShare) {
            if let u = shareURL { ShareSheet(items: [u]) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("软件更新")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("当前 v\(updater.currentVersion) (\(updater.currentBuild))")
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
    }

    private var checking: some View {
        VStack(spacing: 10) {
            if let e = updater.errorText {
                Text(e).font(.system(size: 12)).foregroundStyle(.orange)
            } else {
                ProgressView().tint(.white)
                Text("正在检查更新…")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func versionCard(_ r: ReleaseInfo) -> some View {
        GlassCard(radius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("v\(r.version)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if updater.hasUpdate {
                        Text("可更新")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.green.opacity(0.18)))
                    } else {
                        Text("已是最新")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    Spacer()
                    Text(String(r.publishedAt.prefix(10)))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                if let a = r.ipaAsset {
                    Text("安装包 \(a.name) · \(String(format: "%.1f", Double(a.size) / 1_048_576)) MB")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private func notesCard(_ body: String) -> some View {
        GlassCard(radius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("更新内容")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actions(_ r: ReleaseInfo) -> some View {
        VStack(spacing: 10) {
            if updater.hasUpdate {
                if r.manifestURL != nil {
                    primaryButton("立即更新", icon: "arrow.down.circle.fill") {
                        updater.installOTA()
                    }
                }
                primaryButton(updater.downloading ? "下载中…" : "下载并安装",
                              icon: "square.and.arrow.down") {
                    Task {
                        if let u = await updater.downloadAndShare() {
                            shareURL = u
                            showShare = true
                        }
                    }
                }
                .disabled(updater.downloading)
            } else {
                primaryButton("已是最新版本", icon: "checkmark.circle.fill") { dismiss() }
            }
        }
    }

    private func primaryButton(_ title: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.8), Color.blue.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }
}
