import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        Button(L.t("Paneli aç", "Open dashboard")) {
            DashboardController.shared.show()
        }
        .keyboardShortcut("d")

        Button(L.t("Profil…", "Profile…")) {
            OnboardingController.shared.show(firstRun: false)
        }

        Divider()

        Text(L.t("Bugün: \(store.todayDone) tamam, \(store.todayMissed) kaçtı",
                 "Today: \(store.todayDone) done, \(store.todayMissed) missed"))
        if let s = store.lastCalfSummary { Text(s) }
        if let s = store.lastWeightSummary { Text(s) }

        Divider()

        Menu(L.t("Hatırlatıcılar", "Reminders")) {
            ForEach(Kind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { store.enabled.contains(kind) },
                    set: { on in
                        if on { store.enabled.insert(kind) } else { store.enabled.remove(kind) }
                    }
                )) {
                    Text("\(kind.title) — \(kind.schedule.describe)")
                }
            }
        }

        Menu(L.t("Şimdi tetikle", "Trigger now")) {
            ForEach(Kind.allCases) { kind in
                Button(kind.title) { store.fireNow(kind) }
            }
        }

        Divider()

        Menu(L.t("Aktif saatler: \(store.activeStartHour):00 – \(store.activeEndHour):00",
                 "Active hours: \(store.activeStartHour):00 – \(store.activeEndHour):00")) {
            Picker(L.t("Başlangıç", "Start"), selection: Binding(
                get: { store.activeStartHour },
                set: { store.activeStartHour = $0 }
            )) {
                ForEach([6, 7, 8, 9, 10], id: \.self) { Text("\($0):00").tag($0) }
            }
            Picker(L.t("Bitiş", "End"), selection: Binding(
                get: { store.activeEndHour },
                set: { store.activeEndHour = $0 }
            )) {
                ForEach([20, 21, 22, 23, 24], id: \.self) { Text("\($0):00").tag($0) }
            }
        }

        Toggle(isOn: Binding(
            get: { profiles.profile.voiceEnabled },
            set: { profiles.profile.voiceEnabled = $0 }
        )) {
            Text(L.t("Sesli seslen", "Speak reminders"))
        }

        Button(store.paused ? L.t("Devam et", "Resume") : L.t("Duraklat", "Pause")) {
            store.paused.toggle()
        }

        Divider()

        Button(L.t("CSV olarak masaüstüne aktar", "Export CSV to Desktop")) {
            if let url = store.exportCSV() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        Button(L.t("Kayıt dosyasını göster", "Reveal log file")) {
            NSWorkspace.shared.activateFileViewerSelecting([store.logURL])
        }

        Divider()

        Button(L.t("Çık", "Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.start()

        if !ProfileStore.shared.profile.completed {
            OnboardingController.shared.show(firstRun: true)
        }
    }
}

@main
struct KalkYuruApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "figure.walk")
        }
        .menuBarExtraStyle(.menu)
    }
}
