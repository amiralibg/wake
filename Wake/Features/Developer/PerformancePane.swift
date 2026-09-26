import Charts
import SwiftUI

/// Load timings and Core Web Vitals, a live frame-rate meter, what the page weighs
/// by resource type, DOM statistics, and a quick audit of common problems.
///
/// Limitation: WebKit doesn't expose JavaScript heap size (`performance.memory`) or
/// long-task entries, and its Web Vitals support depends on the macOS version; any
/// metric it doesn't report is shown as "Not supported" rather than guessed. For CPU
/// and layout profiling, use Timelines in the Web Inspector.
struct PerformancePane: View {
    let page: BrowserPage
    @State private var expandedAudit: String?

    private var session: DevToolsSession { page.inspector }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Page load").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Reload and Measure") {
                        page.reloadFromOrigin()
                    }
                    .controlSize(.small)
                    Button {
                        Task { await refresh() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Measure again")
                }
                if let metrics = session.metrics {
                    VitalsGrid(metrics: metrics)
                    FPSMeter(samples: session.fpsSamples)
                    WeightChart(metrics: metrics)
                    PageStats(metrics: metrics)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
                AuditList(audits: session.audits, expanded: $expandedAudit, onRun: { Task { await session.runAudits() } })
            }
            .padding(12)
        }
        .task(id: session.documentLoads) {
            await refresh()
            // Metrics settle as the page finishes loading; FPS is sampled every second.
            var tick = 0
            while !Task.isCancelled {
                await session.sampleFPS()
                tick += 1
                if tick % 3 == 0 { await session.loadMetrics() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { session.stopFPS() }
    }

    private func refresh() async {
        await session.loadMetrics()
        await session.runAudits()
    }
}

// MARK: Vitals

private struct VitalsGrid: View {
    let metrics: DevToolsSession.Metrics

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
            MetricTile(name: "Time to First Byte", short: "TTFB", value: metrics.ttfb, unit: .ms, thresholds: (800, 1800), supported: true)
            MetricTile(name: "First Contentful Paint", short: "FCP", value: metrics.fcp, unit: .ms, thresholds: (1800, 3000), supported: metrics.support["fcp"] ?? false)
            MetricTile(name: "Largest Contentful Paint", short: "LCP", value: metrics.lcp, unit: .ms, thresholds: (2500, 4000), supported: metrics.support["lcp"] ?? false)
            MetricTile(name: "Cumulative Layout Shift", short: "CLS", value: metrics.cls, unit: .score, thresholds: (0.1, 0.25), supported: metrics.support["cls"] ?? false)
            MetricTile(name: "Interaction to Next Paint", short: "INP", value: metrics.inp, unit: .ms, thresholds: (200, 500), supported: metrics.support["inp"] ?? false)
            MetricTile(name: "DOMContentLoaded", short: "DCL", value: metrics.dcl, unit: .ms, thresholds: nil, supported: true)
            MetricTile(name: "Load", short: "Load", value: metrics.load, unit: .ms, thresholds: nil, supported: true)
        }
    }
}

/// Good / needs improvement / poor, with the web.dev thresholds. The rating is
/// always spelled out beside its colour.
private struct MetricTile: View {
    enum Unit { case ms, score }

    let name: String
    let short: String
    let value: Double?
    let unit: Unit
    let thresholds: (Double, Double)?
    let supported: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(short).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(formatted)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .contentTransition(.numericText())
            if let rating {
                Label(rating.label, systemImage: rating.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(rating.color)
            } else {
                Text(supported ? (value == nil ? "Waiting…" : " ") : "Not supported")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8, style: .continuous))
        .help(name)
    }

    private var formatted: String {
        guard supported, let value else { return "—" }
        switch unit {
        case .ms: return NetworkItem.milliseconds(value)
        case .score: return String(format: "%.3f", value)
        }
    }

    private var rating: (label: String, symbol: String, color: Color)? {
        guard supported, let value, let thresholds else { return nil }
        if value <= thresholds.0 { return ("Good", "checkmark.circle.fill", Color(nsColor: .systemGreen)) }
        if value <= thresholds.1 { return ("Needs work", "exclamationmark.triangle.fill", Color(nsColor: .systemOrange)) }
        return ("Poor", "xmark.octagon.fill", Color(nsColor: .systemRed))
    }
}

// MARK: FPS

