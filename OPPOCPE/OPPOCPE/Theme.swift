import SwiftUI

// MARK: - 极光背景
struct AuroraBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.09, blue: 0.18),
                         Color(red: 0.10, green: 0.06, blue: 0.20),
                         Color(red: 0.02, green: 0.08, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            // 光斑
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.55), .clear],
                                     center: .center, startRadius: 4, endRadius: 220))
                .frame(width: 420, height: 420)
                .offset(x: -120 + 30 * sin(phase), y: -260 + 20 * cos(phase * 0.7))
                .blur(radius: 40)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.65, green: 0.35, blue: 1.0).opacity(0.5), .clear],
                                     center: .center, startRadius: 4, endRadius: 200))
                .frame(width: 400, height: 400)
                .offset(x: 150 + 25 * cos(phase * 0.9), y: -40 + 30 * sin(phase * 0.6))
                .blur(radius: 45)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.20, green: 0.95, blue: 0.85).opacity(0.35), .clear],
                                     center: .center, startRadius: 4, endRadius: 190))
                .frame(width: 380, height: 380)
                .offset(x: -60 + 20 * sin(phase * 1.2), y: 320 + 15 * cos(phase))
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - 玻璃卡片
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

// MARK: - 小胶囊
struct Pill: View {
    var text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.8))
            .foregroundStyle(tint)
    }
}

// MARK: - 信号格
struct SignalBars: View {
    var level: Int
    var tint: Color = .green

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < level ? tint.gradient : LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: CGFloat(8 + i * 6))
            }
        }
    }
}

// MARK: - 指标小格
struct MetricCell: View {
    var title: String
    var value: String
    var unit: String? = nil
    var icon: String? = nil
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.55))

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: mono ? 15 : 21, weight: .bold,
                                  design: mono ? .monospaced : .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
