import AppKit
import Foundation

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var isStarting = false
    @Published var message: String?
    @Published private(set) var now = Date()

    /// The root watchdog for the current session (`sudo` → `sh`), while it runs.
    private var watchdog: Process?
    private var ticker: Timer?

    private var ownsSession: Bool { watchdog?.isRunning == true }

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
        // On quit, only signal our own watchdog (it would notice the app is gone within a
        // second anyway). Never start a Touch ID prompt while the app is closing.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.ownsSession else { return }
                FileManager.default.createFile(atPath: self.stopFile.path, contents: nil)
            }
        }
        // An old watchdog notices within a second that its app is gone. If sleep is
        // still disabled after that, something was left behind: fix it.
        refresh()
        if Self.sleepDisabled() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
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
        launchWatchdog(["/bin/sh", "-c", Watchdog.script(options)], withPassword: false)
        guard watchdog != nil else {
            isStarting = false
            return
        }
        waitForSleepDisabled(end: end)
    }

    /// Tries Touch ID first; if that is cancelled or unavailable, asks again with the
    /// password dialog.
    private func launchWatchdog(_ command: [String], withPassword: Bool) {
        message = withPassword ? "Enter your password…" : "Touch ID…"
        watchdog = runPrivileged(command, withPassword: withPassword) { [weak self] status in
            guard let self else { return }
            // Before sleep was disabled, an exit means sudo refused; after, the session ended.
            if self.isStarting && status != 0 && !withPassword {
                self.launchWatchdog(command, withPassword: true)
                return
            }
            if self.isStarting {
                self.isStarting = false
                self.message = status == 0 ? nil : "Not authorised (cancelled or wrong password)."
            }
            // The root watchdog never touches your files, so the app cleans up after it.
            try? FileManager.default.removeItem(at: self.stopFile)
            self.watchdog = nil
            self.endDate = nil
            self.refresh()
        }
    }

    /// Polls until the watchdog has run `pmset -a disablesleep 1`, which happens only
    /// after sudo accepted Touch ID or the password. No timeout: while sudo is still
    /// waiting for you, the session may yet start; if sudo gives up, its exit handler
    /// ends the wait.
    private func waitForSleepDisabled(end: Date?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isStarting else { return }
            if self.ownsSession && Self.sleepDisabled() {
                self.isStarting = false
                self.endDate = end
                self.message = nil
                self.refresh()
            } else {
                self.waitForSleepDisabled(end: end)
            }
        }
    }

    /// Ends the session. With our watchdog running this needs no password: it checks for
    /// the stop file every second. If sleep was disabled by anything else, restore it
    /// directly (Touch ID or password).
    func requestStop() {
        if ownsSession {
            FileManager.default.createFile(atPath: stopFile.path, contents: nil)
            message = "Stopping…"
        } else if Self.sleepDisabled() {
            message = "Restoring sleep…"
            restoreNow()
        }
    }

    func restoreNow(withPassword: Bool = false) {
        runPrivileged(Watchdog.restoreCommand, withPassword: withPassword) { [weak self] status in
            guard let self else { return }
            if status != 0 && !withPassword {
                self.restoreNow(withPassword: true)
                return
            }
            self.message = status == 0 ? nil : "Could not restore sleep. Run: sudo pmset -a disablesleep 0"
            self.refresh()
        }
    }

    private func refresh() {
        now = Date()
        let active = Self.sleepDisabled()
        if isActive && !active {
            endDate = nil
            if message == "Stopping…" || message == "Restoring sleep…" { message = nil }
        }
        isActive = active
    }

    /// Runs a command as root with `sudo -k`. `-k` ignores any cached sudo login, so every
    /// call asks again. Nothing is added to sudoers.
    ///
    /// - `withPassword: false` → plain `sudo`: Touch ID if it is enabled for sudo. With no
    ///   terminal attached, sudo exits at once if Touch ID is cancelled or unavailable.
    /// - `withPassword: true` → `sudo -A`: the password dialog in askpass.sh. `-A` turns
    ///   Touch ID off, which is why it is only the fallback.
    @discardableResult
    private func runPrivileged(
        _ command: [String], withPassword: Bool, onExit: @escaping @MainActor (Int32) -> Void
    ) -> Process? {
        var environment = ProcessInfo.processInfo.environment
        var flags = ["-k"]
        if withPassword {
            guard let askpass = Bundle.main.url(forResource: "askpass", withExtension: "sh") else {
                message = "askpass.sh is missing from the app bundle. Rebuild with ./build.sh."
                return nil
            }
            environment["SUDO_ASKPASS"] = askpass.path
            flags += ["-A", "-p", "OwlEye needs your password to keep the Mac awake:"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = flags + command
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
            return process
        } catch {
            message = "Could not run sudo: \(error.localizedDescription)"
            return nil
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
