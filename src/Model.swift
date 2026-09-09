import SwiftUI
import Foundation

// MARK: - Language

enum Lang: String, Codable, CaseIterable, Identifiable {
    case tr, en
    var id: String { rawValue }

    var display: String {
        switch self {
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }

    var voiceCode: String {
        switch self {
        case .tr: return "tr-TR"
        case .en: return "en-US"
        }
    }

    var localeID: String {
        switch self {
        case .tr: return "tr_TR"
        case .en: return "en_US"
        }
    }
}

/// Bilingual string. Both variants live at the call site instead of a
/// separate strings file, so a translation can never go missing.
enum L {
    static var lang: Lang { ProfileStore.shared.profile.language }

    static func t(_ tr: String, _ en: String) -> String {
        lang == .tr ? tr : en
    }

    /// Picks between two stored slots of a user-editable definition.
    static func pick(_ tr: String, _ en: String) -> String {
        let chosen = lang == .tr ? tr : en
        return chosen.isEmpty ? (lang == .tr ? en : tr) : chosen
    }
}

// MARK: - Files

enum AppSupport {
    static let dir: URL = {
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

    static var logURL: URL { dir.appendingPathComponent("log.json") }
    static var customRemindersURL: URL { dir.appendingPathComponent("custom-reminders.json") }
}

// MARK: - Colour

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255)
    }
}

/// The eight colours a user can pick from, plus the shades the built-ins use.
enum Palette {
    static let blue   = "#0A84FF"
    static let green  = "#34C759"
    static let teal   = "#30B0C7"
    static let cyan   = "#32ADE6"
    static let indigo = "#5856D6"
    static let orange = "#FF9500"
    static let pink   = "#FF2D55"
    static let mint   = "#00C7BE"
    static let purple = "#AF52DE"

    static let choices = [blue, green, teal, cyan, indigo, orange, pink, purple]
}

// MARK: - Profile

enum VaricoseStatus: String, Codable, CaseIterable, Identifiable {
    case yes, no, unspecified
    var id: String { rawValue }

    var label: String {
        switch self {
        case .yes:         return L.t("Var", "Yes")
        case .no:          return L.t("Yok", "No")
        case .unspecified: return L.t("Belirtmiyorum", "Prefer not to say")
        }
    }
}

struct Profile: Codable {
    var firstName = ""
    var lastName = ""
    var heightCm: Double = 0
    var weightKg: Double = 0
    var varicose: VaricoseStatus = .unspecified
    var language: Lang = .tr
    var voiceEnabled = true
    var completed = false

    var displayName: String {
        firstName.isEmpty ? L.t("dostum", "friend") : firstName
    }

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Body mass index, or nil when height and weight are not both set.
    var bmi: Double? {
        guard heightCm > 50, weightKg > 20 else { return nil }
        let m = heightCm / 100
        return weightKg / (m * m)
    }
}

final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var profile: Profile {
        didSet { save() }
    }

    private let key = "profile"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let p = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = p
        } else {
            profile = Profile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Schedule

enum Schedule: Codable, Equatable {
    case interval(Int)                                  // minutes
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)   // 1 = Sunday

    /// Only interval reminders are limited to the active-hours window.
    var respectsActiveHours: Bool {
        if case .interval = self { return true }
        return false
    }

    static func weekdayName(_ weekday: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: L.lang.localeID)
        let index = min(max(weekday, 1), 7) - 1
        return cal.shortWeekdaySymbols[index]
    }

    var describe: String {
        switch self {
        case .interval(let m):
            if m % 60 == 0 && m >= 60 {
                return L.t("\(m / 60) saatte bir", "every \(m / 60)h")
            }
            return L.t("\(m) dakikada bir", "every \(m) min")
        case .daily(let h, let m):
            return L.t(String(format: "her gün %02d:%02d", h, m),
                       String(format: "daily %02d:%02d", h, m))
        case .weekly(let wd, let h, let m):
            return String(format: "%@ %02d:%02d", Schedule.weekdayName(wd), h, m)
        }
    }
}

// MARK: - Reminder definition

/// One number a reminder collects. `key` is the column name in the CSV export
/// and the key inside `LogEntry.values`, so it must stay stable once used.
struct FieldDef: Identifiable, Codable {
    let key: String
    var labelTR: String
    var labelEN: String
    var unit: String
    var referenceValue: Double? = nil
    var referenceLabelTR: String? = nil
    var referenceLabelEN: String? = nil

    var id: String { key }

    var label: String { L.pick(labelTR, labelEN) }

    /// Label as shown next to the input box and above a chart.
    var displayLabel: String { unit.isEmpty ? label : "\(label) (\(unit))" }

