// The app is iOS-only (per the plan: native SwiftUI, App Store, iOS APIs
// throughout). The screens are fenced off so `swift build` on macOS still
// checks the design system and the model layer, which are portable.
#if os(iOS)
import SwiftUI
import DesignSystem

/// Settings, as a third root destination in the bottom bar beside Home and
/// Schedule.
///
/// Deliberately short. Every switch here is one the app's behaviour actually
/// hinges on (when it pushes, how loudly it asks for review); anything that
/// would only be a preference for its own sake stays out.
struct SettingsView: View {
    @AppStorage("dailyDigestEnabled") private var dailyDigestEnabled = true
    @AppStorage("dailyDigestHour") private var dailyDigestHour = 8
    @AppStorage("followUpNudges") private var followUpNudges = true
    @AppStorage("quietHoursEnabled") private var quietHoursEnabled = true
    @AppStorage("reviewFirst") private var reviewFirst = false
    @AppStorage("transcribeOnDevice") private var transcribeOnDevice = true
    /// Bound to the same key `dsAppearance()` reads at the app's root, so the
    /// switch and the ground it changes are never two sources of truth.
    @AppStorage(DSAppearance.storageKey) private var darkMode = false

    var body: some View {
        List {
            // First, and on its own: it changes the screen you are looking at
            // while you look at it, so it wants to be the thing you land on
            // rather than something found under the notification switches.
            Section {
                Toggle("Dark mode", isOn: $darkMode.animation(.easeInOut(duration: 0.2)))
                    .dsSwitchTint()
            } header: {
                Text("Appearance")
            } footer: {
                Text("Swaps the app's ground for the dark palette. The phone's own setting is left alone.")
            }

            Section {
                Toggle("Morning digest", isOn: $dailyDigestEnabled)
                    .dsSwitchTint()
                if dailyDigestEnabled {
                    Picker("Send at", selection: $dailyDigestHour) {
                        ForEach(5..<13) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                }
            } header: {
                Text("Daily digest")
            } footer: {
                Text("One push a day with what's due and what's been sitting. Everything else stays quiet.")
            }

            Section("Nudges") {
                Toggle("Follow-up reminders", isOn: $followUpNudges)
                    .dsSwitchTint()
                Toggle("Respect quiet hours", isOn: $quietHoursEnabled)
                    .dsSwitchTint()
            }

            Section {
                Toggle("Show \"needs review\" first", isOn: $reviewFirst)
                    .dsSwitchTint()
            } header: {
                Text("Review")
            } footer: {
                Text("Items the AI wasn't sure about jump to the top of Home instead of sitting in date order.")
            }

            Section {
                Toggle("Transcribe on device", isOn: $transcribeOnDevice)
                    .dsSwitchTint()
            } header: {
                Text("Capture")
            } footer: {
                Text("On-device dictation never leaves the phone. Turn this off to send longer or messier audio to the cloud for a better transcript.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        // No title: the section headers name everything on the screen, and
        // the navigation bar stays hidden here as it is on every other root.
        .toolbar(.hidden, for: .navigationBar)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#endif
