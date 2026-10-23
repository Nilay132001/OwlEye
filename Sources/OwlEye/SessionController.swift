import AppKit
import Foundation

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var isStarting = false
    @Published var message: String?
    @Published private(set) var now = Date()

    private var ownsSession = false
    private var ticker: Timer?

    private let stopFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OwlEye", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stop")
    }()

    init() {
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestStop() }
        }
        // If sleep is still disabled after an old watchdog has had time to notice its
        // app is gone (it polls every 5 s), something was left behind: fix it.
        if Self.sleepDisabled() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, !self.ownsSession, Self.sleepDisabled() else { return }
                self.message = "Sleep was left disabled. Restoring…"
                self.restoreNow()
            }
        }
    }

    var remainingText: String? {
        guard isActive, ownsSession else { return nil }
        guard let endDate else { return "∞" }
        let seconds = max(0, Int(endDate.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(max(m, 1))m"
    }

    func start(duration: TimeInterval?, stopOnUnplug: Bool, minBattery: Int) {
        guard !isActive, !isStarting else { return }
        let end = duration.map { Date().addingTimeInterval($0) }
        let options = Watchdog.Options(
            appPID: ProcessInfo.processInfo.processIdentifier,
            deadline: end.map { Int($0.timeIntervalSince1970) } ?? 0,
            stopFile: stopFile.path,
            stopOnUnplug: stopOnUnplug,
            minBattery: minBattery
        )
        if stopOnUnplug && Self.onBattery() {
            message = "Plug in the charger first, or turn off \"Stop if unplugged\"."
            return
        }
        try? FileManager.default.removeItem(at: stopFile)
        isStarting = true
        message = "Touch ID or password…"
        let started = runPrivileged(["/bin/sh", "-c", Watchdog.script(options)]) { [weak self] status in
            // The watchdog exits when the session ends; before that, an exit means sudo refused.
            guard let self, self.isStarting else { return }
            self.isStarting = false
            self.message = status == 0 ? nil : "Not authorised (cancelled or wrong password)."
            self.refresh()
        }
        guard started else {
            isStarting = false
            return
        }
        waitForSleepDisabled(until: Date().addingTimeInterval(120), end: end)
    }

    /// Polls until the watchdog has run `pmset -a disablesleep 1`, which happens only
    /// after sudo accepted Touch ID or the password.
    private func waitForSleepDisabled(until deadline: Date, end: Date?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isStarting else { return }
            if Self.sleepDisabled() {
                self.isStarting = false
                self.ownsSession = true
                self.endDate = end
                self.message = nil
                self.refresh()
            } else if Date() < deadline {
                self.waitForSleepDisabled(until: deadline, end: end)
            } else {
                self.isStarting = false
                self.message = "Timed out waiting for authorisation."
            }
        }
    }

    /// Asks the watchdog to restore sleep. No password needed: it polls for this file.
    func requestStop() {
        FileManager.default.createFile(atPath: stopFile.path, contents: nil)
        message = isActive ? "Stopping…" : nil
    }

    func restoreNow() {
        _ = runPrivileged(Watchdog.restoreCommand) { [weak self] status in
            self?.message = status == 0 ? nil : "Could not restore sleep. Run: sudo pmset -a disablesleep 0"
            self?.refresh()
        }
    }

    private func refresh() {
        now = Date()
        let active = Self.sleepDisabled()
        if isActive && !active {
            ownsSession = false
            endDate = nil
            if message == "Stopping…" { message = nil }
        }
        isActive = active
    }

    /// Runs a command as root with `sudo -k -A`. `-k` ignores any cached sudo login, so
    /// every call asks again: Touch ID if it is enabled for sudo, otherwise (or if
    /// cancelled) the password dialog in askpass.sh. Nothing is added to sudoers.
    private func runPrivileged(_ command: [String], onExit: @escaping @MainActor (Int32) -> Void) -> Bool {
        guard let askpass = Bundle.main.url(forResource: "askpass", withExtension: "sh") else {
            message = "askpass.sh is missing from the app bundle. Rebuild with ./build.sh."
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-k", "-A", "-p", "OwlEye needs your password to keep the Mac awake:"] + command
        var environment = ProcessInfo.processInfo.environment
        environment["SUDO_ASKPASS"] = askpass.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in onExit(status) }
        }
        do {
            try process.run()
            return true
        } catch {
            message = "Could not run sudo: \(error.localizedDescription)"
            return false
        }
    }

    static func sleepDisabled() -> Bool {
        shell("/usr/bin/pmset", ["-g"]).range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    static func onBattery() -> Bool {
        shell("/usr/bin/pmset", ["-g", "batt"]).contains("'Battery Power'")
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