    /// Unit suffix for chart legends: "%" hugs the number, words get a space.
    var chartUnit: String {
        if unit.isEmpty { return "" }
        return unit == "%" ? "%" : " \(unit)"
    }

    /// A fresh row in the editor. `key` is a placeholder until the reminder is
    /// saved and the column name is derived from the label.
    static func blank() -> FieldDef {
        FieldDef(key: "new.\(UUID().uuidString)", labelTR: "", labelEN: "", unit: "")
    }

    var chartReference: (value: Double, label: String)? {
        guard let value = referenceValue else { return nil }
        let tr = referenceLabelTR ?? ""
        let en = referenceLabelEN ?? ""
        let text = L.pick(tr, en)
        return (value, text.isEmpty ? String(format: "%g", value) : text)
    }
}

/// Everything the app needs to know about a reminder, whether it ships with
/// the app or the user wrote it. Nothing downstream switches on `Kind`.
struct ReminderDef: Identifiable, Codable {
    let id: String               // "builtin.move" or "custom.<uuid>"
    var titleTR: String
    var titleEN: String
    var subtitleTR: String
    var subtitleEN: String
    var spokenTR: String         // "%@" is replaced with the user's first name
    var spokenEN: String
    var iconName: String         // SF Symbol
    var tintHex: String
    var soundName: String
    var schedule: Schedule
    var fields: [FieldDef]       // empty for a simple acknowledge
    var isBuiltIn: Bool

    var title: String { L.pick(titleTR, titleEN) }
    var subtitle: String { L.pick(subtitleTR, subtitleEN) }
    var tint: Color { Color(hex: tintHex) }

    /// Short label for tight spots; built-ins carry their own, custom ones
    /// fall back to the full title.
    var shortTitle: String {
        Kind(builtInID: id)?.shortTitle ?? title
    }

    func spoken(name: String) -> String {
        L.pick(spokenTR, spokenEN).replacingOccurrences(of: "%@", with: name)
    }

    /// Reminders that ask for a number never auto-close and do take focus.
    var autoCloseSeconds: Int? { fields.isEmpty ? 20 : nil }
    var snoozable: Bool { fields.isEmpty }

    static let builtInPrefix = "builtin."
    static let customPrefix = "custom."

    static func newCustomID() -> String { customPrefix + UUID().uuidString }

    /// Maps anything that has ever been written into a log onto a current id:
    /// pre-2.1 Turkish raw values, the 2.1 English ones, and ids themselves.
    static func canonicalID(_ raw: String) -> String {
        if raw.hasPrefix(builtInPrefix) || raw.hasPrefix(customPrefix) { return raw }
        if let kind = Kind(rawValue: raw) ?? Kind.legacyNames[raw] { return kind.definition.id }
        return raw
    }

    /// A blank definition for the editor to fill in.
    static func newCustom() -> ReminderDef {
        ReminderDef(id: newCustomID(),
                    titleTR: "", titleEN: "",
                    subtitleTR: "", subtitleEN: "",
                    spokenTR: "", spokenEN: "",
                    iconName: "bell",
                    tintHex: Palette.blue,
                    soundName: "Glass",
                    schedule: .interval(60),
                    fields: [],
                    isBuiltIn: false)
    }
}

// MARK: - Built-in reminders

enum Kind: String, CaseIterable, Identifiable {
    case move
    case anklePumps
    case eyeBreak
    case water
    case compressionSocks
    case legsUp
    case calfMeasurement
    case weighIn
    case restingPulse
    case bloodOxygen

    var id: String { rawValue }

    /// Raw values used before the 2.1 rename, so existing logs still decode.
    static let legacyNames: [String: Kind] = [
        "hareket": .move,
        "ayakBilegi": .anklePumps,
        "goz": .eyeBreak,
        "su": .water,
        "corap": .compressionSocks,
        "bacakYukari": .legsUp,
        "olcumBaldir": .calfMeasurement,
        "olcumKilo": .weighIn
    ]

    init?(builtInID: String) {
        guard builtInID.hasPrefix(ReminderDef.builtInPrefix) else { return nil }
        self.init(rawValue: String(builtInID.dropFirst(ReminderDef.builtInPrefix.count)))
    }

    var definition: ReminderDef {
        ReminderDef(id: ReminderDef.builtInPrefix + rawValue,
                    titleTR: titles.tr, titleEN: titles.en,
                    subtitleTR: subtitles.tr, subtitleEN: subtitles.en,
                    spokenTR: spokenTemplates.tr, spokenEN: spokenTemplates.en,
                    iconName: icon,
                    tintHex: tintHex,
                    soundName: sound,
                    schedule: schedule,
                    fields: fields,
                    isBuiltIn: true)
    }

