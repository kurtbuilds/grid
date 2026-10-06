import SwiftUI
import Carbon.HIToolbox
import GridCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var openSetupGuide: () -> Void = {}
    @State private var editing: EditRequest?
    @State private var axTrusted = WindowManager.isTrusted
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var hotKeyFailed = false
    @State private var confirmRestore = false

    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    struct EditRequest: Identifiable {
        var shortcut: GridShortcut
        var isNew: Bool
        var id: UUID { shortcut.id }
    }

    var body: some View {
        Form {
            if !axTrusted {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility access needed").fontWeight(.semibold)
                            Text("Grid needs it to move and resize windows.").foregroundStyle(.secondary).font(.callout)
                        }
                        Spacer()
                        Button("Set Up…", action: openSetupGuide)
                    }
                }
            }

            Section("General") {
                LabeledContent("Show grid") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder(combo: Binding(
                            get: { store.config.launchKey },
                            set: { if let v = $0 { store.config.launchKey = v } }
                        ), allowsClear: false)
                        if hotKeyFailed {
                            Text("Another app is already using this shortcut.").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Picker("Pressing it again while open", selection: $store.config.repeatBehavior) {
                    ForEach(RepeatBehavior.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Highlight the target area while selecting", isOn: $store.config.showPreview)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
                ))
            }

            Section("Grid") {
                CountStepper(title: "Columns", value: $store.config.columns)
                CountStepper(title: "Rows", value: $store.config.rows)
            }

            Section {
                ForEach(store.config.shortcuts) { shortcut in
                    ShortcutRow(shortcut: shortcut, duplicate: isDuplicate(shortcut)) {
                        editing = EditRequest(shortcut: shortcut, isNew: false)
                    } onDelete: {
                        store.config.shortcuts.removeAll { $0.id == shortcut.id }
                    }
                }
                .onMove { store.config.shortcuts.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    let c = store.config
                    editing = EditRequest(shortcut: GridShortcut(
                        name: "", key: nil, columns: c.columns, rows: c.rows,
                        rect: GridRect(x: 0, y: 0, w: max(c.columns / 2, 1), h: max(c.rows / 2, 1))
                    ), isNew: true)
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Button("Restore Defaults…") { confirmRestore = true }
                        .buttonStyle(.borderless)
                        .disabled(store.config.shortcuts == Config.defaultShortcuts)
                }
                .confirmationDialog("Replace your shortcuts with the defaults?", isPresented: $confirmRestore) {
                    Button("Restore Defaults", role: .destructive) { store.config.shortcuts = Config.defaultShortcuts }
                } message: {
                    Text("Your current shortcuts will be removed.")
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("While the grid is open, press a shortcut's key to snap the window instantly — no mouse needed. Plain keys like C are fine; Esc and Tab are reserved.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 560, idealHeight: 720)
        .sheet(item: $editing) { request in
            ShortcutEditor(draft: request.shortcut, isNew: request.isNew, existing: store.config.shortcuts) { saved in
                if let i = store.config.shortcuts.firstIndex(where: { $0.id == saved.id }) {
                    store.config.shortcuts[i] = saved
                } else {
                    store.config.shortcuts.append(saved)
                }
            }
        }
        .onReceive(trustTimer) { _ in
            axTrusted = WindowManager.isTrusted
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyRegistrationChanged)) { note in
            hotKeyFailed = (note.object as? Bool) == false
        }
    }

    private func isDuplicate(_ shortcut: GridShortcut) -> Bool {
        guard let key = shortcut.key else { return false }
        return store.config.shortcuts.contains { $0.id != shortcut.id && $0.key == key }
    }
}

extension Notification.Name {
    static let hotKeyRegistrationChanged = Notification.Name("GridHotKeyRegistrationChanged")
}

// MARK: - Rows

struct CountStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value)").monospacedDigit()
                Stepper(title, value: $value, in: Config.gridRange).labelsHidden()
            }
        }
    }
}

struct ShortcutRow: View {
    let shortcut: GridShortcut
    let duplicate: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GridThumbnail(columns: shortcut.columns, rows: shortcut.rows, selection: shortcut.rect)
                .frame(width: 48, height: 30)
            Text(shortcut.name.isEmpty ? "Untitled" : shortcut.name)
            Spacer()
            if duplicate {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Another shortcut uses the same key; the first one wins.")
            }
            Button(action: onEdit) { KeyCap(text: shortcut.key?.displayString ?? "—") }
                .buttonStyle(.plain)
                .help("Edit shortcut")
                .onHover { inside in (inside ? NSCursor.pointingHand : NSCursor.arrow).set() }
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .frame(minWidth: 28)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

struct GridThumbnail: View {
    let columns: Int
    let rows: Int
    let selection: GridRect

