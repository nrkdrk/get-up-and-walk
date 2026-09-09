import SwiftUI
import AppKit

/// The app lives in the menu bar, so it launches as an accessory process with
/// no Dock icon. While it has a real window on screen it becomes a regular
/// app, so the window can be reached from the Dock and with cmd-tab, and drops
/// back to the menu bar when the last one closes.
enum DockPresence {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

final class DashboardController: NSObject, NSWindowDelegate {
    static let shared = DashboardController()
    private var window: NSWindow?

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        // Claim the Dock icon before the window exists, so it does not appear
        // and then have the activation policy changed underneath it.
        DockPresence.windowOpened()
        NSApp.activate(ignoringOtherApps: true)

        // No .fullSizeContentView: the dashboard scrolls, and content sliding
        // under the title bar and the traffic lights reads as a glitch.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = L.t("Kalk Yürü", "Get Up and Walk")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: DashboardView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DockPresence.windowClosed()
    }
}

/// One field of one reminder, drawn with its own reference line.
struct MeasurementChart: View {
    let field: FieldDef
    let points: [DataPoint]
    var color: Color = .blue
    var height: CGFloat = 150
    var forcedBounds: (min: Double, max: Double)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.displayLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            LineChart(
                series: [.init(name: field.label, color: color, points: points)],
                reference: field.chartReference,
                unit: field.chartUnit,
                height: height,
                forcedBounds: forcedBounds
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var reminders = ReminderStore.shared
    @ObservedObject private var presenter = EditorPresenter.shared

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        ScrollView {
            cards.padding(24)
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $presenter.editing) { def in
            ReminderEditor(def: def) { presenter.editing = nil }
        }
    }

    var cards: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            calfCircumferenceCard
            calfDifferenceCard

            HStack(alignment: .top, spacing: 16) {
                weightCard
                complianceCard
            }

            if showsVitals {
                vitalsCard
            }

            ForEach(chartableCustoms) { def in
                customCard(def)
            }

            remindersCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(greeting)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(L.t("Profil", "Profile")) {
                    OnboardingController.shared.show(firstRun: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 24) {
                Stat(value: "\(store.todayDone)",
                     label: L.t("bugün tamam", "done today"),
                     tint: .green)
                Stat(value: "\(store.todayMissed)",
                     label: L.t("kaçırıldı", "missed"),
                     tint: store.todayMissed > 0 ? .orange : .primary)
                Stat(value: "\(store.todaySnoozed)",
                     label: L.t("ertelendi", "snoozed"))
                Stat(value: "\(store.streak)",
                     label: L.t("gün üst üste", "day streak"),
                     tint: store.streak > 0 ? .green : .primary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if store.paused {
                        Text(L.t("Duraklatıldı", "Paused"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if let (def, date) = store.upNext {
                        Text(timeFormatter.string(from: date))
                            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                        Text(L.t("sıradaki: \(def.shortTitle)", "next: \(def.shortTitle)"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var greeting: String {
        let name = profiles.profile.displayName
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return L.t("Günaydın, \(name)", "Good morning, \(name)")
        case 12..<18: return L.t("İyi günler, \(name)", "Good afternoon, \(name)")
        default:      return L.t("İyi akşamlar, \(name)", "Good evening, \(name)")
        }
    }

    // MARK: Calf

    /// Left and right share a scale of their own; the difference between them
    /// is an order of magnitude smaller and gets its own card below.
    private var calfCircumferenceCard: some View {
        let s = store.calfSeries
        let note = s.left.isEmpty
            ? L.t("ölçüm bekleniyor", "awaiting measurement")
            : L.t("\(s.left.count) ölçüm", "\(s.left.count) measurements")

        return Card(title: L.t("Baldır çevresi", "Calf circumference"), note: note) {
            LineChart(
                series: [
                    .init(name: L.t("Sol", "Left"), color: .blue, points: s.left),
                    .init(name: L.t("Sağ", "Right"), color: .orange, points: s.right)
                ],
                unit: " cm",
                height: 180
            )
        }
    }

    private var calfDifferenceCard: some View {
        let diff = store.calfSeries.diff
        let note: String = {
            guard let d = diff.last else { return L.t("ölçüm bekleniyor", "awaiting measurement") }
            return String(format: L.t("son fark %.1f cm", "latest diff %.1f cm"), d.value)
        }()
        // Zero and the 3 cm line always stay in frame, so the gap between a
        // reading and the threshold is readable instead of a single pixel.
        let top = max(3.5, (diff.map { $0.value }.max() ?? 0) + 0.5)

        return Card(title: L.t("Sol-sağ farkı", "Left-right difference"), note: note) {
            LineChart(
                series: [.init(name: L.t("Fark", "Difference"),
                               color: .red.opacity(0.7), points: diff, dashed: true)],
                reference: (value: 3.0, label: L.t("3 cm — hekime danış", "3 cm — see a doctor")),
                unit: " cm",
                height: 150,
                forcedBounds: (min: 0, max: top)
            )
        }
    }

    // MARK: Weight, consistency, vitals

    private var weightCard: some View {
        let w = store.weightSeries
        let note: String = {
            guard w.count >= 2 else {
                if let bmi = profiles.profile.bmi {
                    return String(format: L.t("VKİ %.1f", "BMI %.1f"), bmi)
                }
                return ""
            }
            let delta = w[w.count - 1].value - w[0].value
            return String(format: L.t("%+.1f kg (başlangıçtan)", "%+.1f kg (since start)"), delta)
        }()

        return Card(title: L.t("Kilo", "Weight"), note: note) {
            LineChart(
                series: [.init(name: L.t("Kilo", "Weight"), color: .green, points: w)],
                unit: " kg",
                height: 140
            )
        }
    }

    private var complianceCard: some View {
        Card(title: L.t("Uyum", "Consistency"), note: L.t("son 12 hafta", "last 12 weeks")) {
            Heatmap(days: store.dailyDone(days: 84))
                .frame(height: 140, alignment: .top)
        }
    }

    private var showsVitals: Bool {
        [Kind.restingPulse, Kind.bloodOxygen].contains { kind in
            let def = kind.definition
            return store.enabled.contains(def.id) || store.hasData(def)
        }
    }

    private var vitalsCard: some View {
        let pulse = Kind.restingPulse.definition
        let oxygen = Kind.bloodOxygen.definition

        return Card(title: L.t("Nabız ve oksijen", "Pulse and oxygen"),
                    note: L.t("çizgiler yalnızca referans", "the lines are references only")) {
            HStack(alignment: .top, spacing: 16) {
                if let field = pulse.fields.first {
                    MeasurementChart(field: field,
                                     points: store.pulseSeries,
                                     color: pulse.tint)
                }
                if let field = oxygen.fields.first {
                    MeasurementChart(field: field,
                                     points: store.oxygenSeries,
                                     color: oxygen.tint,
                                     forcedBounds: (min: 88, max: 100))
                }
            }
        }
    }

    // MARK: User-defined measurements

    private var chartableCustoms: [ReminderDef] {
        reminders.custom.filter { !$0.fields.isEmpty && store.hasData($0) }
    }

    private func customCard(_ def: ReminderDef) -> some View {
        Card(title: def.title, note: def.schedule.describe) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(def.fields) { field in
                    MeasurementChart(field: field,
                                     points: store.points(def.id, field.key),
                                     color: def.tint)
                }
            }
        }
    }

    // MARK: Reminders

    private var remindersCard: some View {
        Card(title: L.t("Hatırlatıcılar", "Reminders")) {
            Button {
                presenter.create()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L.t("Yeni hatırlatıcı", "New reminder"))
        } content: {
            let all = reminders.all
            VStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { pair in
                    row(for: pair.element)
                    if pair.offset < all.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private func row(for def: ReminderDef) -> some View {
        let on = store.enabled.contains(def.id)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(def.tint.opacity(on ? 0.16 : 0.06))
                    .frame(width: 30, height: 30)
                Image(systemName: def.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(on ? def.tint : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(def.title).font(.system(size: 13, weight: .medium))
                Text(def.schedule.describe).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer()

            if on, let next = store.nextDue(def) {
                Text(timeFormatter.string(from: next))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 46, alignment: .trailing)
            }

            Text("\(store.todayCount(def.id, .done))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(store.todayCount(def.id, .done) > 0 ? .green : .secondary)
                .frame(width: 26, alignment: .trailing)

            Button {
                presenter.edit(def)
            } label: {
                Image(systemName: def.isBuiltIn ? "info.circle" : "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(def.isBuiltIn ? L.t("Ayrıntılar", "Details") : L.t("Düzenle", "Edit"))

            Button(L.t("Tetikle", "Trigger")) { store.fireNow(def) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Toggle("", isOn: Binding(
                get: { on },
                set: { v in
                    if v { store.enabled.insert(def.id) } else { store.enabled.remove(def.id) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}
