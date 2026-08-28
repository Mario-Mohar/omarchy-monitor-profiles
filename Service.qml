import QtQuick
import Quickshell
import Quickshell.Io

// Owns everything the widget knows about monitor profiles. All of it comes from
// bin/monitor-profiles, which is also what Hyprland's config calls -- one code
// path decides what "active" means, so the bar can never disagree with what is
// actually on screen.
//
// Applying a profile is deliberately indirect: the helper writes `active` and
// runs `hyprctl reload`, and the Lua loader in monitors.lua puts the screens
// where they belong. That is why a profile survives a relogin.
Item {
  id: root

  property var settings: ({})

  // One entry per profile: {id, name, icon, match, monitors, matches, configured}
  property var profiles: []
  property string active: "auto"        // "auto" or a profile id
  property string effectiveId: ""       // what is on screen now
  property string autoId: ""            // what auto would pick
  property var connected: []            // connector names the kernel reports
  property string configPath: ""
  property string error: ""
  property bool everLoaded: false

  readonly property bool busy: useProcess.running || captureProcess.running
  readonly property bool isAuto: active === "auto"

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 300)

  function intSetting(name, fallback, min, max) {
    var v = parseInt(settings ? settings[name] : undefined, 10)
    if (isNaN(v)) return fallback
    return Math.max(min, Math.min(max, v))
  }

  function boolSetting(name, fallback) {
    var v = settings ? settings[name] : undefined
    if (v === undefined || v === null) return fallback
    return v === true || String(v).toLowerCase() === "true" || String(v) === "1"
  }

  function scriptPath() {
    return String(Qt.resolvedUrl("bin/monitor-profiles")).replace(/^file:\/\//, "")
  }

  function profileById(id) {
    for (var i = 0; i < profiles.length; i++)
      if (profiles[i].id === id) return profiles[i]
    return null
  }

  readonly property var effectiveProfile: profileById(effectiveId)

  // Profiles that actually hold an arrangement. Cycling through empty slots
  // from the bar would just look broken.
  readonly property var configuredProfiles: {
    var out = []
    for (var i = 0; i < profiles.length; i++)
      if (profiles[i].configured) out.push(profiles[i])
    return out
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [scriptPath(), "status"]
    statusProcess.running = true
  }

  function use(id) {
    if (busy || !id) return
    useProcess.command = [scriptPath(), "use", String(id)]
    useProcess.running = true
  }

  function capture(id) {
    if (busy || !id) return
    captureProcess.command = [scriptPath(), "capture", String(id)]
    captureProcess.running = true
  }

  // Middle click and wheel walk the configured profiles without opening the
  // panel. Auto counts as one more stop on the way round.
  function cycle(step) {
    var list = configuredProfiles
    if (!list.length) return
    var stops = [null].concat(list)          // null == auto
    var current = 0
    if (!isAuto) {
      for (var i = 0; i < list.length; i++)
        if (list[i].id === active) current = i + 1
    }
    var next = (current + step + stops.length) % stops.length
    use(stops[next] === null ? "auto" : stops[next].id)
  }

  function editConfig() {
    if (configPath === "") return
    Quickshell.execDetached(["omarchy-launch-editor", configPath])
  }

  function apply(text) {
    var payload
    try {
      payload = JSON.parse(text)
    } catch (e) {
      root.error = "monitor-profiles returned unparseable output"
      root.everLoaded = true
      return
    }
    root.everLoaded = true
    root.error = ""
    root.configPath = String(payload.configPath || "")
    root.active = String(payload.active || "auto")
    root.effectiveId = String(payload.effectiveId || "")
    root.autoId = String(payload.autoId || "")
    root.connected = Array.isArray(payload.connected) ? payload.connected : []
    root.profiles = Array.isArray(payload.profiles) ? payload.profiles : []
  }

  // A StdioCollector buffers the whole of a helper's output before anything
  // looks at it, so a helper gone wrong could grow that buffer without limit.
  // The cap is this side of that rule; the watchdogs cover a helper that never
  // exits at all.
  readonly property int maxStdoutChars: 128 * 1024
  readonly property int watchdogMs: 30000

  function takeOutput(collector, what) {
    var text = String(collector.text || "")
    if (text.length > root.maxStdoutChars) {
      console.warn("monitor-profiles: " + what + " produced "
                   + text.length + " characters, discarding")
      return ""
    }
    return text
  }

  Timer {
    id: statusWatchdog
    interval: root.watchdogMs
    onTriggered: { statusProcess.signal(15); root.error = "reading the profiles timed out" }
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    onRunningChanged: running ? statusWatchdog.restart() : statusWatchdog.stop()
    onExited: function (exitCode) {
      if (exitCode === 0) root.apply(root.takeOutput(statusStdout, "status"))
      else {
        root.error = "monitor-profiles status failed (exit " + exitCode + ")"
        root.everLoaded = true
      }
    }
  }

  Timer {
    id: useWatchdog
    // Longer than the others: this one waits on `hyprctl reload`.
    interval: root.watchdogMs
    onTriggered: { useProcess.signal(15); root.error = "switching the profile timed out" }
  }

  Process {
    id: useProcess
    command: []
    stderr: StdioCollector { id: useStderr; waitForEnd: true }
    onRunningChanged: running ? useWatchdog.restart() : useWatchdog.stop()
    onExited: function (exitCode) {
      root.error = exitCode === 0 ? ""
        : (String(useStderr.text || "").trim() || "could not switch profile")
      // Hyprland needs a moment to settle after a reload before hyprctl and
      // /sys agree again on what is on screen.
      settle.restart()
    }
  }

  Timer {
    id: captureWatchdog
    interval: root.watchdogMs
    onTriggered: { captureProcess.signal(15); root.error = "capturing the arrangement timed out" }
  }

  Process {
    id: captureProcess
    command: []
    stderr: StdioCollector { id: captureStderr; waitForEnd: true }
    onRunningChanged: running ? captureWatchdog.restart() : captureWatchdog.stop()
    onExited: function (exitCode) {
      root.error = exitCode === 0 ? ""
        : (String(captureStderr.text || "").trim() || "could not capture the arrangement")
      root.refresh()
    }
  }

  Timer {
    id: settle
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 800
    repeat: false
    running: true
    onTriggered: root.refresh()
  }

  // Plugging a monitor in or out changes what auto resolves to, and waiting up
  // to refreshIntervalSec to notice would make the widget look asleep at the
  // one moment it matters.
  Connections {
    target: Quickshell
    function onScreensChanged() { settle.restart() }
  }

  // profiles.json is meant to be hand-edited too, so pick up changes without
  // waiting for the next poll. The path comes from the helper rather than being
  // rebuilt here, because XDG_CONFIG_HOME may point somewhere other than
  // ~/.config and the two must not disagree about which file is the real one.
  FileView {
    path: root.configPath !== "" ? root.configPath
      : Quickshell.env("HOME") + "/.config/omarchy/monitor-profiles/profiles.json"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }
}