    private var titles: (tr: String, en: String) {
        switch self {
        case .move:             return ("Hareket zamanı", "Time to move")
        case .anklePumps:       return ("Ayak bileği pompası", "Ankle pumps")
        case .eyeBreak:         return ("Göz molası", "Eye break")
        case .water:            return ("Su iç", "Drink water")
        case .compressionSocks: return ("Kompresyon çorabı", "Compression socks")
        case .legsUp:           return ("Bacakları yukarı", "Legs up")
        case .calfMeasurement:  return ("Haftalık baldır ölçümü", "Weekly calf measurement")
        case .weighIn:          return ("Haftalık tartı", "Weekly weigh-in")
        case .restingPulse:     return ("Dinlenme nabzı", "Resting pulse")
        case .bloodOxygen:      return ("Kan oksijeni", "Blood oxygen")
        }
    }

    var shortTitle: String {
        switch self {
        case .move:             return L.t("Hareket", "Move")
        case .anklePumps:       return L.t("Ayak bileği", "Ankles")
        case .eyeBreak:         return L.t("Göz", "Eyes")
        case .water:            return L.t("Su", "Water")
        case .compressionSocks: return L.t("Çorap", "Socks")
        case .legsUp:           return L.t("Bacak yukarı", "Legs up")
        case .calfMeasurement:  return L.t("Baldır", "Calf")
        case .weighIn:          return L.t("Tartı", "Weight")
        case .restingPulse:     return L.t("Nabız", "Pulse")
        case .bloodOxygen:      return L.t("Oksijen", "Oxygen")
        }
    }

    private var subtitles: (tr: String, en: String) {
        switch self {
        case .move:
            return ("Kalk, 2-3 dakika yürü", "Stand up, walk 2-3 minutes")
        case .anklePumps:
            return ("Ayakları öne-arkaya 20 kez esnet", "Flex your feet 20 times")
        case .eyeBreak:
            return ("20 saniye uzağa bak", "Look 20 feet away for 20 seconds")
        case .water:
            return ("Bir bardak su", "One glass of water")
        case .compressionSocks:
            return ("Kalkmadan önce giy", "Put them on before getting up")
        case .legsUp:
            return ("15 dakika kalp seviyesinin üstünde", "15 minutes above heart level")
        case .calfMeasurement:
            return ("Diz kapağının 10 cm altından ölç", "Measure 10 cm below the kneecap")
        case .weighIn:
            return ("Aç karnına, aynı saatte", "Empty stomach, same time")
        case .restingPulse:
            return ("Yataktan kalkmadan, 5 dakika dinlendikten sonra",
                    "Before getting up, after five minutes at rest")
        case .bloodOxygen:
            return ("Parmak ucundan, el sıcak ve hareketsizken",
                    "Fingertip, hand warm and still")
        }
    }

    /// Sentence spoken aloud; "%@" stands in for the user's first name.
    private var spokenTemplates: (tr: String, en: String) {
        switch self {
        case .move:
            return ("%@, kalkıp yürümen lazım.", "%@, you need to stand up and walk.")
        case .anklePumps:
            return ("%@, ayak bileklerini çalıştır.", "%@, pump your ankles.")
        case .eyeBreak:
            return ("%@, gözlerini dinlendir.", "%@, rest your eyes.")
        case .water:
            return ("%@, su içmeyi unutma.", "%@, drink some water.")
        case .compressionSocks:
            return ("%@, kompresyon çorabını giy.", "%@, put on your compression socks.")
        case .legsUp:
            return ("%@, bacaklarını yukarı kaldır.", "%@, put your legs up.")
        case .calfMeasurement:
            return ("%@, baldır ölçümü zamanı.", "%@, time for your calf measurement.")
        case .weighIn:
            return ("%@, tartılma zamanı.", "%@, time to weigh in.")
        case .restingPulse:
            return ("%@, nabzını ölçme zamanı.", "%@, time to measure your pulse.")
        case .bloodOxygen:
            return ("%@, kan oksijenini ölçme zamanı.", "%@, time to measure your blood oxygen.")
        }
    }

    private var icon: String {
        switch self {
        case .move:             return "figure.walk"
        case .anklePumps:       return "shoe"
        case .eyeBreak:         return "eye"
        case .water:            return "drop"
        case .compressionSocks: return "bandage"
        case .legsUp:           return "bed.double"
        case .calfMeasurement:  return "ruler"
        case .weighIn:          return "scalemass"
        case .restingPulse:     return "heart"
        case .bloodOxygen:      return "lungs"
        }
    }

