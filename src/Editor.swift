import SwiftUI
import AppKit

/// Drives the editor sheet. The dashboard owns the presentation; the menu bar
/// only asks for it, so both entry points end up in the same window.
final class EditorPresenter: ObservableObject {
    static let shared = EditorPresenter()

    @Published var editing: ReminderDef?

    func create() {
        DashboardController.shared.show()
        editing = ReminderDef.newCustom()
    }

    func edit(_ def: ReminderDef) {
        editing = def
    }
}

private enum ScheduleMode: Int, CaseIterable, Identifiable {
    case interval, daily, weekly
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .interval: return L.t("Aralık", "Interval")
        case .daily:    return L.t("Günlük", "Daily")
        case .weekly:   return L.t("Haftalık", "Weekly")
        }
    }
}

struct ReminderEditor: View {
    let original: ReminderDef
    let onClose: () -> Void

    @ObservedObject private var store = Store.shared

    @State private var title: String
    @State private var subtitle: String
    @State private var spoken: String
    @State private var iconName: String
    @State private var tintHex: String

    @State private var mode: ScheduleMode
    @State private var minutes: Int
    @State private var hour: Int
    @State private var minute: Int
    @State private var weekday: Int

    @State private var collects: Bool
    @State private var fields: [FieldDef]

    @State private var confirmingDelete = false
    @State private var enabledDraft: Bool

    private let existingKeys: Set<String>
    /// True until the first save, which is when the definition starts existing.
    private let isNew: Bool

    init(def: ReminderDef, onClose: @escaping () -> Void) {
        self.original = def
        self.onClose = onClose
        _title = State(initialValue: def.title)
        _subtitle = State(initialValue: def.subtitle)
        _spoken = State(initialValue: L.pick(def.spokenTR, def.spokenEN))
        _iconName = State(initialValue: def.iconName)
        _tintHex = State(initialValue: def.tintHex)
        _collects = State(initialValue: !def.fields.isEmpty)
        _fields = State(initialValue: def.fields)
        existingKeys = Set(def.fields.map { $0.key })
        isNew = !def.isBuiltIn && !ReminderStore.shared.custom.contains { $0.id == def.id }
        _enabledDraft = State(initialValue: isNew ? true : Store.shared.enabled.contains(def.id))

        switch def.schedule {
        case .interval(let m):
            _mode = State(initialValue: .interval)
            _minutes = State(initialValue: m)
            _hour = State(initialValue: 9)
            _minute = State(initialValue: 0)
            _weekday = State(initialValue: 2)
        case .daily(let h, let m):
            _mode = State(initialValue: .daily)
            _minutes = State(initialValue: 60)
            _hour = State(initialValue: h)
            _minute = State(initialValue: m)
            _weekday = State(initialValue: 2)
        case .weekly(let wd, let h, let m):
            _mode = State(initialValue: .weekly)
            _minutes = State(initialValue: 60)
            _hour = State(initialValue: h)
            _minute = State(initialValue: m)
            _weekday = State(initialValue: wd)
        }
    }

    private var locked: Bool { original.isBuiltIn }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if locked { readOnlyBanner }

            ScrollView {
                form
            }

            Divider()

