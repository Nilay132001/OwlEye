import Foundation

/// Runs as root through `sudo` (Touch ID or password, every session). It turns lid-sleep off, then
/// polls every 5 seconds and turns it back on the moment any stop condition is met.
/// Because it watches the app's PID, a crash or force-quit still restores sleep.
enum Watchdog {
    struct Options {
        var appPID: Int32
        var deadline: Int        // Unix seconds; 0 = no timer
        var stopFile: String
        var stopOnUnplug: Bool
        var minBattery: Int      // 0 = no battery floor
    }

    static func script(_ o: Options) -> String {
        """
        APP_PID=\(o.appPID)
        DEADLINE=\(o.deadline)
        STOP_FILE='\(o.stopFile.replacingOccurrences(of: "'", with: "'\\''"))'
        STOP_ON_UNPLUG=\(o.stopOnUnplug ? 1 : 0)
        MIN_BATTERY=\(o.minBattery)

        rm -f "$STOP_FILE"
        /usr/bin/pmset -a disablesleep 1
        while :; do
          sleep 5
          kill -0 "$APP_PID" 2>/dev/null || break
          [ -e "$STOP_FILE" ] && break
          if [ "$DEADLINE" -gt 0 ] && [ "$(date +%s)" -ge "$DEADLINE" ]; then break; fi
          BATT="$(/usr/bin/pmset -g batt)"
          case "$BATT" in
            *"'Battery Power'"*)
              [ "$STOP_ON_UNPLUG" -eq 1 ] && break
              PCT="$(echo "$BATT" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
              if [ "$MIN_BATTERY" -gt 0 ] && [ -n "$PCT" ] && [ "$PCT" -lt "$MIN_BATTERY" ]; then break; fi
              ;;
          esac
        done
        /usr/bin/pmset -a disablesleep 0
        rm -f "$STOP_FILE"
        """
    }

    /// Restores normal sleep immediately (used when sleep was left disabled).
    static let restoreCommand = ["/usr/bin/pmset", "-a", "disablesleep", "0"]
}
