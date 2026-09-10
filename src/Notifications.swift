import AppKit
import UserNotifications

/// Mirrors automatically fired reminders into Notification Center, alongside
/// the panel. The panel stays the primary surface — it speaks, and it is the
/// only place a measurement can be typed — so a banner is a second way to see
/// a reminder and, for simple ones, to answer it.
final class NotificationBridge: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationBridge()

    private enum Action {
        static let done = "done"
        static let snooze = "snooze"
    }

    private enum Category {
        static let simple = "reminder.simple"
        static let measure = "reminder.measure"
    }

    // Kept out of Profile on purpose: Profile decodes with synthesized Codable,
    // so a new field would fail to decode the stored profile and reset it.
    private let enabledKey = "notificationsEnabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: enabledKey)
            if enabled { requestAuthorization() }
        }
    }

    private override init() {
        enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        super.init()
    }

    /// UNUserNotificationCenter traps in a process with no bundle identifier,
    /// which is what a bare build of these sources outside the app bundle is.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Call once at launch, before a banner can deliver a response.
    func start() {
        center?.delegate = self
        if enabled { requestAuthorization() }
    }

    private func requestAuthorization() {
        center?.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ def: ReminderDef) {
        guard enabled, let center else { return }
        registerCategories(on: center)

        let content = UNMutableNotificationContent()
        content.title = def.title
        content.body = def.subtitle
        content.sound = nil   // the panel has already chimed
        content.categoryIdentifier = def.fields.isEmpty ? Category.simple : Category.measure

        // Keyed by reminder, so a new fire replaces its previous banner.
        center.add(UNNotificationRequest(identifier: def.id, content: content, trigger: nil))
    }

    func withdraw(_ id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Registered on every post so the button titles follow the current language.
    private func registerCategories(on center: UNUserNotificationCenter) {
        let done = UNNotificationAction(identifier: Action.done,
                                        title: L.t("Tamam", "Done"), options: [])
        let snooze = UNNotificationAction(identifier: Action.snooze,
                                          title: L.t("10 dk", "10 min"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.simple, actions: [done, snooze],
                                   intentIdentifiers: [], options: []),
            // A banner cannot take the numbers a measurement needs.
            UNNotificationCategory(identifier: Category.measure, actions: [],
                                   intentIdentifiers: [], options: [])
        ])
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            switch action {
            case Action.done:   PanelController.shared.answer(id, .done)
            case Action.snooze: PanelController.shared.answer(id, .snoozed)
            default:            PanelController.shared.bringForward(id)
            }
            completionHandler()
        }
    }
}
