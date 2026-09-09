import SwiftUI

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
}

/// Bilingual string. Both variants live at the call site instead of a
/// separate strings file, so a translation can never go missing.
enum L {
    static var lang: Lang { ProfileStore.shared.profile.language }

    static func t(_ tr: String, _ en: String) -> String {
        lang == .tr ? tr : en
    }
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

// MARK: - Reminder kinds

enum Kind: String, Codable, CaseIterable, Identifiable {
    case move
    case anklePumps
    case eyeBreak
    case water
    case compressionSocks
    case legsUp
    case calfMeasurement
    case weighIn

    var id: String { rawValue }

    /// Raw values used before the 2.1 rename, so existing logs still decode.
    private static let legacyNames: [String: Kind] = [
        "hareket": .move,
        "ayakBilegi": .anklePumps,
        "goz": .eyeBreak,
        "su": .water,
        "corap": .compressionSocks,
        "bacakYukari": .legsUp,
        "olcumBaldir": .calfMeasurement,
        "olcumKilo": .weighIn
    ]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Kind(rawValue: raw) ?? Kind.legacyNames[raw] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown kind: \(raw)")
            )
        }
        self = kind
    }

    var title: String {
        switch self {
        case .move:             return L.t("Hareket zamanı", "Time to move")
        case .anklePumps:       return L.t("Ayak bileği pompası", "Ankle pumps")
        case .eyeBreak:         return L.t("Göz molası", "Eye break")
        case .water:            return L.t("Su iç", "Drink water")
        case .compressionSocks: return L.t("Kompresyon çorabı", "Compression socks")
        case .legsUp:           return L.t("Bacakları yukarı", "Legs up")
        case .calfMeasurement:  return L.t("Haftalık baldır ölçümü", "Weekly calf measurement")
        case .weighIn:          return L.t("Haftalık tartı", "Weekly weigh-in")
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
        }
    }

    var subtitle: String {
        switch self {
        case .move:             return L.t("Kalk, 2-3 dakika yürü", "Stand up, walk 2-3 minutes")
        case .anklePumps:       return L.t("Ayakları öne-arkaya 20 kez esnet", "Flex your feet 20 times")
        case .eyeBreak:         return L.t("20 saniye uzağa bak", "Look 20 feet away for 20 seconds")
        case .water:            return L.t("Bir bardak su", "One glass of water")
        case .compressionSocks: return L.t("Kalkmadan önce giy", "Put them on before getting up")
        case .legsUp:           return L.t("15 dakika kalp seviyesinin üstünde", "15 minutes above heart level")
        case .calfMeasurement:  return L.t("Diz kapağının 10 cm altından ölç", "Measure 10 cm below the kneecap")
        case .weighIn:          return L.t("Aç karnına, aynı saatte", "Empty stomach, same time")
        }
    }

    /// Sentence spoken aloud, addressed to the user by name.
    func spoken(name: String) -> String {
        switch self {
        case .move:
            return L.t("\(name), kalkıp yürümen lazım.", "\(name), you need to stand up and walk.")
        case .anklePumps:
            return L.t("\(name), ayak bileklerini çalıştır.", "\(name), pump your ankles.")
        case .eyeBreak:
            return L.t("\(name), gözlerini dinlendir.", "\(name), rest your eyes.")
        case .water:
            return L.t("\(name), su içmeyi unutma.", "\(name), drink some water.")
        case .compressionSocks:
            return L.t("\(name), kompresyon çorabını giy.", "\(name), put on your compression socks.")
        case .legsUp:
            return L.t("\(name), bacaklarını yukarı kaldır.", "\(name), put your legs up.")
        case .calfMeasurement:
            return L.t("\(name), baldır ölçümü zamanı.", "\(name), time for your calf measurement.")
        case .weighIn:
            return L.t("\(name), tartılma zamanı.", "\(name), time to weigh in.")
        }
    }

    var icon: String {
        switch self {
        case .move:             return "figure.walk"
        case .anklePumps:       return "shoe"
        case .eyeBreak:         return "eye"
        case .water:            return "drop"
        case .compressionSocks: return "bandage"
        case .legsUp:           return "bed.double"
        case .calfMeasurement:  return "ruler"
        case .weighIn:          return "scalemass"
        }
    }

    var tint: Color {
        switch self {
        case .move, .anklePumps:                return .green
        case .eyeBreak:                         return .teal
        case .water:                            return .cyan
        case .compressionSocks, .legsUp:        return .indigo
        case .calfMeasurement, .weighIn:        return .orange
        }
    }

    var sound: String {
        switch self {
        case .eyeBreak, .anklePumps:                            return "Tink"
        case .calfMeasurement, .weighIn, .compressionSocks:     return "Ping"
        default:                                                return "Glass"
        }
    }

    /// Kinds that ask for a number never auto-close and do take keyboard focus.
    var inputFields: [InputField] {
        switch self {
        case .calfMeasurement:
            return [
                InputField(key: "calf_left",  label: L.t("Sol baldır (cm)", "Left calf (cm)")),
                InputField(key: "calf_right", label: L.t("Sağ baldır (cm)", "Right calf (cm)"))
            ]
        case .weighIn:
            return [InputField(key: "weight", label: L.t("Kilo (kg)", "Weight (kg)"))]
        default:
            return []
        }
    }

    var autoCloseSeconds: Int? { inputFields.isEmpty ? 20 : nil }

    var snoozable: Bool { inputFields.isEmpty }

    var schedule: Schedule {
        switch self {
        case .move:             return .interval(60)
        case .anklePumps:       return .interval(30)
        case .eyeBreak:         return .interval(20)
        case .water:            return .interval(120)
        case .compressionSocks: return .daily(hour: 7, minute: 45)
        case .legsUp:           return .daily(hour: 21, minute: 30)
        case .weighIn:          return .weekly(weekday: 1, hour: 8, minute: 30)
        case .calfMeasurement:  return .weekly(weekday: 1, hour: 9, minute: 0)
        }
    }

    /// Directly related to leg circulation.
    var isVenous: Bool {
        switch self {
        case .compressionSocks, .legsUp, .calfMeasurement, .anklePumps: return true
        default: return false
        }
    }

    func defaultEnabled(varicose: VaricoseStatus) -> Bool {
        switch self {
        case .eyeBreak:
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

struct InputField: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

enum Schedule {
    case interval(Int)                                  // minutes
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)   // 1 = Sunday

    /// Only interval reminders are limited to the active-hours window.
    var respectsActiveHours: Bool {
        if case .interval = self { return true }
        return false
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
        case .weekly(_, let h, let m):
            return L.t(String(format: "pazar %02d:%02d", h, m),
                       String(format: "Sun %02d:%02d", h, m))
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
    let kind: Kind
    let outcome: Outcome
    var values: [String: Double]? = nil
}

struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