    var body: some View {
        Canvas { context, size in
            let cw = size.width / CGFloat(columns), ch = size.height / CGFloat(rows)
            for row in 0..<rows {
                for col in 0..<columns {
                    let r = CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch, width: cw, height: ch).insetBy(dx: 0.75, dy: 0.75)
                    let on = selection.contains(col: col, row: row)
                    context.fill(Path(roundedRect: r, cornerRadius: 1.5),
                                 with: .color(on ? .accentColor : .secondary.opacity(0.25)))
                }
            }
        }
    }
}

// MARK: - Editor

struct ShortcutEditor: View {
    @State var draft: GridShortcut
    let isNew: Bool
    let existing: [GridShortcut]
    let onSave: (GridShortcut) -> Void
    @Environment(\.dismiss) private var dismiss

    private var conflict: GridShortcut? {
        guard let key = draft.key else { return nil }
        return existing.first { $0.id != draft.id && $0.key == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Shortcut" : "Edit Shortcut").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing)
                    TextField("e.g. Upper Left", text: $draft.name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Key")
                    HStack {
                        // Starts listening right away: open the editor and just type the new key.
                        ShortcutRecorder(combo: $draft.key, allowsClear: true,
                                         reservedKeys: [UInt16(kVK_Escape), UInt16(kVK_Tab)],
                                         recordOnAppear: true)
                        if let conflict {
                            Text("Also used by “\(conflict.name)”").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                GridRow {
                    Text("Grid")
                    HStack(spacing: 16) {
                        Stepper("\(draft.columns) columns", value: $draft.columns, in: Config.gridRange)
                        Stepper("\(draft.rows) rows", value: $draft.rows, in: Config.gridRange)
                    }
                }
            }

            GridSelector(columns: draft.columns, rows: draft.rows, selection: $draft.rect)
                .frame(height: 250) // explicit: a GeometryReader in a self-sizing sheet can collapse
            Text("Drag across the grid to choose the area.").font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var s = draft
                    s.name = s.name.trimmingCharacters(in: .whitespaces)
                    if s.name.isEmpty { s.name = "Untitled" }
                    onSave(s)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.key == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: draft.columns) { draft.rect = draft.rect.clamped(columns: draft.columns, rows: draft.rows) }
        .onChange(of: draft.rows) { draft.rect = draft.rect.clamped(columns: draft.columns, rows: draft.rows) }
    }
}

struct GridSelector: View {
    let columns: Int
    let rows: Int
    @Binding var selection: GridRect
    @State private var dragStart: GridCell?

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(columns), ch = geo.size.height / CGFloat(rows)
            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<columns {
                        let r = CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch, width: cw, height: ch).insetBy(dx: 2, dy: 2)
                        let on = selection.contains(col: col, row: row)
                        context.fill(Path(roundedRect: r, cornerRadius: 4),
                                     with: .color(on ? .accentColor : .secondary.opacity(0.18)))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    func cell(_ p: CGPoint) -> GridCell {
                        GridCell(col: min(max(Int(p.x / cw), 0), columns - 1), row: min(max(Int(p.y / ch), 0), rows - 1))
                    }
                    let start = dragStart ?? cell(value.startLocation)
                    dragStart = start
                    selection = .spanning(start, cell(value.location))
                }
                .onEnded { _ in dragStart = nil })
        }
    }
}

// MARK: - Recorder

struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    var allowsClear: Bool
    var reservedKeys: Set<UInt16> = []
    /// Start recording as soon as the control appears. Esc then cancels the surrounding sheet too.
    var recordOnAppear = false
    @StateObject private var model = RecorderModel()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.isRecording ? model.stop() : startRecording(passEscape: false)
            } label: {
                Text(model.isRecording ? (combo.map { "\($0.displayString) → type a key…" } ?? "Type a key…")
                                       : (combo?.displayString ?? "Click to record"))
                    .frame(minWidth: 110)
            }
            .tint(model.isRecording ? .accentColor : nil)
            .buttonStyle(.bordered)

            if allowsClear, combo != nil, !model.isRecording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear")
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { if recordOnAppear { startRecording(passEscape: true) } }
        .onDisappear { model.stop() }
    }

    private func startRecording(passEscape: Bool) {
        model.start(reserved: reservedKeys, passEscape: passEscape) { combo = $0 }
    }
}

final class RecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var message: String?
    private var monitor: Any?
    private static weak var active: RecorderModel?

    func start(reserved: Set<UInt16>, passEscape: Bool = false, onRecord: @escaping (KeyCombo) -> Void) {
        Self.active?.stop()
        Self.active = self
        message = nil
        isRecording = true
        GlobalHotKey.shared.suspend() // so the current launch shortcut can be typed and captured
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let combo = KeyCombo(event: event)
            if event.keyCode == UInt16(kVK_Escape) && combo.modifierFlags.isEmpty {
                self.stop()
                return passEscape ? event : nil
            } else if reserved.contains(event.keyCode) {
                self.message = "\(combo.displayString) is reserved"
            } else {
                onRecord(combo)
                self.stop()
            }
            return nil
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        GlobalHotKey.shared.resume()
    }
}