private struct FPSMeter: View {
    let samples: [Double]
    @Environment(AppearanceSettings.self) private var appearance
    private var tint: Color { appearance.accent.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Frame rate").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(samples.last.map { "\(Int($0.rounded())) fps" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                if let low = samples.suffix(30).min() {
                    Text("low \(Int(low.rounded()))").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("Second", index), y: .value("FPS", value))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Second", index), y: .value("FPS", value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Target", 60))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXScale(domain: 0...59)
            .chartYScale(domain: 0...max(120, (samples.max() ?? 60) + 10))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 30, 60, 120]) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 80)
            .accessibilityLabel("Frame rate over the last minute")
            Text("Frames the page painted each second while this pane is open. Scroll or interact with the page to see drops.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: Weight

private struct WeightChart: View {
    let metrics: DevToolsSession.Metrics
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        let rows = merged.filter { $0.decoded > 0 || $0.count > 0 }.prefix(8)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Page weight").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(metrics.requests) requests · \(bytes(metrics.transfer)) transferred · \(bytes(metrics.decoded)) decoded")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text("No subresources yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Chart(Array(rows), id: \.type) { row in
                    BarMark(x: .value("Size", row.decoded), y: .value("Type", row.type))
                        .foregroundStyle(appearance.accent.color.gradient)
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(bytes(row.decoded)) · \(row.count)")
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel().font(.system(size: 10)) }
                }
                .frame(height: CGFloat(rows.count) * 22 + 8)
            }
        }
    }

    /// One row per label: "fetch" and "xmlhttprequest" (or "css" and "link") share
    /// one, and as separate bars on the same row their labels drew over each other.
    private var merged: [(type: String, count: Int, decoded: Int)] {
        var rows: [(type: String, count: Int, decoded: Int)] = []
        for entry in metrics.byType {
            let name = label(entry.type)
            if let index = rows.firstIndex(where: { $0.type == name }) {
                rows[index].count += entry.count
                rows[index].decoded += entry.decoded
            } else {
                rows.append((name, entry.count, entry.decoded))
            }
        }
        return rows.sorted { $0.decoded > $1.decoded }
    }

    private func label(_ type: String) -> String {
        switch type {
        case "img": "Images"
        case "script": "Scripts"
        case "css", "link": "Styles & links"
        case "fetch", "xmlhttprequest": "Fetch/XHR"
        case "other": "Other"
        default: type.capitalized
        }
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

private struct PageStats: View {
    let metrics: DevToolsSession.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Document").font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow { stat("DOM elements", "\(metrics.domNodes)"); stat("Max depth", "\(metrics.domDepth)") }
                GridRow { stat("Scripts", "\(metrics.scripts)"); stat("Stylesheets", "\(metrics.styleSheets)") }
                GridRow { stat("Images", "\(metrics.images)"); stat("Iframes", "\(metrics.iframes)") }
                GridRow { stat("Viewport", metrics.viewport); stat("Pixel ratio", String(format: "%.1f×", metrics.devicePixelRatio)) }
                GridRow { stat("Protocol", metrics.protocolName.isEmpty ? "—" : metrics.protocolName); stat("Navigation", metrics.navigationType.isEmpty ? "—" : metrics.navigationType) }
            }
        }
    }

    @ViewBuilder private func stat(_ label: String, _ value: String) -> some View {
        Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        Text(value).font(.system(size: 11, design: .monospaced))
    }
}

// MARK: Audits

private struct AuditList: View {
    let audits: [DevToolsSession.Audit]
    @Binding var expanded: String?
    let onRun: () -> Void

    var body: some View {
        let passed = audits.filter { $0.state == .pass }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ScoreRing(fraction: audits.isEmpty ? 0 : Double(passed) / Double(audits.count))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Audit").font(.system(size: 12, weight: .semibold))
                    Text(audits.isEmpty ? "Checks for accessibility, SEO and loading problems." : "\(passed) of \(audits.count) checks pass")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Again", action: onRun).controlSize(.small)
            }
            VStack(spacing: 0) {
                ForEach(audits.sorted { order($0.state) < order($1.state) }) { audit in
                    Button {
                        withAnimation(.hover) { expanded = expanded == audit.id ? nil : audit.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: symbol(audit.state)).foregroundStyle(color(audit.state)).frame(width: 14)
                                Text(audit.title).font(.system(size: 11.5))
                                Spacer(minLength: 4)
                                if audit.count > 0, audit.state != .pass {
                                    Text("\(audit.count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expanded == audit.id ? 90 : 0))
                            }
                            if expanded == audit.id, !audit.detail.isEmpty {
                                Text(audit.detail)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.leading, 22)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(audit.title): \(audit.state.rawValue)")
                    Divider().padding(.leading, 32)
                }
            }
            .background(.primary.opacity(0.03), in: .rect(cornerRadius: 8, style: .continuous))
        }
    }

    private func order(_ state: DevToolsSession.Audit.State) -> Int {
        switch state { case .fail: 0; case .warn: 1; case .pass: 2 }
    }

    private func symbol(_ state: DevToolsSession.Audit.State) -> String {
        switch state {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }

    private func color(_ state: DevToolsSession.Audit.State) -> Color {
        switch state {
        case .pass: Color(nsColor: .systemGreen)
        case .warn: Color(nsColor: .systemOrange)
        case .fail: Color(nsColor: .systemRed)
        }
    }
}

private struct ScoreRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.deck, value: fraction)
            Text("\(Int((fraction * 100).rounded()))")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(width: 36, height: 36)
    }
}
