//
//  SMSView.swift
//  CPE5S
//
//  SMS inbox / outbox with a composer.
//

import SwiftUI

struct SMSView: View {
    @EnvironmentObject var store: CPEStore
    @State private var messages: [CPESms] = []
    @State private var loading = false
    @State private var box = 1          // 1 = inbox, 2 = outbox
    @State private var showingCompose = false
    @State private var detail: CPESms?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                if loading && messages.isEmpty {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if messages.isEmpty {
                    emptyState
                } else {
                    ForEach(messages) { m in
                        Button { detail = m } label: { smsCard(m) }
                            .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingCompose) {
            ComposeSMSView { phone, text in
                await send(phone: phone, text: text)
            }
        }
        .sheet(item: $detail) { m in
            SMSDetailView(sms: m)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        GlassCard(radius: 26, padding: 16) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("短信").font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("共 \(messages.count) 条 · 未读 \(store.smsUnread)")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button {
                        showingCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.7))
                    }
                }
                // segmented
                HStack(spacing: 0) {
                    segButton("收件箱", active: box == 1) { box = 1; Task { await load() } }
                    segButton("发件箱", active: box == 2) { box = 2; Task { await load() } }
                }
                .padding(3)
                .background(Capsule().fill(.white.opacity(0.07)))
            }
        }
    }

    private func segButton(_ t: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(.white.opacity(0.16)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.6))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.25))
            Text(box == 1 ? "收件箱为空" : "发件箱为空")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func smsCard(_ m: CPESms) -> some View {
        GlassCard(radius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    if m.unread {
                        Circle().fill(.blue).frame(width: 6, height: 6)
                            .shadow(color: .blue.opacity(0.9), radius: 3)
                    }
                    Text(m.phone.isEmpty ? "未知号码" : m.phone)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(m.date)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(m.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Load

    func load() async {
        loading = true
        defer { loading = false }
        let page = box == 1
            ? "/api/sms/sms-list"
            : "/api/sms/sms-list"
        let body = box == 1
            ? "<request><PageIndex>1</PageIndex><ReadCount>50</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>"
            : "<request><PageIndex>1</PageIndex><ReadCount>50</ReadCount><BoxType>2</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>"
        guard let r = await store.bridge.action(page, body: body) else {
            messages = []; return
        }
        messages = parse(r.raw)
        if box == 1 { await markReadIfNeeded(r.raw) }
    }

    private func parse(_ raw: String) -> [CPESms] {
        var out: [CPESms] = []
        for blk in CPEXML(raw: raw, isError: false).blocks("Message") {
            guard let s = blk["_raw"] else { continue }
            let x = CPEXML(raw: s, isError: false)
            let content = (x.str("Content") ?? "")
                .replacingOccurrences(of: "\n", with: " ")
            out.append(CPESms(
                index: x.str("Index") ?? "",
                phone: x.str("Phone") ?? "",
                content: Self.decodeB64(content),
                date: Self.formatDate(x.str("Date") ?? ""),
                unread: x.str("Smstat") == "0",
                box: x.str("SmsType") == String(box) ? (box == 1 ? "inbox" : "outbox") : "inbox"
            ))
        }
        return out
    }

    /// Huawei returns SMS bodies base64-encoded when they contain UTF-8.
    static func decodeB64(_ s: String) -> String {
        guard let d = Data(base64Encoded: s),
              let t = String(data: d, encoding: .utf8),
              !t.isEmpty else { return s }
        // Heuristic: base64 of plain ASCII also decodes; only accept if printable.
        let printable = t.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil || " .,:;!?()-+/@#%_=[]{}'\"\n".unicodeScalars.contains($0) }
        return printable ? t : s
    }

    static func formatDate(_ d: String) -> String {
        // format: 26,11,08,13,45,00,+32  or  2026-11-08 13:45:00
        if d.contains("-") { return String(d.prefix(16)) }
        let parts = d.split(separator: ",")
        if parts.count >= 5 {
            let y = parts[0], mo = parts[1], da = parts[2], h = parts[3], mi = parts[4]
            return "20\(y)-\(mo)-\(da) \(h):\(mi)"
        }
        return d
    }

    private func markReadIfNeeded(_ raw: String) async {
        let idxs = CPEXML(raw: raw, isError: false).blocks("Message").compactMap { b -> String? in
            guard let s = b["_raw"] else { return nil }
            let x = CPEXML(raw: s, isError: false)
            guard x.str("Smstat") == "0", let i = x.str("Index") else { return nil }
            return i
        }
        guard !idxs.isEmpty else { return }
        let body = "<request>" + idxs.map { "<Index>\($0)</Index>" }.joined() + "</request>"
        _ = await store.bridge.action("/api/sms/set-read", body: body)
    }

    private func send(phone: String, text: String) async {
        let b64 = Data(text.utf8).base64EncodedString()
        let body = "<request><Index>-1</Index><Phones><Phone>\(phone)</Phone></Phones><Sca></Sca><Content>\(b64)</Content><Length>\(text.count)</Length><Reserved>1</Reserved><Date>-1</Date></request>"
        _ = await store.bridge.action("/api/sms/send-sms", body: body)
        await load()
    }
}

// MARK: - Detail

struct SMSDetailView: View {
    let sms: CPESms
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sms.phone.isEmpty ? "未知号码" : sms.phone)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text(sms.date).font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                GlassCard(radius: 20, padding: 16) {
                    ScrollView {
                        Text(sms.content)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Compose

struct ComposeSMSView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var text = ""
    @State private var sending = false
    let onSend: (String, String) async -> Void

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 14) {
                HStack {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("新建短信").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        Task {
                            sending = true
                            await onSend(phone, text)
                            sending = false
                            dismiss()
                        }
                    } label: {
                        if sending { ProgressView().tint(.white) }
                        else { Text("发送").font(.system(size: 14, weight: .bold)).foregroundStyle(.cyan) }
                    }
                    .disabled(phone.isEmpty || text.isEmpty || sending)
                }
                GlassCard(radius: 18, padding: 14) {
                    TextField("", text: $phone, prompt: Text("收件人号码"))
                        .keyboardType(.phonePad)
                        .foregroundStyle(.white)
                }
                GlassCard(radius: 18, padding: 14) {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(18)
        }
    }
}
