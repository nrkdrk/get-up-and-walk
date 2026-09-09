import SwiftUI
import AppKit

final class DashboardController: NSObject, NSWindowDelegate {
    static let shared = DashboardController()
    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
    }
}

struct DashboardView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var profiles = ProfileStore.shared

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                calfCard

                HStack(alignment: .top, spacing: 16) {
                    weightCard
                    complianceCard
                }

                remindersCard
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    } else if let (kind, date) = store.upNext {
                        Text(timeFormatter.string(from: date))
                            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                        Text(L.t("sıradaki: \(kind.shortTitle)", "next: \(kind.shortTitle)"))
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

    private var calfCard: some View {
        let s = store.calfSeries
        let note: String = {
            guard let d = s.diff.last else { return L.t("ölçüm bekleniyor", "awaiting measurement") }
            return String(format: L.t("son fark %.1f cm", "latest diff %.1f cm"), d.value)
        }()

        return Card(title: L.t("Baldır çevresi", "Calf circumference"), note: note) {
            LineChart(
                series: [
                    .init(name: L.t("Sol", "Left"), color: .blue, points: s.left),
                    .init(name: L.t("Sağ", "Right"), color: .orange, points: s.right),
                    .init(name: L.t("Fark", "Difference"), color: .red.opacity(0.7),
                          points: s.diff, dashed: true)
                ],
                reference: (value: 3.0, label: L.t("3 cm — hekime danış", "3 cm — see a doctor")),
                unit: " cm",
                height: 210
            )
        }
    }

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

    private var remindersCard: some View {
        Card(title: L.t("Hatırlatıcılar", "Reminders")) {
            VStack(spacing: 0) {
                ForEach(Kind.allCases) { kind in
                    row(for: kind)
                    if kind != Kind.allCases.last {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private func row(for kind: Kind) -> some View {
        let on = store.enabled.contains(kind)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(kind.tint.opacity(on ? 0.16 : 0.06))
                    .frame(width: 30, height: 30)
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(on ? kind.tint : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text(kind.schedule.describe).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer()

            if on, let next = store.nextDue(kind) {
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

            Text("\(store.todayCount(kind, .done))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(store.todayCount(kind, .done) > 0 ? .green : .secondary)
                .frame(width: 26, alignment: .trailing)

            Button(L.t("Tetikle", "Trigger")) { store.fireNow(kind) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Toggle("", isOn: Binding(
                get: { on },
                set: { v in
                    if v { store.enabled.insert(kind) } else { store.enabled.remove(kind) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}
