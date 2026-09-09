import SwiftUI

/// Owns every reminder definition the app knows about: the built-ins compiled
/// into `Kind`, plus whatever the user has written, persisted as JSON next to
/// the log. Everything else in the app reads definitions from here.
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published private(set) var custom: [ReminderDef] = []

    private init() {
        load()
    }

    var builtIns: [ReminderDef] { Kind.allCases.map { $0.definition } }

    var all: [ReminderDef] { builtIns + custom }

    func definition(for id: String) -> ReminderDef? {
        all.first { $0.id == id }
    }

    /// Inserts a new custom definition or replaces the one with the same id.
    func upsert(_ def: ReminderDef) {
        guard !def.isBuiltIn else { return }
        if let i = custom.firstIndex(where: { $0.id == def.id }) {
            custom[i] = def
        } else {
            custom.append(def)
        }
        save()
    }

    /// Removes the definition. Entries already logged against it stay in the
    /// log file untouched.
    func delete(_ def: ReminderDef) {
        guard !def.isBuiltIn else { return }
        custom.removeAll { $0.id == def.id }
        Store.shared.forget(def.id)
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppSupport.customRemindersURL) else { return }
        custom = (try? JSONDecoder().decode([ReminderDef].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(custom) {
            try? data.write(to: AppSupport.customRemindersURL, options: .atomic)
        }
    }
}
