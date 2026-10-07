import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: BuddySettings
    @ObservedObject var model: BuddyModel
    let onResetPosition: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PreviewPane(settings: settings)
                .frame(width: 280)

            Divider()

            VStack(spacing: 0) {
                TabView {
                    AppearanceTab(settings: settings)
                        .tabItem { Label("Appearance", systemImage: "paintpalette") }
                    BehaviorTab(settings: settings, onResetPosition: onResetPosition)
                        .tabItem { Label("Behavior", systemImage: "figure.wave") }
                    ClaudeTab(settings: settings, model: model)
                        .tabItem { Label("Claude Code", systemImage: "terminal") }
                }
                .padding([.top, .horizontal], 12)

                HStack {
                    Button("Reset All to Defaults") { settings.resetToDefaults() }
                    Spacer()
                    Button("Quit Mac Buddy") { NSApp.terminate(nil) }
                }
                .padding(12)
            }
        }
        .frame(width: 820, height: 620)
    }
}

// MARK: - Live preview

@MainActor
private struct PreviewPane: View {
    @ObservedObject var settings: BuddySettings
    @State private var mood: Mood = .idle
    @State private var tappedAt = Date.distantPast
    @State private var tapKind = ReactionKind.spin
    @State private var hover: CGPoint?

    private let stageHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 16) {
            Text("Preview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.animation(minimumInterval: 1.0 / 40)) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate * settings.animationSpeed
                let elapsed = now.timeIntervalSince(tappedAt)
                let reaction = elapsed < tapKind.duration ? Reaction(kind: tapKind, elapsed: elapsed) : nil
                let bubble = elapsed < 2.5 && settings.showBubble
                    ? BubbleInfo(text: settings.phrases.first ?? "Boop!")
                    : BuddyStack.bubble(for: mood, projects: ["my-app"], settings: settings)
                BuddyStack(bubble: bubble, mood: mood, t: t, reaction: reaction,
                           style: settings.style(look: previewLook))
                    .opacity(settings.opacity)
            }
            .frame(width: 248, height: stageHeight, alignment: .bottom)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                tapKind = .random(excluding: tapKind)
                tappedAt = Date()
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover = point
                case .ended: hover = nil
                }
            }

            Picker("State", selection: $mood) {
                Text("Idle").tag(Mood.idle)
                Text("Work").tag(Mood.working)
                Text("Ask").tag(Mood.attention)
                Text("Done").tag(Mood.done)
                Text("Zzz").tag(Mood.sleeping)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Click the buddy to test its reaction. Size changes show on your desktop buddy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(16)
    }

    /// Eyes in the preview follow the cursor while it hovers over the stage.
    private var previewLook: CGSize {
        guard let hover else { return .zero }
        let eye = CGPoint(x: 124, y: stageHeight - BuddyLayout.eyeCenter.y)
        return lookOffset(dx: hover.x - eye.x, dy: hover.y - eye.y, reach: 120)
    }
}

// MARK: - Tabs

@MainActor
private struct AppearanceTab: View {
    @ObservedObject var settings: BuddySettings

