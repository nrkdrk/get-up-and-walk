import SwiftUI
import AppKit

final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private var window: NSWindow?

    func show(firstRun: Bool) {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        DockPresence.windowOpened()
        NSApp.activate(ignoringOtherApps: true)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: firstRun ? [.titled, .fullSizeContentView]
                                : [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = firstRun ? L.t("Başlayalım", "Let's get started")
                           : L.t("Profil", "Profile")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: OnboardingView(firstRun: firstRun) { [weak self] in
            self?.close()
        })
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DockPresence.windowClosed()
    }
}

struct OnboardingView: View {
    let firstRun: Bool
    let onFinish: () -> Void

    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var store = Store.shared

    @State private var height = ""
    @State private var weight = ""

    private var canFinish: Bool {
        !profiles.profile.firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if firstRun {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.t("Kalk Yürü", "Get Up and Walk"))
                                .font(.system(size: 24, weight: .semibold))
                            Text(L.t("Masa başında geçen günü sağlıklı aralıklara bölen küçük bir yardımcı.",
                                     "A small helper that breaks a desk-bound day into healthy intervals."))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    section(L.t("Dil", "Language")) {
                        Picker("", selection: Binding(
                            get: { profiles.profile.language },
                            set: { profiles.profile.language = $0 }
                        )) {
                            ForEach(Lang.allCases) { l in Text(l.display).tag(l) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    section(L.t("Seni nasıl çağıralım?", "What should we call you?")) {
                        HStack(spacing: 10) {
                            TextField(L.t("Ad", "First name"), text: Binding(
                                get: { profiles.profile.firstName },
                                set: { profiles.profile.firstName = $0 }
                            ))
                            TextField(L.t("Soyad", "Last name"), text: Binding(
                                get: { profiles.profile.lastName },
                                set: { profiles.profile.lastName = $0 }
                            ))
                        }
                        .textFieldStyle(.roundedBorder)

                        Toggle(isOn: Binding(
                            get: { profiles.profile.voiceEnabled },
                            set: { profiles.profile.voiceEnabled = $0 }
                        )) {
                            Text(L.t("Hatırlatmalarda adımla sesli seslen",
                                     "Say my name out loud with reminders"))
                                .font(.system(size: 12))
                        }

                        if profiles.profile.voiceEnabled && canFinish {
                            Button(L.t("Dinle", "Preview")) {
                                Speaker.shared.say(Kind.move.definition.spoken(name: profiles.profile.displayName))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    section(L.t("Boy ve kilo", "Height and weight")) {
                        HStack(spacing: 10) {
                            LabeledField(label: L.t("Boy (cm)", "Height (cm)"), text: $height)
                            LabeledField(label: L.t("Kilo (kg)", "Weight (kg)"), text: $weight)
                        }
                        if let bmi = profiles.profile.bmi {
                            Text(String(format: L.t("Vücut kitle indeksi: %.1f", "Body mass index: %.1f"), bmi))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    section(L.t("Varis ya da bacak damar şikâyetin var mı?",
                                "Any varicose or leg vein complaints?")) {
                        Picker("", selection: Binding(
                            get: { profiles.profile.varicose },
                            set: { profiles.profile.varicose = $0 }
                        )) {
                            ForEach(VaricoseStatus.allCases) { v in Text(v.label).tag(v) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(L.t("Opsiyonel. Yanıtına göre bacak dolaşımıyla ilgili hatırlatmalar açılır; sonradan tek tek değiştirebilirsin.",
                                 "Optional. Your answer sets which leg-circulation reminders start on; you can change each one later."))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)
            }

            Divider()

            HStack {
                if !firstRun {
                    Text(L.t("Değişiklikler anında kaydedilir.", "Changes are saved as you type."))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(firstRun ? L.t("Başla", "Start") : L.t("Kapat", "Close")) {
                    commit()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canFinish)
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
        .onAppear {
            if profiles.profile.heightCm > 0 { height = String(format: "%.0f", profiles.profile.heightCm) }
            if profiles.profile.weightKg > 0 { weight = String(format: "%.1f", profiles.profile.weightKg) }
        }
        .onChange(of: height) { _ in commitNumbers() }
        .onChange(of: weight) { _ in commitNumbers() }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func commitNumbers() {
        if let h = Double(height.replacingOccurrences(of: ",", with: ".")) {
            profiles.profile.heightCm = h
        }
        if let w = Double(weight.replacingOccurrences(of: ",", with: ".")) {
            profiles.profile.weightKg = w
        }
    }

    private func commit() {
        commitNumbers()
        profiles.profile.firstName = profiles.profile.firstName.trimmingCharacters(in: .whitespaces)
        profiles.profile.lastName = profiles.profile.lastName.trimmingCharacters(in: .whitespaces)

        if firstRun {
            store.applyDefaults(varicose: profiles.profile.varicose)
            profiles.profile.completed = true
        }
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
