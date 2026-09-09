import SwiftUI
import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController {
    static let shared = PanelController()
    private var panel: KeyablePanel?

    var isIdle: Bool { panel == nil }

    func show(kind: Kind) {
        if panel != nil { close() }

        let fields = kind.inputFields
        let needsInput = !fields.isEmpty
        let height: CGFloat = needsInput ? CGFloat(152 + fields.count * 40) : 152
        let size = NSSize(width: 340, height: height)

        let view = ReminderView(
            kind: kind,
            width: size.width,
            height: height,
            onDone:   { [weak self] values in self?.finish(kind, .done, values) },
            onSnooze: { [weak self] in self?.finishSnooze(kind) },
            onExpire: { [weak self] in self?.finish(kind, .missed, nil) }
        )

        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 48))
        }

        if needsInput {
            NSApp.activate(ignoringOtherApps: true)
            p.makeKeyAndOrderFront(nil)
        } else {
            p.orderFrontRegardless()
        }
        panel = p

        NSSound(named: NSSound.Name(kind.sound))?.play()

        // Let the chime finish before speaking.
        let name = ProfileStore.shared.profile.displayName
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            Speaker.shared.say(kind.spoken(name: name))
        }
    }

    private func close() {
        Speaker.shared.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func finish(_ kind: Kind, _ outcome: Outcome, _ values: [String: Double]?) {
        close()
        Store.shared.record(kind, outcome, values: values)
    }

    private func finishSnooze(_ kind: Kind) {
        close()
        Store.shared.snooze(kind)
    }
}

struct ReminderView: View {
    let kind: Kind
    let width: CGFloat
    let height: CGFloat
    let onDone: ([String: Double]?) -> Void
    let onSnooze: () -> Void
    let onExpire: () -> Void

    private let fields: [InputField]

    @State private var remaining: Int
    @State private var inputs: [String]
    @FocusState private var focused: Int?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(kind: Kind, width: CGFloat, height: CGFloat,
         onDone: @escaping ([String: Double]?) -> Void,
         onSnooze: @escaping () -> Void,
         onExpire: @escaping () -> Void) {
        self.kind = kind
        self.width = width
        self.height = height
        self.onDone = onDone
        self.onSnooze = onSnooze
        self.onExpire = onExpire
        self.fields = kind.inputFields
        _remaining = State(initialValue: kind.autoCloseSeconds ?? 0)
        _inputs = State(initialValue: Array(repeating: "", count: kind.inputFields.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(kind.tint.opacity(0.16)).frame(width: 42, height: 42)
                    Image(systemName: kind.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(kind.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title).font(.system(size: 15, weight: .semibold))
                    Text(kind.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !fields.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(fields.enumerated()), id: \.offset) { pair in
                        HStack {
                            Text(pair.element.label)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("", text: Binding(
                                get: { inputs[pair.offset] },
                                set: { inputs[pair.offset] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .focused($focused, equals: pair.offset)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if kind.autoCloseSeconds != nil {
                    Text(L.t("\(remaining) sn", "\(remaining)s"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .opacity(0.7)
                }

                Spacer()

                if kind.snoozable {
                    Button(L.t("10 dk", "10 min"), action: onSnooze)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                Button(action: { onDone(collect()) }) {
                    Text(fields.isEmpty ? L.t("Tamam", "Done") : L.t("Kaydet", "Save"))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(kind.tint)
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { if !fields.isEmpty { focused = 0 } }
        .onReceive(tick) { _ in
            guard kind.autoCloseSeconds != nil else { return }
            remaining -= 1
            if remaining <= 0 { onExpire() }
        }
    }

    private func collect() -> [String: Double]? {
        guard !fields.isEmpty else { return nil }
        var out: [String: Double] = [:]
        for (i, field) in fields.enumerated() {
            let clean = inputs[i].replacingOccurrences(of: ",", with: ".")
            if let v = Double(clean) { out[field.key] = v }
        }
        return out.isEmpty ? nil : out
    }
}
