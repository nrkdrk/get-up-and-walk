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
    @Published private(set) var lastFired: [Kind: Date] = [:]
    @Published private(set) var snoozeUntil: [Kind: Date] = [:]

    @Published var enabled: Set<Kind> = [] { didSet { persistEnabled() } }
    @Published var paused = false
    @Published var activeStartHour = 8  { didSet { UserDefaults.standard.set(activeStartHour, forKey: "startHour") } }
    @Published var activeEndHour   = 23 { didSet { UserDefaults.standard.set(activeEndHour,   forKey: "endHour") } }

    private var tick: Timer?

    private let dir: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("GetUpAndWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Carry over the log written by builds before the 2.1 rename.
        let legacy = support.appendingPathComponent("KalkYuru/log.json")
        let current = base.appendingPathComponent("log.json")
        if FileManager.default.fileExists(atPath: legacy.path),
           !FileManager.default.fileExists(atPath: current.path) {
            try? FileManager.default.copyItem(at: legacy, to: current)
        }
        return base
    }()

    var logURL: URL { dir.appendingPathComponent("log.json") }

    private init() {
        let d = UserDefaults.standard
        activeStartHour = d.object(forKey: "startHour") as? Int ?? 8
        activeEndHour   = d.object(forKey: "endHour")   as? Int ?? 23

        if let saved = d.array(forKey: "enabledKinds") as? [String] {
            enabled = Set(saved.compactMap(Kind.init(rawValue:)))
        } else {
            enabled = []
        }

        loadLog()

        // Nothing is overdue at launch, so the user is not flooded on startup.
        let now = Date()
        for k in Kind.allCases { lastFired[k] = now }
    }

    /// Sets the initial reminder selection from the onboarding answer.
    func applyDefaults(varicose: VaricoseStatus) {
        enabled = Set(Kind.allCases.filter { $0.defaultEnabled(varicose: varicose) })
    }

    // MARK: Scheduling

    func start() {
        tick?.invalidate()
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
        for kind in Kind.allCases where enabled.contains(kind) {
            if let until = snoozeUntil[kind], until > now { continue }
            if kind.schedule.respectsActiveHours && !insideActiveHours(now) { continue }
            guard isDue(kind, now: now) else { continue }

            lastFired[kind] = now
            snoozeUntil[kind] = nil
            PanelController.shared.show(kind: kind)
            return   // one card at a time
        }
    }

    private func isDue(_ kind: Kind, now: Date) -> Bool {
        let cal = Calendar.current
        switch kind.schedule {
        case .interval(let minutes):
            guard let last = lastFired[kind] else { return true }
            return now.timeIntervalSince(last) >= Double(minutes * 60)

        case .daily(let h, let m):
            guard let occ = cal.nextDate(after: now,
                                         matching: DateComponents(hour: h, minute: m),
                                         matchingPolicy: .nextTime,
                                         direction: .backward) else { return false }
            return (lastFired[kind] ?? Date.distantPast) < occ

        case .weekly(let wd, let h, let m):
            guard let occ = cal.nextDate(after: now,
                                         matching: DateComponents(hour: h, minute: m, weekday: wd),
                                         matchingPolicy: .nextTime,
                                         direction: .backward) else { return false }
            return (lastFired[kind] ?? Date.distantPast) < occ
        }
    }

    func nextDue(_ kind: Kind) -> Date? {
        guard enabled.contains(kind), !paused else { return nil }
        let cal = Calendar.current
        let now = Date()
        if let until = snoozeUntil[kind], until > now { return until }

        switch kind.schedule {
        case .interval(let minutes):
            guard let last = lastFired[kind] else { return now }
            return last.addingTimeInterval(Double(minutes * 60))
        case .daily(let h, let m):
            return cal.nextDate(after: now, matching: DateComponents(hour: h, minute: m),
                                matchingPolicy: .nextTime)
        case .weekly(let wd, let h, let m):
            return cal.nextDate(after: now, matching: DateComponents(hour: h, minute: m, weekday: wd),
                                matchingPolicy: .nextTime)
        }
    }

    var upNext: (Kind, Date)? {
        let pairs: [(Kind, Date)] = Kind.allCases.compactMap { k in
            guard let d = nextDue(k) else { return nil }
            return (k, d)
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

    private var secondsIdle: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    // MARK: Recording

    func record(_ kind: Kind, _ outcome: Outcome, values: [String: Double]? = nil) {
        entries.append(LogEntry(date: Date(), kind: kind, outcome: outcome, values: values))
        saveLog()

        // A weigh-in also updates the stored profile weight.
        if kind == .weighIn, let w = values?["weight"] {
            ProfileStore.shared.profile.weightKg = w
        }
    }

    func snooze(_ kind: Kind, minutes: Int = 10) {
        snoozeUntil[kind] = Date().addingTimeInterval(Double(minutes * 60))
        record(kind, .snoozed)
    }

    func fireNow(_ kind: Kind) {
        lastFired[kind] = Date()
        PanelController.shared.show(kind: kind)
    }

    // MARK: Summaries

    private func todayCount(_ outcome: Outcome) -> Int {
        entries.filter { Calendar.current.isDateInToday($0.date) && $0.outcome == outcome }.count
    }
    var todayDone: Int { todayCount(.done) }
    var todayMissed: Int { todayCount(.missed) }
    var todaySnoozed: Int { todayCount(.snoozed) }

    func todayCount(_ kind: Kind, _ outcome: Outcome) -> Int {
        entries.filter {
            Calendar.current.isDateInToday($0.date) && $0.kind == kind && $0.outcome == outcome
        }.count
    }

    var calfSeries: (left: [DataPoint], right: [DataPoint], diff: [DataPoint]) {
        var l: [DataPoint] = [], r: [DataPoint] = [], d: [DataPoint] = []
        for e in entries where e.kind == .calfMeasurement && e.outcome == .done {
            guard let v = e.values,
                  let lv = v["calf_left"],
                  let rv = v["calf_right"] else { continue }
            l.append(DataPoint(date: e.date, value: lv))
            r.append(DataPoint(date: e.date, value: rv))
            d.append(DataPoint(date: e.date, value: abs(rv - lv)))
        }
        return (l, r, d)
    }

    var weightSeries: [DataPoint] {
        entries.compactMap { e in
            guard e.kind == .weighIn, e.outcome == .done,
                  let w = e.values?["weight"] else { return nil }
            return DataPoint(date: e.date, value: w)
        }
    }

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
        UserDefaults.standard.set(enabled.map { $0.rawValue }, forKey: "enabledKinds")
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

    @discardableResult
    func exportCSV() -> URL? {
        let df = ISO8601DateFormatter()
        var rows = ["date,kind,outcome,calf_left,calf_right,weight"]
        for e in entries {
            let v = e.values ?? [:]
            func num(_ key: String) -> String {
                if let d = v[key] { return String(format: "%.1f", d) }
                return ""
            }
            let row = [df.string(from: e.date), e.kind.rawValue, e.outcome.rawValue,
                       num("calf_left"), num("calf_right"), num("weight")]
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
