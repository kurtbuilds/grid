import SwiftUI
import Combine
import GridCore

enum OnboardingStep: Int, CaseIterable {
    case welcome, accessibility, launchAtLogin, tryIt, done
}

final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep
    @Published var axTrusted = WindowManager.isTrusted
    @Published var launchStatus = LaunchAtLogin.status
    @Published var openedGrid = false
    @Published var snappedWindow = false
    /// Set after the user has gone off to System Settings, so we can offer the stale-entry fix.
    @Published var visitedAccessibilitySettings = false

    /// Called when access flips to granted, so the window can come back in front of System Settings.
    var onTrustGranted: (() -> Void)?
    var onStepChange: ((OnboardingStep) -> Void)?
    var onFinish: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init(startAt step: OnboardingStep = .welcome) {
        self.step = step
        Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .gridOverlayOpened)
            .sink { [weak self] _ in self?.openedGrid = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .gridWindowSnapped)
            .sink { [weak self] _ in self?.snappedWindow = true }
            .store(in: &cancellables)
        $step.dropFirst().sink { [weak self] in self?.onStepChange?($0) }.store(in: &cancellables)
    }

    func refresh() {
        let trusted = WindowManager.isTrusted
        if trusted && !axTrusted { onTrustGranted?() }
        if trusted != axTrusted { axTrusted = trusted }
        let status = LaunchAtLogin.status
        if status != launchStatus { launchStatus = status }
    }

    func next() {
        if let n = OnboardingStep(rawValue: step.rawValue + 1) { step = n } else { onFinish?() }
    }

    func back() {
        if let p = OnboardingStep(rawValue: step.rawValue - 1) { step = p }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store: SettingsStore
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: welcome
                case .accessibility: accessibility
                case .launchAtLogin: launchAtLogin
                case .tryIt: tryIt
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 580, height: 480)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }
            }
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch model.step {
        case .welcome:
            Button("Get Started") { model.next() }.keyboardShortcut(.defaultAction)
        case .accessibility:
            if model.axTrusted {
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Skip for Now") { model.next() }
            }
        case .launchAtLogin:
            Button("Continue") { model.next() }.keyboardShortcut(.defaultAction)
        case .tryIt:
            Button(model.snappedWindow ? "Continue" : "Skip") { model.next() }.keyboardShortcut(.defaultAction)
        case .done:
            Button("Done") { model.onFinish?() }.keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to Grid").font(.largeTitle.weight(.semibold))
            Text("Snap any window to a grid, instantly, with one shortcut and a drag or a single key.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                Feature(symbol: "keyboard", text: "Press \(store.config.launchKey.displayString) anywhere to open the grid")
                Feature(symbol: "hand.draw", text: "Drag across cells, or press a saved key like C or F")
                Feature(symbol: "display.2", text: "Press Tab to send the window to your next display")
            }
            .padding(.top, 6)
            Text("Setup takes about a minute.").font(.callout).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var accessibility: some View {
        StepLayout(symbol: "hand.raised.fill", tint: .blue, title: "Allow Accessibility access",
                   subtitle: "This is the only permission Grid requires. macOS uses it to let an app move and resize other apps' windows. Grid doesn't read window contents or what you type.") {
            StatusRow(granted: model.axTrusted, grantedText: "Accessibility access granted",
                      pendingText: "Waiting for access…")

            if !model.axTrusted {
                VStack(alignment: .leading, spacing: 10) {
                    Instruction(n: 1, text: "Click **Open System Settings** below.")
                    Instruction(n: 2, text: "Find **Grid** in the list and switch it **on**.")
                    Instruction(n: 3, text: "Come back here. This page updates on its own.")
                }
                Button {
                    model.visitedAccessibilitySettings = true
                    WindowManager.promptForTrust()
                    WindowManager.openAccessibilitySettings()
                } label: {
                    Label("Open System Settings", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                if model.visitedAccessibilitySettings {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Grid is already switched on but this still says waiting? macOS may be remembering an older copy of the app.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Reset Grid's permission and ask again") { WindowManager.resetTrust() }
                                .buttonStyle(.link).font(.callout)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var launchAtLogin: some View {
        StepLayout(symbol: "power", tint: .green, title: "Start Grid when you log in",
                   subtitle: "Optional. Grid stays in your menu bar and uses almost no resources, so it's ready whenever you press the shortcut.") {
            Toggle(isOn: Binding(
                get: { model.launchStatus == .enabled || model.launchStatus == .requiresApproval },
                set: { LaunchAtLogin.set($0); model.refresh() }
            )) {
                Text("Launch Grid at login").font(.body.weight(.medium))
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            if model.launchStatus == .requiresApproval {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS needs you to allow Grid under **Login Items & Extensions**.")
                            .font(.callout)
                        Button("Open Login Items Settings") { LaunchAtLogin.openLoginItemsSettings() }
                            .buttonStyle(.link).font(.callout)
                    }
                }
            } else if model.launchStatus == .enabled {
                StatusRow(granted: true, grantedText: "Grid will start at login", pendingText: "")
            }
        }
    }

    private var tryIt: some View {
        StepLayout(symbol: "square.grid.3x3.fill", tint: .purple, title: "Try it out",
                   subtitle: "Click any other app's window to focus it, then:") {
            if !model.axTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Grid can't move windows until Accessibility access is on.").font(.callout)
                    Button("Go back") { model.step = .accessibility }.buttonStyle(.link).font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Checklist(done: model.openedGrid) {
                    HStack(spacing: 6) { Text("Press"); KeyCap(text: store.config.launchKey.displayString); Text("to open the grid") }
                }
                Checklist(done: model.snappedWindow) {
                    HStack(spacing: 6) {
                        Text("Drag across a few cells, or press"); KeyCap(text: "C"); Text("to center it")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            if model.snappedWindow {
                Text("That's it. 🎉").font(.title3.weight(.medium)).transition(.opacity)
            } else {
                Text("This window stays on top while you try it.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: model.snappedWindow)
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64))
                .symbolRenderingMode(.palette).foregroundStyle(.white, .green)
            Text("You're all set").font(.largeTitle.weight(.semibold))
            Text("Grid lives in your menu bar. A few keys to remember while the grid is open:")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                KeyHelp(key: "Tab", text: "Move the window to the next display (⇧Tab goes back)")
                KeyHelp(key: store.config.launchKey.displayString, text: store.config.repeatBehavior == .cycleDisplays
                        ? "Press again to cycle displays" : "Press again to close")
                KeyHelp(key: "F  C  ←  →", text: "Saved shortcuts: full screen, center, halves…")
                KeyHelp(key: "Esc", text: "Close the grid")
            }
            .padding(.top, 4)
            Button("Customize Shortcuts in Settings…") {
                model.onFinish?()
                openSettings()
            }
            .buttonStyle(.link)
            .padding(.top, 4)
        }
    }
}

// MARK: - Pieces

private struct StepLayout<Content: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Feature: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(Color.accentColor)
            Text(text)
        }
    }
}

private struct StatusRow: View {
    let granted: Bool
    let grantedText: String
    let pendingText: String
    var body: some View {
        HStack(spacing: 10) {
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
                Text(grantedText).fontWeight(.medium)
            } else {
                ProgressView().controlSize(.small)
                Text(pendingText).foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: granted)
    }
}

private struct Instruction: View {
    let n: Int
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
            Text(text)
        }
    }
}

private struct Checklist<Label: View>: View {
    let done: Bool
    @ViewBuilder var label: Label
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
            label.foregroundStyle(done ? .secondary : .primary)
        }
        .animation(.default, value: done)
    }
}

private struct KeyHelp: View {
    let key: String
    let text: String
    var body: some View {
        GridRow {
            KeyCap(text: key).gridColumnAlignment(.trailing)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
