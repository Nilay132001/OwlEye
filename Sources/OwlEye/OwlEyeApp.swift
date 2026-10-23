import SwiftUI

@main
struct OwlEyeApp: App {
    @StateObject private var session = SessionController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(session: session)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: session.isActive ? "eye.fill" : "eye")
                if let remaining = session.remainingText {
                    Text(remaining)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var session: SessionController
    @AppStorage("stopOnUnplug") private var stopOnUnplug = true
    @AppStorage("stopOnLowBattery") private var stopOnLowBattery = true
    // @AppStorage, not @State: on the macOS 27 SDK @State is a macro whose plugin
    // ships only with full Xcode, so it fails to build with the Command Line Tools.
    @AppStorage("customHours") private var customHours = 3
    @AppStorage("customMinutes") private var customMinutes = 0

    private let presets: [(String, TimeInterval?)] = [
        ("1h", 3600), ("2h", 7200), ("4h", 14_400), ("8h", 28_800), ("Until I stop", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if session.isActive {
                Button(role: .destructive) {
                    session.requestStop()
                } label: {
                    Label("Stop and allow sleep", systemImage: "moon.zzz")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                presetButtons
                customRow
            }

            Divider()

            Toggle("Stop if unplugged", isOn: $stopOnUnplug)
            Toggle("Stop below 20% battery", isOn: $stopOnLowBattery)
                .disabled(stopOnUnplug)
                .help("Only matters on battery, so it applies when \"Stop if unplugged\" is off.")

            if let message = session.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit OwlEye") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: 280)
        .disabled(session.isStarting)
    }

    private var header: some View {
        HStack {
            Image(systemName: session.isActive ? "eye.fill" : "eye")
                .font(.title2)
                .foregroundStyle(session.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.isActive ? "Staying awake" : "Normal sleep")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if session.isStarting { return "Starting…" }
        guard session.isActive else { return "Pick how long to stay awake with the lid closed" }
        if let remaining = session.remainingText {
            return remaining == "∞" ? "Until you stop it" : "\(remaining) left"
        }
        return "Sleep is disabled"
    }

    private var presetButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(presets, id: \.0) { title, duration in
                Button {
                    start(duration)
                } label: {
                    Text(title).frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
        }
    }

    private var customRow: some View {
        HStack {
            Stepper("\(customHours)h", value: $customHours, in: 0...48)
            Stepper("\(customMinutes)m", value: $customMinutes, in: 0...55, step: 5)
            Spacer()
            Button("Start") {
                start(TimeInterval(customHours * 3600 + customMinutes * 60))
            }
            .disabled(customHours == 0 && customMinutes == 0)
        }
        .controlSize(.regular)
    }

    private func start(_ duration: TimeInterval?) {
        session.start(
            duration: duration,
            stopOnUnplug: stopOnUnplug,
            minBattery: stopOnLowBattery ? 20 : 0
        )
    }
}
