import SwiftUI
import AppKit
import CoreGraphics
import AVFoundation

// MARK: - Speech

final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        let p = ProfileStore.shared.profile
        guard p.voiceEnabled, !text.isEmpty else { return }

        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: p.language.voiceCode)
        u.rate = 0.48
        u.preUtteranceDelay = 0.1
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var lastFired: [String: Date] = [:]
    @Published private(set) var snoozeUntil: [String: Date] = [:]

    @Published var enabled: Set<String> = [] { didSet { persistEnabled() } }
    @Published var paused = false
    @Published var activeStartHour = 8  { didSet { UserDefaults.standard.set(activeStartHour, forKey: "startHour") } }
    @Published var activeEndHour   = 23 { didSet { UserDefaults.standard.set(activeEndHour,   forKey: "endHour") } }

    private var tick: Timer?
    /// Keeps App Nap from throttling the tick while no window is on screen,
    /// which is exactly when a reminder app is meant to be working.
    private var activity: NSObjectProtocol?

    private let enabledKey = "enabledReminders"

    var logURL: URL { AppSupport.logURL }

    private init() {
        let d = UserDefaults.standard
        activeStartHour = d.object(forKey: "startHour") as? Int ?? 8
        activeEndHour   = d.object(forKey: "endHour")   as? Int ?? 23

        if let saved = d.array(forKey: enabledKey) as? [String] {
            enabled = Set(saved)
        } else if let legacy = d.array(forKey: "enabledKinds") as? [String] {
            // Selections stored by builds that keyed on the Kind raw value.
            enabled = Set(legacy.map(ReminderDef.canonicalID))
            persistEnabled()
        } else {
            enabled = []
        }

        loadLog()

        // Nothing is overdue at launch, so the user is not flooded on startup.
        let now = Date()
        for def in ReminderStore.shared.all { lastFired[def.id] = now }
    }

    /// Sets the initial reminder selection from the onboarding answer.
    func applyDefaults(varicose: VaricoseStatus) {
        enabled = Set(Kind.allCases
            .filter { $0.defaultEnabled(varicose: varicose) }
            .map { $0.definition.id })
    }

    /// Drops the scheduling state of a reminder the user deleted.
    func forget(_ id: String) {
        enabled.remove(id)
        lastFired[id] = nil
        snoozeUntil[id] = nil
    }

    // MARK: Scheduling

    func start() {
        tick?.invalidate()
        if activity == nil {
            // Allows idle system sleep: reminders should not keep the Mac awake.
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Reminders fire on a schedule")
        }
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    private func evaluate() {
        guard ProfileStore.shared.profile.completed else { return }
        guard !paused else { return }
        guard PanelController.shared.isIdle else { return }
        guard !screenIsLocked else { return }
        guard secondsIdle < 600 else { return }   // already away from the desk

        let now = Date()
        for def in ReminderStore.shared.all where enabled.contains(def.id) {
            if let until = snoozeUntil[def.id], until > now { continue }
            if def.schedule.respectsActiveHours && !insideActiveHours(now) { continue }
            guard isDue(def, now: now) else { continue }

            lastFired[def.id] = now
            snoozeUntil[def.id] = nil
            PanelController.shared.show(def: def, automatic: true)
            return   // one card at a time
        }
    }

    private func isDue(_ def: ReminderDef, now: Date) -> Bool {
        let cal = Calendar.current
        switch def.schedule {
        case .interval(let minutes):
            guard let last = lastFired[def.id] else { return true }
            return now.timeIntervalSince(last) >= Double(minutes * 60)

        case .daily(let h, let m):
            guard let occ = cal.nextDate(after: now,
                                         matching: DateComponents(hour: h, minute: m),
                                         matchingPolicy: .nextTime,
                                         direction: .backward) else { return false }
            return (lastFired[def.id] ?? Date.distantPast) < occ

        case .weekly(let wd, let h, let m):
            guard let occ = cal.nextDate(after: now,
                                         matching: DateComponents(hour: h, minute: m, weekday: wd),
                                         matchingPolicy: .nextTime,
                                         direction: .backward) else { return false }
            return (lastFired[def.id] ?? Date.distantPast) < occ
        }
    }

    func nextDue(_ def: ReminderDef) -> Date? {
        guard enabled.contains(def.id), !paused else { return nil }
        let cal = Calendar.current
        let now = Date()
        if let until = snoozeUntil[def.id], until > now { return until }

        switch def.schedule {
        case .interval(let minutes):
            guard let last = lastFired[def.id] else { return now }
            return last.addingTimeInterval(Double(minutes * 60))
        case .daily(let h, let m):
            return cal.nextDate(after: now, matching: DateComponents(hour: h, minute: m),
                                matchingPolicy: .nextTime)
        case .weekly(let wd, let h, let m):
            return cal.nextDate(after: now, matching: DateComponents(hour: h, minute: m, weekday: wd),
                                matchingPolicy: .nextTime)
        }
    }

    var upNext: (ReminderDef, Date)? {
        let pairs: [(ReminderDef, Date)] = ReminderStore.shared.all.compactMap { def in
            guard let d = nextDue(def) else { return nil }
            return (def, d)
        }
        return pairs.min { $0.1 < $1.1 }
    }

    private func insideActiveHours(_ date: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return h >= activeStartHour && h < activeEndHour
    }

    // MARK: System state

    private var screenIsLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// Any keyboard, mouse or tablet input (kCGAnyInputEventType). `.null` is
    /// an event type of its own, not a wildcard: on an active desk it reported
    /// hours of idleness, so every tick treated the user as away and returned.
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    private var secondsIdle: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Store.anyInputEvent)
    }

    // MARK: Recording

    func record(_ id: String, _ outcome: Outcome, values: [String: Double]? = nil) {
        entries.append(LogEntry(date: Date(), reminderID: id, outcome: outcome, values: values))
        saveLog()

        // A weigh-in also updates the stored profile weight.
        if id == Kind.weighIn.definition.id, let w = values?["weight"] {
            ProfileStore.shared.profile.weightKg = w
        }
    }

    func snooze(_ id: String, minutes: Int = 10) {
        snoozeUntil[id] = Date().addingTimeInterval(Double(minutes * 60))
        record(id, .snoozed)
    }

    func fireNow(_ def: ReminderDef) {
        lastFired[def.id] = Date()
        PanelController.shared.show(def: def)
    }

    // MARK: Summaries

    private func todayCount(_ outcome: Outcome) -> Int {
        entries.filter { Calendar.current.isDateInToday($0.date) && $0.outcome == outcome }.count
    }
    var todayDone: Int { todayCount(.done) }
    var todayMissed: Int { todayCount(.missed) }
    var todaySnoozed: Int { todayCount(.snoozed) }

    func todayCount(_ id: String, _ outcome: Outcome) -> Int {
        entries.filter {
            Calendar.current.isDateInToday($0.date) && $0.reminderID == id && $0.outcome == outcome
        }.count
    }

    /// Every recorded value of one field of one reminder, oldest first.
    func points(_ id: String, _ key: String) -> [DataPoint] {
        entries.compactMap { e in
            guard e.reminderID == id, e.outcome == .done,
                  let v = e.values?[key] else { return nil }
            return DataPoint(date: e.date, value: v)
        }
    }

    func hasData(_ def: ReminderDef) -> Bool {
        def.fields.contains { !points(def.id, $0.key).isEmpty }
    }

    var calfSeries: (left: [DataPoint], right: [DataPoint], diff: [DataPoint]) {
        let id = Kind.calfMeasurement.definition.id
        var l: [DataPoint] = [], r: [DataPoint] = [], d: [DataPoint] = []
        for e in entries where e.reminderID == id && e.outcome == .done {
            guard let v = e.values,
                  let lv = v["calf_left"],
                  let rv = v["calf_right"] else { continue }
            l.append(DataPoint(date: e.date, value: lv))
            r.append(DataPoint(date: e.date, value: rv))
            d.append(DataPoint(date: e.date, value: abs(rv - lv)))
        }
        return (l, r, d)
    }

    var weightSeries: [DataPoint] { points(Kind.weighIn.definition.id, "weight") }
    var pulseSeries: [DataPoint] { points(Kind.restingPulse.definition.id, "pulse_bpm") }
    var oxygenSeries: [DataPoint] { points(Kind.bloodOxygen.definition.id, "spo2_pct") }

    func dailyDone(days: Int) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(Date, Int)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let n = entries.filter {
                $0.outcome == .done && cal.isDate($0.date, inSameDayAs: day)
            }.count
            out.append((day, n))
        }
        return out
    }

    /// Consecutive days with at least one completed reminder.
    var streak: Int {
        let cal = Calendar.current
        var count = 0
        var day = cal.startOfDay(for: Date())
        while true {
            let has = entries.contains { $0.outcome == .done && cal.isDate($0.date, inSameDayAs: day) }
            if has {
                count += 1
            } else if !cal.isDateInToday(day) {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            if count > 400 { break }
        }
        return count
    }

    var lastCalfSummary: String? {
        let s = calfSeries
        guard let l = s.left.last, let r = s.right.last else { return nil }
        return String(format: L.t("Baldır: sol %.1f · sağ %.1f · fark %.1f",
                                  "Calf: L %.1f · R %.1f · diff %.1f"),
                      l.value, r.value, abs(r.value - l.value))
    }

    var lastWeightSummary: String? {
        guard let w = weightSeries.last else { return nil }
        return String(format: L.t("Kilo: %.1f kg", "Weight: %.1f kg"), w.value)
    }

    // MARK: Persistence

    private func persistEnabled() {
        UserDefaults.standard.set(Array(enabled), forKey: enabledKey)
    }

    private func saveLog() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(entries) { try? data.write(to: logURL, options: .atomic) }
    }

    private func loadLog() {
        guard let data = try? Data(contentsOf: logURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        entries = (try? dec.decode([LogEntry].self, from: data)) ?? []
    }

    /// One column per measurement key that appears anywhere in the log, so
    /// user-defined measurements are exported alongside the built-in ones.
    @discardableResult
    func exportCSV() -> URL? {
        let df = ISO8601DateFormatter()
        let keys = Set(entries.flatMap { ($0.values ?? [:]).keys }).sorted()

        var rows = [(["date", "reminder", "outcome"] + keys).joined(separator: ",")]
        for e in entries {
            let v = e.values ?? [:]
            let numbers = keys.map { key -> String in
                guard let d = v[key] else { return "" }
                return String(format: "%.1f", d)
            }
            let row = [df.string(from: e.date), e.reminderID, e.outcome.rawValue] + numbers
            rows.append(row.joined(separator: ","))
        }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("getupandwalk-\(stamp.string(from: Date())).csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
