import SwiftUI

let numberFont = Font.system(size: 30, weight: .medium, design: .rounded).monospacedDigit()

struct Card<Content: View>: View {
    let title: String
    let note: String?
    let content: Content

    init(title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct Stat: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(numberFont).foregroundStyle(tint)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LineChart: View {
    struct Series {
        let name: String
        let color: Color
        let points: [DataPoint]
        var dashed = false
    }

    let series: [Series]
    var reference: (value: Double, label: String)? = nil
    var unit: String = ""
    var height: CGFloat = 190

    private var allValues: [Double] {
        series.flatMap { $0.points.map { $0.value } } + (reference.map { [$0.value] } ?? [])
    }

    private var pointCount: Int {
        series.map { $0.points.count }.max() ?? 0
    }

    var body: some View {
        if pointCount < 1 {
            VStack(spacing: 6) {
                Text(L.t("Henüz veri yok", "No data yet"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(L.t("İlk ölçümden sonra burada trend görünecek",
                         "The trend will appear after your first measurement"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ChartCanvas(
                        series: series,
                        reference: reference,
                        count: pointCount,
                        bounds: LineChart.bounds(for: allValues),
                        size: geo.size
                    )
                }
                .frame(height: height)

                LineChartLegend(series: series, unit: unit)
            }
        }
    }

    static func bounds(for values: [Double]) -> (min: Double, max: Double) {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.25, 0.5)
        return (lo - pad, hi + pad)
    }
}

struct ChartCanvas: View {
    let series: [LineChart.Series]
    let reference: (value: Double, label: String)?
    let count: Int
    let bounds: (min: Double, max: Double)
    let size: CGSize

    private func x(_ i: Int) -> CGFloat {
        count == 1 ? size.width / 2 : size.width * CGFloat(i) / CGFloat(count - 1)
    }

    private func y(_ v: Double) -> CGFloat {
        let span = max(bounds.max - bounds.min, 0.0001)
        return size.height - CGFloat((v - bounds.min) / span) * size.height
    }

    private func linePath(_ s: LineChart.Series) -> Path {
        var p = Path()
        for (i, pt) in s.points.enumerated() {
            let point = CGPoint(x: x(i), y: y(pt.value))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }

    private func horizontal(at value: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: value))
        p.addLine(to: CGPoint(x: size.width, y: value))
        return p
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { i in
                horizontal(at: size.height * CGFloat(i) / 3)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }

            if let ref = reference, ref.value >= bounds.min, ref.value <= bounds.max {
                horizontal(at: y(ref.value))
                    .stroke(Color.red.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Text(ref.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .offset(x: 2, y: y(ref.value) - 14)
            }

            ForEach(Array(series.enumerated()), id: \.offset) { item in
                linePath(item.element)
                    .stroke(item.element.color,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
                                               dash: item.element.dashed ? [5, 4] : []))

                ForEach(Array(item.element.points.enumerated()), id: \.element.id) { pair in
                    Circle()
                        .fill(item.element.color)
                        .frame(width: 5, height: 5)
                        .position(x: x(pair.offset), y: y(pair.element.value))
                }
            }
        }
    }
}

struct LineChartLegend: View {
    let series: [LineChart.Series]
    let unit: String

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(series.enumerated()), id: \.offset) { item in
                HStack(spacing: 6) {
                    Capsule().fill(item.element.color).frame(width: 12, height: 3)
                    Text(item.element.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let last = item.element.points.last {
                        Text(String(format: "%.1f\(unit)", last.value))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
            }
            Spacer()
        }
    }
}

struct Heatmap: View {
    let days: [(date: Date, count: Int)]

    private var rowLabels: [String] {
        L.lang == .tr
            ? ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
            : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private var columns: [[Int?]] {
        let cal = Calendar.current
        var result: [[Int?]] = []
        var current = [Int?](repeating: nil, count: 7)
        var currentWeek: Int? = nil

        for d in days {
            let week = cal.component(.weekOfYear, from: d.date)
            if let cw = currentWeek, cw != week {
                result.append(current)
                current = [Int?](repeating: nil, count: 7)
            }
            currentWeek = week
            let rowIndex = (cal.component(.weekday, from: d.date) + 5) % 7
            current[rowIndex] = d.count
        }
        result.append(current)
        return result
    }

    var body: some View {
        let maxCount = max(days.map { $0.count }.max() ?? 1, 1)
        let cols = columns

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(rowLabels, id: \.self) { r in
                    Text(r)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(height: 13)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { col in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { r in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(fill(col.element[r], max: maxCount))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fill(_ count: Int?, max: Int) -> Color {
        guard let count else { return Color.primary.opacity(0.03) }
        if count == 0 { return Color.primary.opacity(0.07) }
        let ratio = Double(count) / Double(max)
        return Color.green.opacity(0.25 + 0.6 * ratio)
    }
}
