//
//  GlassTheme.swift
//  CPE5S
//
//  Frosted-glass design system: layered materials, animated aurora backdrop,
//  specular borders and soft inner highlights.
//

import SwiftUI

// MARK: - Background

struct AuroraBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.04, green: 0.06, blue: 0.13),
                Color(red: 0.07, green: 0.10, blue: 0.22),
                Color(red: 0.03, green: 0.05, blue: 0.10)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)

            // moving blobs
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.22, green: 0.45, blue: 1.0).opacity(0.55), .clear],
                                     center: .center, startRadius: 5, endRadius: 260))
                .frame(width: 520, height: 520)
                .offset(x: -140 + sin(phase) * 40, y: -260 + cos(phase) * 30)
                .blendMode(.plusLighter)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.45), .clear],
                                     center: .center, startRadius: 5, endRadius: 240))
                .frame(width: 480, height: 480)
                .offset(x: 150 + cos(phase) * 40, y: 60 + sin(phase) * 35)
                .blendMode(.plusLighter)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.10, green: 0.80, blue: 0.75).opacity(0.38), .clear],
                                     center: .center, startRadius: 5, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: 40 + sin(phase * 0.7) * 50, y: 330)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    var radius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.02)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Pill / chip

struct GlassPill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(tint.opacity(0.14)))
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
    }
}

// MARK: - Section header

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Signal bars

struct SignalBars: View {
    let bars: Int          // 0...5
    var height: CGFloat = 26
    var tint: Color = .green

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<5) { i in
                let active = i < bars
                let h = height * (0.38 + CGFloat(i) * 0.155)
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(active
                          ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.13)))
                    .frame(width: height * 0.155, height: h)
            }
        }
    }
}

// MARK: - Colour helpers

extension Color {
    static func signalColor(sinr: Double) -> Color {
        if sinr >= 15 { return .green }
        if sinr >= 8 { return .yellow }
        if sinr >= 0 { return .orange }
        return .red
    }

    static func cellTint(_ c: NeighborCell) -> Color {
        if c.sinrValue >= 15 { return .green }
        if c.sinrValue >= 8 { return .yellow }
        if c.sinrValue >= 0 { return .orange }
        return .red
    }
}

// MARK: - Progress bar

struct GlassProgress: View {
    var value: Double      // 0...1
    var tint: Color = .blue
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
