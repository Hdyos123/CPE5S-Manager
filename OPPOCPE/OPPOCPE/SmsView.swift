import SwiftUI

struct SmsView: View {
    @ObservedObject var cpe: CpeClient
    @State private var selected: SmsSession?

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    summary
                    if cpe.smsSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(cpe.smsSessions) { s in
                            Button {
                                selected = s
                                cpe.loadSmsDetail(index: s.index)
                            } label: {
                                sessionRow(s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .background(Color.clear)
            .navigationTitle("短信")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        cpe.loadSms()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .background(AuroraBackground().opacity(0.6))
        }
        .navigationViewStyle(.stack)
        .onAppear { cpe.loadSms() }
        .sheet(item: $selected) { s in
            SmsDetailView(cpe: cpe, session: s)
        }
    }

    private var summary: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 46, height: 46)
                    Image(systemName: "message.fill")
                        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.6))
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("共 \(cpe.smsSessions.count) 个会话")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("未读 \(cpe.smsSessions.filter { $0.unread > 0 }.count) 条")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
    }

    private func sessionRow(_ s: SmsSession) -> some View {
        GlassCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.7, blue: 1.0).opacity(0.35),
                                                      Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.28)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Text(String(s.display.prefix(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.display)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        if let t = s.time {
                            Text(t)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Text(s.snippet ?? "（无内容）")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if s.unread > 0 {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.35, blue: 0.35))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("暂无短信")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

// MARK: - 会话详情
struct SmsDetailView: View {
    @ObservedObject var cpe: CpeClient
    let session: SmsSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sending = false
    @State private var sendFailed = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text(session.display)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(session.time ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Button { cpe.loadSmsDetail(index: session.index) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if sendFailed {
                    Text("发送失败，请检查号码或短信中心")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
                        .padding(.top, 6)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if cpe.smsMessages.isEmpty {
                            Text("加载中…")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, 40)
                        }
                        ForEach(cpe.smsMessages) { m in
                            bubble(m)
                        }
                    }
                    .padding(16)
                }

                HStack(spacing: 10) {
                    TextField("输入短信内容", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1))
                        .foregroundStyle(.white)
                    Button {
                        guard !draft.isEmpty else { return }
                        sending = true
                        cpe.sendSms(number: session.number ?? "", content: draft) { ok in
                            Task { @MainActor in
                                sending = false
                                if ok {
                                    draft = ""
                                    cpe.loadSmsDetail(index: session.index)
                                } else {
                                    sendFailed = true
                                }
                            }
                        }
                    } label: {
                        Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(draft.isEmpty ? Color.white.opacity(0.25) : Color(red: 0.35, green: 0.8, blue: 1.0))
                    }
                    .disabled(draft.isEmpty || sending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func bubble(_ m: SmsMessage) -> some View {
        HStack {
            if !m.isIncoming { Spacer(minLength: 40) }
            VStack(alignment: m.isIncoming ? .leading : .trailing, spacing: 4) {
                Text(m.content ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(m.isIncoming
                                  ? AnyShapeStyle(.ultraThinMaterial)
                                  : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.95),
                                                                          Color(red: 0.35, green: 0.35, blue: 0.85)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                    )
                if let t = m.time {
                    Text(t)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            if m.isIncoming { Spacer(minLength: 40) }
        }
    }
}
