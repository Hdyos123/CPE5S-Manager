import SwiftUI

/// 速率趋势迷你折线图：60 个采样点（1 秒 1 点），下载/上传双曲线 + 渐变填充 + 端点光点
struct SpeedTrendChart: View {
    var download: [Int64]
    var upload: [Int64]
    var capacity: Int = 60

    private var peak: Double {
        max(Double(download.max() ?? 0), Double(upload.max() ?? 0), 800_000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("速率趋势 · 近 60 秒")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                HStack(spacing: 10) {
                    legend("下载", Color(red: 0.33, green: 0.85, blue: 1.0))
                    legend("上传", Color(red: 0.49, green: 0.88, blue: 0.55))
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    // 网格线
                    ForEach(0..<2, id: \.self) { i in
                        Path { p in
                            let y = h * (0.26 + 0.38 * CGFloat(i))
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.white.opacity(0.07),
                                style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    }

                    // 下载渐变填充
                    linePath(values: download, w: w, h: h, closed: true)
                        .fill(LinearGradient(colors: [Color(red: 0.33, green: 0.85, blue: 1.0).opacity(0.34),
                                                      Color(red: 0.33, green: 0.85, blue: 1.0).opacity(0.0)],
                                             startPoint: .top, endPoint: .bottom))

                    // 下载曲线
                    linePath(values: download, w: w, h: h)
                        .stroke(Color(red: 0.33, green: 0.85, blue: 1.0),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // 上传曲线
                    linePath(values: upload, w: w, h: h)
                        .stroke(Color(red: 0.49, green: 0.88, blue: 0.55).opacity(0.82),
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    // 端点光点
                    if let last = endpoint(values: download, w: w, h: h) {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color(red: 0.33, green: 0.85, blue: 1.0), lineWidth: 2))
                            .frame(width: 6, height: 6)
                            .shadow(color: Color(red: 0.33, green: 0.85, blue: 1.0).opacity(0.8), radius: 4)
                            .position(last)
                    }
                }
            }
            .frame(height: 56)
            .animation(.linear(duration: 0.4), value: download.last)

            HStack {
                Text("峰值 " + Fmt.rate(Int64(peak)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                Spacer()
                Text("now")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(c)
                .frame(width: 8, height: 3)
                .shadow(color: c.opacity(0.55), radius: 3)
            Text(t)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - 路径
    private func points(values: [Int64], w: CGFloat, h: CGFloat) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = w / CGFloat(capacity - 1)
        let p = peak * 1.15
        return values.enumerated().map { i, v in
            let ratio = min(1, Double(v) / p)
            return CGPoint(x: CGFloat(i) * step,
                           y: h - max(2, CGFloat(ratio) * (h - 6)))
        }
    }

    private func linePath(values: [Int64], w: CGFloat, h: CGFloat, closed: Bool = false) -> Path {
        var path = Path()
        let pts = points(values: values, w: w, h: h)
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1], cur = pts[i]
            let cx = (prev.x + cur.x) / 2
            path.addCurve(to: cur,
                          control1: CGPoint(x: cx, y: prev.y),
                          control2: CGPoint(x: cx, y: cur.y))
        }
        if closed, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
        return path
    }

    private func endpoint(values: [Int64], w: CGFloat, h: CGFloat) -> CGPoint? {
        points(values: values, w: w, h: h).last
    }
}