    private var tintHex: String {
        switch self {
        case .move, .anklePumps:            return Palette.green
        case .eyeBreak:                     return Palette.teal
        case .water:                        return Palette.cyan
        case .compressionSocks, .legsUp:    return Palette.indigo
        case .calfMeasurement, .weighIn:    return Palette.orange
        case .restingPulse:                 return Palette.pink
        case .bloodOxygen:                  return Palette.mint
        }
    }

    private var sound: String {
        switch self {
        case .eyeBreak, .anklePumps:
            return "Tink"
        case .calfMeasurement, .weighIn, .compressionSocks, .restingPulse, .bloodOxygen:
            return "Ping"
        default:
            return "Glass"
        }
    }

    private var fields: [FieldDef] {
        switch self {
        case .calfMeasurement:
            return [
                FieldDef(key: "calf_left",  labelTR: "Sol baldır", labelEN: "Left calf",  unit: "cm"),
                FieldDef(key: "calf_right", labelTR: "Sağ baldır", labelEN: "Right calf", unit: "cm")
            ]
        case .weighIn:
            return [FieldDef(key: "weight", labelTR: "Kilo", labelEN: "Weight", unit: "kg")]
        case .restingPulse:
            return [FieldDef(key: "pulse_bpm", labelTR: "Nabız", labelEN: "Pulse", unit: "bpm",
                             referenceValue: 100,
                             referenceLabelTR: "100 — üst sınır",
                             referenceLabelEN: "100 — upper limit")]
        case .bloodOxygen:
            return [FieldDef(key: "spo2_pct", labelTR: "SpO₂", labelEN: "SpO₂", unit: "%",
                             referenceValue: 94,
                             referenceLabelTR: "94 — alt sınır",
                             referenceLabelEN: "94 — lower limit")]
        default:
            return []
        }
    }

    private var schedule: Schedule {
        switch self {
        case .move:             return .interval(60)
        case .anklePumps:       return .interval(30)
        case .eyeBreak:         return .interval(20)
        case .water:            return .interval(120)
        case .compressionSocks: return .daily(hour: 7, minute: 45)
        case .legsUp:           return .daily(hour: 21, minute: 30)
        case .weighIn:          return .weekly(weekday: 1, hour: 8, minute: 30)
        case .calfMeasurement:  return .weekly(weekday: 1, hour: 9, minute: 0)
        case .restingPulse:     return .daily(hour: 8, minute: 0)
        case .bloodOxygen:      return .daily(hour: 8, minute: 5)
        }
    }

    func defaultEnabled(varicose: VaricoseStatus) -> Bool {
        switch self {
        case .eyeBreak, .restingPulse, .bloodOxygen:
            return false
        case .anklePumps:
            return varicose == .yes
        case .compressionSocks, .legsUp, .calfMeasurement:
            return varicose != .no
        default:
            return true
        }
    }
}

// MARK: - Log

enum Outcome: String, Codable {
    case done       // the user acknowledged
    case missed     // the card timed out
    case snoozed
}

struct LogEntry: Codable {
    let date: Date
    let reminderID: String
    let outcome: Outcome
    var values: [String: Double]? = nil

    init(date: Date, reminderID: String, outcome: Outcome, values: [String: Double]? = nil) {
        self.date = date
        self.reminderID = reminderID
        self.outcome = outcome
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case date, reminderID, kind, outcome, values
    }

    /// The earliest builds keyed measurements by the label shown next to the
    /// input box, which differs per language. Both languages map onto the
    /// field keys in use now, so old measurements still chart and export.
    private static let legacyValueKeys: [String: String] = [
        "Sol baldır (cm)": "calf_left",   "Left calf (cm)":  "calf_left",
        "Sağ baldır (cm)": "calf_right",  "Right calf (cm)": "calf_right",
        "Kilo (kg)":       "weight",      "Weight (kg)":     "weight"
    ]

    /// Entries written before 3.0 carry a "kind" holding either a pre-2.1
    /// Turkish raw value or the 2.1 English one; both map onto a built-in id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        outcome = try c.decode(Outcome.self, forKey: .outcome)

        values = try c.decodeIfPresent([String: Double].self, forKey: .values).map { raw in
            var out: [String: Double] = [:]
            for (key, value) in raw {
                out[LogEntry.legacyValueKeys[key] ?? key] = value
            }
            return out
        }

        let raw = try c.decodeIfPresent(String.self, forKey: .reminderID)
            ?? c.decode(String.self, forKey: .kind)
        reminderID = ReminderDef.canonicalID(raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(reminderID, forKey: .reminderID)
        try c.encode(outcome, forKey: .outcome)
        try c.encodeIfPresent(values, forKey: .values)
    }
}

struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
