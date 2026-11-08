//
//  CPE5SApp.swift
//  CPE5S
//

import SwiftUI
import UIKit

@main
struct CPE5SApp: App {
    @StateObject private var store = CPEStore()
    @AppStorage("cpe.refresh") private var refreshInterval: Double = 1.0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear {
                    store.start(interval: refreshInterval)
                    Task { await store.bridge.boot(); await store.refreshAll() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: CPEStore
    @State private var tab: Int = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            Group {
                switch tab {
                case 0: HomeView()
                case 1: SMSView()
                case 2: ControlView()
                case 3: LockBandView()
                case 4: ParamsView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                GlassTabBar(selection: $tab)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { BridgeHost.attach(bridge: store.bridge) }
    }
}

// MARK: - Tab bar

struct GlassTabBar: View {
    @Binding var selection: Int
    @Namespace private var ns

    private let items: [(String, String)] = [
        ("首页", "waveform.path.ecg"),
        ("短信", "message.fill"),
        ("控制", "slider.horizontal.3"),
        ("锁频", "antenna.radiowaves.left.and.right"),
        ("参数", "list.bullet.rectangle"),
        ("设置", "gearshape.fill")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = i
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.1)
                            .font(.system(size: 15, weight: selection == i ? .semibold : .regular))
                        Text(item.0)
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(selection == i ? Color.white : Color.white.opacity(0.38))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selection == i {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(.white.opacity(0.18)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.6))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom)))
        }
        .overlay {
            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.08)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Attach the hidden web view

@MainActor
enum BridgeHost {
    static func attach(bridge: CPEBridge) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let win = scene.windows.first(where: { $0.isKeyWindow }) else { return }
            bridge.attach(to: win)
        }
    }
}