            footer
        }
        .frame(width: 540, height: 660)
        .alert(L.t("Bu hatırlatıcı silinsin mi?", "Delete this reminder?"),
               isPresented: $confirmingDelete) {
            Button(L.t("Vazgeç", "Cancel"), role: .cancel) { }
            Button(L.t("Sil", "Delete"), role: .destructive) {
                ReminderStore.shared.delete(original)
                onClose()
            }
        } message: {
            Text(L.t("Kayıt dosyasındaki geçmişi silinmez, orada kalır.",
                     "Its logged history is not deleted; it stays in the log file."))
        }
    }

    // MARK: Sections

    private var readOnlyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text(L.t("Hazır hatırlatıcı — değiştirilemez. Yalnızca üstteki anahtarla açıp kapatabilirsin.",
                     "Built-in reminder — read-only. Only the switch above can be changed."))
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
    }

    var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            textSection
            appearanceSection
            scheduleSection
            fieldsSection
        }
        .padding(24)
        .disabled(locked)
        .opacity(locked ? 0.55 : 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: tintHex).opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: symbolExists(iconName) ? iconName : "questionmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: tintHex))
            }

            Text(title.isEmpty ? L.t("Yeni hatırlatıcı", "New reminder") : title)
                .font(.system(size: 15, weight: .semibold))

            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle(isOn: Binding(
                get: { isNew ? enabledDraft : store.enabled.contains(original.id) },
                set: { on in
                    guard !isNew else { enabledDraft = on; return }
                    if on { store.enabled.insert(original.id) } else { store.enabled.remove(original.id) }
                }
            )) {
                Text(L.t("Açık", "On")).font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L.t("Başlık", "Title")) {
                TextField("", text: $title).textFieldStyle(.roundedBorder)
            }
            field(L.t("Alt başlık", "Subtitle")) {
                TextField("", text: $subtitle).textFieldStyle(.roundedBorder)
            }
            field(L.t("Sesli cümle", "Spoken sentence")) {
                HStack(spacing: 8) {
                    TextField("", text: $spoken).textFieldStyle(.roundedBorder)
                    Button(L.t("Dinle", "Preview")) {
                        Speaker.shared.say(previewSentence)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(spoken.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(L.t("Cümledeki %@ yerine adın söylenir.",
                         "%@ in the sentence is replaced with your first name."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L.t("Simge (SF Symbol)", "Icon (SF Symbol)")) {
                HStack(spacing: 10) {
                    TextField("", text: $iconName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    if symbolExists(iconName) {
                        Image(systemName: iconName)
                            .font(.system(size: 17))
                            .foregroundStyle(Color(hex: tintHex))
                    } else {
                        Text(L.t("böyle bir simge yok", "no such symbol"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            field(L.t("Renk", "Colour")) {
                HStack(spacing: 10) {
                    ForEach(Palette.choices, id: \.self) { hex in
                        Button {
                            tintHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(Color.primary.opacity(tintHex == hex ? 0.6 : 0),
                                                          lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L.t("Ne zaman", "When")) {
                Picker("", selection: $mode) {
                    ForEach(ScheduleMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .interval:
                    Stepper(value: $minutes, in: 5...480, step: 5) {
                        Text(L.t("\(minutes) dakikada bir", "every \(minutes) min"))
                            .font(.system(size: 12))
                    }
                    .frame(width: 240)

                case .daily:
                    timePickers

                case .weekly:
                    HStack(spacing: 10) {
                        Picker("", selection: $weekday) {
                            ForEach(1...7, id: \.self) { wd in
                                Text(Schedule.weekdayName(wd)).tag(wd)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        timePickers
                    }
                }
            }
        }
    }

    private var timePickers: some View {
        HStack(spacing: 6) {
            Picker("", selection: $hour) {
                ForEach(0...23, id: \.self) { h in Text(String(format: "%02d", h)).tag(h) }
            }
            .labelsHidden()
            .frame(width: 70)

            Text(":").foregroundStyle(.secondary)

            Picker("", selection: $minute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 70)

            Spacer()
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { collects },
                set: { on in
                    collects = on
                    if on && fields.isEmpty { fields = [FieldDef.blank()] }
                }
            )) {
                Text(L.t("Bir ölçüm topluyor", "Collects a measurement"))
                    .font(.system(size: 13, weight: .semibold))
            }

            if collects {
                ForEach(Array(fields.enumerated()), id: \.offset) { pair in
                    fieldRow(index: pair.offset)
                }

                if fields.count < 3 {
                    Button(L.t("Alan ekle", "Add field")) {
                        fields.append(FieldDef.blank())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text(L.t("En fazla üç alan", "Three fields at most"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func fieldRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(L.t("Etiket", "Label"), text: binding(index, \.labelTR, \.labelEN))
                    .textFieldStyle(.roundedBorder)
                TextField(L.t("Birim", "Unit"), text: Binding(
                    get: { fields[index].unit },
                    set: { fields[index].unit = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Button {
                    fields.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField(L.t("Referans değeri (opsiyonel)", "Reference value (optional)"), text: Binding(
                    get: {
                        guard let v = fields[index].referenceValue else { return "" }
                        return String(format: "%g", v)
                    },
                    set: { text in
                        let clean = text.replacingOccurrences(of: ",", with: ".")
                        fields[index].referenceValue = clean.isEmpty ? nil : Double(clean)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                TextField(L.t("Referans etiketi", "Reference label"),
                          text: referenceLabelBinding(index))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !original.isBuiltIn && !isNew {
                Button(L.t("Sil", "Delete"), role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.bordered)
            }

            Spacer()

            Button(L.t("Kapat", "Close")) { onClose() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            if !locked {
                Button(L.t("Kaydet", "Save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
    }

    // MARK: Helpers

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private var previewSentence: String {
        spoken.replacingOccurrences(of: "%@", with: ProfileStore.shared.profile.displayName)
    }

    private func symbolExists(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// Edits the slot of the language in use and mirrors it into the other one
    /// while the two are still in sync, so nothing ever renders blank.
    private func binding(_ index: Int,
                         _ tr: WritableKeyPath<FieldDef, String>,
                         _ en: WritableKeyPath<FieldDef, String>) -> Binding<String> {
        Binding(
            get: { L.lang == .tr ? fields[index][keyPath: tr] : fields[index][keyPath: en] },
            set: { text in
                var f = fields[index]
                var trText = f[keyPath: tr]
                var enText = f[keyPath: en]
                mirror(text, &trText, &enText)
                f[keyPath: tr] = trText
                f[keyPath: en] = enText
                fields[index] = f
            }
        )
    }

    private func referenceLabelBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let f = fields[index]
                return (L.lang == .tr ? f.referenceLabelTR : f.referenceLabelEN) ?? ""
            },
            set: { text in
                var f = fields[index]
                var tr = f.referenceLabelTR ?? ""
                var en = f.referenceLabelEN ?? ""
                mirror(text, &tr, &en)
                f.referenceLabelTR = tr.isEmpty ? nil : tr
                f.referenceLabelEN = en.isEmpty ? nil : en
                fields[index] = f
            }
        )
    }

    private func mirror(_ text: String, _ tr: inout String, _ en: inout String) {
        let current = L.lang == .tr ? tr : en
        let other = L.lang == .tr ? en : tr
        let inSync = other.isEmpty || other == current
        if L.lang == .tr {
            tr = text
            if inSync { en = text }
        } else {
            en = text
            if inSync { tr = text }
        }
    }

    /// CSV-safe column name derived from the label, unique within the reminder.
    private func columnKey(for label: String, taken: Set<String>) -> String {
        let folded = label.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_US"))
        var slug = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                slug.append(ch)
            } else if !slug.hasSuffix("_") {
                slug.append("_")
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty { slug = "value" }

        var candidate = slug
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(slug)_\(n)"
            n += 1
        }
        return candidate
    }

    private func save() {
        var def = original
        mirror(title.trimmingCharacters(in: .whitespaces), &def.titleTR, &def.titleEN)
        mirror(subtitle, &def.subtitleTR, &def.subtitleEN)
        mirror(spoken, &def.spokenTR, &def.spokenEN)
        def.iconName = symbolExists(iconName) ? iconName : "bell"
        def.tintHex = tintHex

        switch mode {
        case .interval: def.schedule = .interval(minutes)
        case .daily:    def.schedule = .daily(hour: hour, minute: minute)
        case .weekly:   def.schedule = .weekly(weekday: weekday, hour: hour, minute: minute)
        }

        if collects {
            // A key is fixed the first time it is saved: it names a column in
            // the CSV and a slot in the log, so later label edits leave it be.
            var taken = existingKeys
            def.fields = fields.compactMap { f in
                var f = f
                guard !f.label.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                if !existingKeys.contains(f.key) {
                    let key = columnKey(for: f.label, taken: taken)
                    taken.insert(key)
                    f = FieldDef(key: key,
                                 labelTR: f.labelTR, labelEN: f.labelEN, unit: f.unit,
                                 referenceValue: f.referenceValue,
                                 referenceLabelTR: f.referenceLabelTR,
                                 referenceLabelEN: f.referenceLabelEN)
                }
                return f
            }
        } else {
            def.fields = []
        }

        ReminderStore.shared.upsert(def)
        if isNew && enabledDraft { store.enabled.insert(def.id) }
        onClose()
    }
}