    var body: some View {
        Form {
            Section("Size") {
                SliderRow(title: "Size", value: $settings.scale, range: 0.5...3, format: percent)
                SliderRow(title: "Opacity", value: $settings.opacity, range: 0.3...1, format: percent)
            }

            Section("Colors") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 9), spacing: 8) {
                    ForEach(ColorPreset.all) { preset in
                        Button {
                            settings.bodyHex = preset.body
                            settings.limbHex = preset.limb
                        } label: {
                            Circle()
                                .fill(RGB(hex: preset.body)!.color)
                                .overlay(Circle().stroke(RGB(hex: preset.limb)!.color, lineWidth: 3))
                                .overlay(
                                    Circle().stroke(Color.accentColor, lineWidth: 2).padding(-4)
                                        .opacity(settings.bodyHex == preset.body ? 1 : 0)
                                )
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
                ColorPicker("Body", selection: colorBinding(\.bodyHex), supportsOpacity: false)
                ColorPicker("Arms & feet", selection: colorBinding(\.limbHex), supportsOpacity: false)
            }

            Section("Look") {
                Picker("Accessory", selection: $settings.accessory) {
                    ForEach(Accessory.allCases) { Text($0.title).tag($0) }
                }
                SliderRow(title: "Roundness", value: $settings.roundness, range: 14...41,
                          format: { "\(Int($0))" })
                SliderRow(title: "Pupil size", value: $settings.pupilScale, range: 0.6...1.5, format: percent)
                Toggle("Antenna", isOn: $settings.showAntenna)
                Toggle("Rosy cheeks", isOn: $settings.showCheeks)
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ key: ReferenceWritableKeyPath<BuddySettings, String>) -> Binding<Color> {
        Binding(
            get: { (RGB(hex: settings[keyPath: key]) ?? RGB(r: 0.5, g: 0.5, b: 0.5)).color },
            set: { settings[keyPath: key] = RGB($0).hex }
        )
    }
}

@MainActor
private struct BehaviorTab: View {
    @ObservedObject var settings: BuddySettings
    let onResetPosition: () -> Void
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Eyes follow your cursor", isOn: $settings.followCursor)
            } header: {
                Text("Eyes")
            } footer: {
                Text("The buddy watches your mouse pointer anywhere on screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Animation") {
                SliderRow(title: "Speed", value: $settings.animationSpeed, range: 0.25...2,
                          format: { String(format: "%.2g×", $0) })
            }

            Section {
                Toggle("React when clicked", isOn: $settings.clickReactions)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Things it says when you click it (one per line)")
                    TextEditor(text: $settings.customPhrases)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    Text("Leave empty to use the built-in lines.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!settings.clickReactions)
            } header: {
                Text("Clicking")
            }

            Section("Sleep") {
                Toggle("Fall asleep when nothing is happening", isOn: $settings.sleepEnabled)
                Stepper("After \(Int(settings.sleepMinutes)) min", value: $settings.sleepMinutes, in: 1...120)
                    .disabled(!settings.sleepEnabled)
            }

            Section("Window") {
                Toggle("Stay on top of other windows", isOn: $settings.alwaysOnTop)
                Toggle("Show on every desktop (Space)", isOn: $settings.allSpaces)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("MacBuddy: login item change failed: \(error)")
                        }
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Button("Move Buddy Back to Corner", action: onResetPosition)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct ClaudeTab: View {
    @ObservedObject var settings: BuddySettings
    @ObservedObject var model: BuddyModel
    @State private var connected = ClaudeHooks.isConnected
    @State private var hookError: String?

    var body: some View {
        Form {
            Section("Speech bubble") {
                Toggle("Show a bubble while Claude works", isOn: $settings.showBubble)
                Toggle("Show which project it's working on", isOn: $settings.showProject)
                    .disabled(!settings.showBubble)
            }

            Section("Activity") {
                Toggle("Celebrate when Claude finishes", isOn: $settings.celebrate)
                Toggle("Only show the buddy while Claude is active", isOn: $settings.hideWhenIdle)
            }

            Section {
                TextField("Only follow projects containing", text: $settings.projectFilter,
                          prompt: Text("All projects"))
                LabeledContent("Right now", value: status)
            } header: {
                Text("Sessions")
            } footer: {
                Text("Matched against the session's folder path, e.g. “mac-buddy”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Claude Code") {
                    if connected {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not connected", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
                Button(connected ? "Disconnect from Claude Code" : "Connect to Claude Code") {
                    do {
                        if connected { try ClaudeHooks.disconnect() } else { try ClaudeHooks.connect() }
                        hookError = nil
                    } catch {
                        hookError = error.localizedDescription
                    }
                    connected = ClaudeHooks.isConnected
                }
                if let hookError {
                    Text(hookError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Adds or removes Mac Buddy's hooks in ~/.claude/settings.json. Restart open Claude Code sessions afterwards.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var status: String {
        switch model.mood {
        case .working:
            return model.projects.isEmpty ? "Working" : "Working on \(model.projects.joined(separator: ", "))"
        case .attention: return "Waiting for your permission"
        case .done: return "Just finished"
        case .sleeping: return "Asleep"
        case .idle: return "Idle"
        }
    }
}

// MARK: - Helpers

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

@MainActor
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}
