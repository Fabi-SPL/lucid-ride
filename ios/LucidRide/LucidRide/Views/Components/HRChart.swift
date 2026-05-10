import SwiftUI
import Charts

/// HR profile chart for a single ride. Real data from `realtime_health` window.
/// Falls back to an empty-state if no samples are available.
struct HRChart: View {
    let samples: [HRSample]
    let rideStart: Date
    let rideEnd: Date?

    private var hrSamples: [HRSample] {
        samples.filter { $0.hr != nil && $0.hr! > 30 }
    }

    private var hrPeak: Int? {
        hrSamples.compactMap { $0.hr.map(Int.init) }.max()
    }

    private var hrAvg: Int? {
        let vals = hrSamples.compactMap { $0.hr }
        guard !vals.isEmpty else { return nil }
        return Int(vals.reduce(0, +) / Double(vals.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(icon: "heart.fill", title: "HEART RATE", iconColor: DS.Colors.danger)
                if let avg = hrAvg, let peak = hrPeak {
                    Spacer()
                    HStack(spacing: 8) {
                        StatPill(icon: "waveform.path.ecg", value: "\(avg)", unit: "avg", color: DS.Colors.violet)
                        StatPill(icon: "arrow.up", value: "\(peak)", unit: "peak", color: DS.Colors.danger)
                    }
                }
            }

            if hrSamples.isEmpty {
                EmptyGlassState(
                    icon: "waveform.path.ecg",
                    title: "No HR samples in this window",
                    detail: "Make sure WHOOP was connected via LucidBridge during the ride."
                )
            } else {
                Chart(hrSamples) { sample in
                    if let hr = sample.hr {
                        AreaMark(
                            x: .value("time", sample.ts),
                            yStart: .value("baseline", 50),
                            yEnd: .value("hr", hr)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [DS.Colors.danger.opacity(0.30), DS.Colors.danger.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("time", sample.ts),
                            y: .value("hr", hr)
                        )
                        .foregroundStyle(DS.Colors.danger)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXScale(domain: rideStart...(rideEnd ?? Date()))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 25)) { value in
                        AxisGridLine().foregroundStyle(DS.Colors.border)
                        AxisValueLabel().font(DS.Font.micro).foregroundStyle(DS.Colors.textFaint)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 10)) { _ in
                        AxisGridLine().foregroundStyle(DS.Colors.border)
                        AxisValueLabel(format: .dateTime.hour().minute(),
                                       collisionResolution: .greedy)
                            .font(DS.Font.micro)
                            .foregroundStyle(DS.Colors.textFaint)
                    }
                }
                .frame(height: 180)
            }
        }
        .glassCard(padding: DS.Spacing.md)
    }
}
