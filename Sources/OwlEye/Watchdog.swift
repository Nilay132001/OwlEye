import Foundation

/// Runs as root through `sudo` (Touch ID or password, every session). It turns lid-sleep off, then
/// checks every second and turns it back on the moment any stop condition is met.
/// Because it watches the app's PID, a crash or force-quit still restores sleep, and a
/// trap restores it if the watchdog itself is interrupted or terminated.
enum Watchdog {
    struct Options {
        var appPID: Int32
        var deadline: Int        // Unix seconds; 0 = no timer
        var stopFile: String
        var logFile: String
        var stopOnUnplug: Bool
        var minBattery: Int      // 0 = no battery floor
    }

    static func script(_ o: Options) -> String {
        """
        APP_PID=\(o.appPID)
        DEADLINE=\(o.deadline)
        STOP_FILE=\(quoted(o.stopFile))
        LOG_FILE=\(quoted(o.logFile))
        STOP_ON_UNPLUG=\(o.stopOnUnplug ? 1 : 0)
        MIN_BATTERY=\(o.minBattery)

        log() { echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog[$$]: $*" >> "$LOG_FILE"; }
        restore() {
          /usr/bin/pmset -a disablesleep 0 && log "sleep restored ($1)" || log "FAILED to restore sleep ($1)"
          rm -f "$STOP_FILE"
        }
        trap 'restore "signal"; exit 0' HUP INT TERM

        rm -f "$STOP_FILE"
        /usr/bin/pmset -a disablesleep 1 && log "sleep disabled (deadline=$DEADLINE app=$APP_PID)"
        REASON=""
        TICK=0
        while [ -z "$REASON" ]; do
          sleep 1
          TICK=$((TICK + 1))
          kill -0 "$APP_PID" 2>/dev/null || { REASON="app exited"; break; }
          [ -e "$STOP_FILE" ] && { REASON="stop pressed"; break; }
          if [ "$DEADLINE" -gt 0 ] && [ "$(date +%s)" -ge "$DEADLINE" ]; then REASON="timer ended"; break; fi
          # Power checks spawn pmset, so run them every 5 seconds rather than every tick.
          [ $((TICK % 5)) -eq 0 ] || continue
          BATT="$(/usr/bin/pmset -g batt)"
          case "$BATT" in
            *"'Battery Power'"*)
              [ "$STOP_ON_UNPLUG" -eq 1 ] && REASON="charger unplugged"
              PCT="$(echo "$BATT" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
              if [ "$MIN_BATTERY" -gt 0 ] && [ -n "$PCT" ] && [ "$PCT" -lt "$MIN_BATTERY" ]; then REASON="battery below $MIN_BATTERY%"; fi
              ;;
          esac
        done
        restore "$REASON"
        """
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Restores normal sleep immediately (used when sleep was left disabled).
    static let restoreCommand = ["/usr/bin/pmset", "-a", "disablesleep", "0"]
}
