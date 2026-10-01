import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Runs bin/wallpaper-video and mirrors its status for the panel. All process
// management (mpvpaper pids, assignments) lives in the bash helper; this item
// only translates commands into state the UI can render.
Item {
  id: root

  property var settings: ({})

  readonly property string helper: Qt.resolvedUrl("bin/wallpaper-video").toString().replace(/^file:\/\//, "")

  property var monitors: []
  property int active: 0
  property int total: 0
  property string mode: "video"
  // Two separate error channels: a failed action must survive the status
  // refresh that follows it, while a failed refresh is cleared by the next
  // successful one. lastError/lastHint are the views the panel renders.
  property string actionError: ""
  property string actionHint: ""
  property string statusError: ""
  property string statusHint: ""
  property string actionStatus: ""
  property bool refreshing: false

  readonly property string lastError: actionError !== "" ? actionError : statusError
  readonly property string lastHint: actionHint !== "" ? actionHint : statusHint
  readonly property bool running: active > 0
  readonly property bool busy: actionProcess.running || pickProcess.running
  readonly property int configuredCount: {
    var n = 0
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].video) n++
    return n
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (statusProcess.running) return
    refreshing = true
    statusProcess.command = [root.helper, "status", "--json"]
    statusProcess.running = true
  }

  function syncBackground() {
    if (syncProcess.running || statusProcess.running || actionProcess.running || pickProcess.running) return
    syncProcess.command = [root.helper, "reconcile"]
    syncProcess.running = true
  }

  function act(args, statusText) {
    if (actionProcess.running) return
    actionStatus = statusText || ""
    actionError = ""
    actionHint = ""
    actionProcess.command = [root.helper].concat(args)
    actionProcess.running = true
  }

  function toggle() { act(["toggle"], "Toggling wallpaper…") }
  function startAll() { act(["start"], "Starting wallpaper…") }
  function stopAll() { act(["stop"], "Stopping wallpaper…") }

  function toggleMonitor(monitor, turnOn) {
    act([turnOn ? "start" : "stop", monitor],
      (turnOn ? "Starting " : "Stopping ") + monitor + "…")
  }

  function pickFor(monitor) {
    if (pickProcess.running) return
    actionError = ""
    actionHint = ""
    actionStatus = "Choose a video for " + monitor + "…"
    pickProcess.command = [root.helper, "pick", monitor]
    pickProcess.running = true
  }

  function pickImage() {
    if (pickProcess.running) return
    actionError = ""
    actionHint = ""
    actionStatus = "Choose a static wallpaper…"
    pickProcess.command = [root.helper, "image"]
    pickProcess.running = true
  }

  function pickWallpaper(monitor) {
    if (pickProcess.running) return
    actionError = ""
    actionHint = ""
    actionStatus = "Choose a wallpaper for " + monitor + "…"
    pickProcess.command = [root.helper, "wallpaper", monitor]
    pickProcess.running = true
  }

  function setLayout(monitor, layout) {
    act(["layout", monitor, layout], "Setting " + monitor + " to " + layout + "…")
  }

  function clearFor(monitor) {
    act(["clear", monitor], "Clearing " + monitor + "…")
  }

  function clearError() {
    actionError = ""
    actionHint = ""
    statusError = ""
    statusHint = ""
  }

  function applyStatus(raw) {
    var data = null
    try { data = JSON.parse(raw) } catch (e) { data = null }
    if (!data || !Array.isArray(data.monitors)) {
      statusError = "Could not read the wallpaper status"
      statusHint = "Choose Refresh in the panel to try again."
      return
    }
    monitors = data.monitors
    active = Number(data.active || 0)
    total = Number(data.total || 0)
    mode = String(data.mode || "video")
    statusError = ""
    statusHint = ""
  }

  function elideError(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  // Failures the engine reports the way a developer would, rewritten the way
  // a user would read them — each with the step that fixes it. The engine's
  // own `hint:` line wins whenever it sent one; this is the fallback for the
  // die() paths that only ever print one line.
  function friendlyFor(text) {
    var t = String(text || "").toLowerCase()
    var rules = [
      ["unknown monitor",
        "That monitor is no longer available",
        "Refresh the panel to see the monitors that are connected now."],
      ["no video is assigned",
        "No video is assigned to this monitor",
        "Pick a video for it, or Clear the assignment."],
      ["missing or unreadable",
        "The saved video file is missing or unreadable",
        "Pick a new video for this monitor, or Clear the assignment."],
      ["does not exist or is not readable",
        "The selected file is missing or unreadable",
        "Pick a different video file."],
      ["not a supported video",
        "That file is not a supported video",
        "Choose an MP4, WebM, MKV, AVI, MOV, or GIF file."],
      ["choose an mp4",
        "That file is not a supported video",
        "Choose an MP4, WebM, MKV, AVI, MOV, or GIF file."],
      ["mpvpaper is not installed",
        "mpvpaper is not installed",
        "Install it with: yay -S mpvpaper"],
      ["zenity is not installed",
        "The file picker is not installed (zenity)",
        "Install it with: sudo pacman -S zenity"],
      ["python3 is not installed",
        "python3 is not installed",
        "Install it with: sudo pacman -S python"],
      ["mpvpaper could not start",
        "mpvpaper could not play this file",
        "Check the file opens in a video player, then Pick it again."],
      ["mpvpaper failed",
        "mpvpaper could not play this file",
        "Check the file opens in a video player, then Pick it again."],
      ["hyprctl",
        "Your monitors could not be listed",
        "Hyprland has to be running before the panel can show your screens."]
    ]
    for (var i = 0; i < rules.length; i++)
      if (t.indexOf(rules[i][0]) !== -1)
        return { message: rules[i][1], hint: rules[i][2] }
    return { message: "", hint: "" }
  }

  // One shape for every failed command: the first stderr line is the
  // headline, any `hint:` line is the way out, and anything else falls back
  // to friendlyFor(). The panel shows the message with the hint under it.
  function parseFailure(raw, exitCode, fallback) {
    var text = String(raw || "").replace(/\r/g, "").replace(/[ \t]+$/, "")
    text = text.replace(/^\n+|\n+$/g, "")
    if (text === "")
      return { message: elideError(fallback || "wallpaper-video exited with " + exitCode), hint: "" }

    var lines = text.split("\n")
    var message = lines[0].replace(/^\s*wallpaper-video:\s*/, "").trim()
    var hint = ""
    for (var i = 1; i < lines.length; i++) {
      var match = /^\s*hint:\s*(.+)$/.exec(lines[i])
      if (match) { hint = match[1].trim(); break }
    }

    var friendly = friendlyFor(text)
    if (lines.length === 1 && friendly.message !== "") message = friendly.message
    if (hint === "" && friendly.hint !== "") hint = friendly.hint

    return { message: elideError(message), hint: elideError(hint) }
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.syncBackground()
  }

  Timer {
    // Actions settle quickly, but mpvpaper takes a moment to come up or go
    // down — re-poll a few times so the icon and panel track reality instead
    // of waiting for the next periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 800
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 5) {
        settleTimer.ticks = 0
        settleTimer.running = false
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) {
        root.applyStatus(String(statusStdout.text || ""))
      } else {
        var failure = root.parseFailure(String(statusStderr.text || ""), exitCode, "Could not read the wallpaper status")
        root.statusError = failure.message
        root.statusHint = failure.hint
      }
    }
  }

  Process {
    id: syncProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var failure = root.parseFailure(String(actionStderr.text || ""), exitCode, "wallpaper-video exited with " + exitCode)
        root.actionError = failure.message
        root.actionHint = failure.hint
        root.actionStatus = ""
      } else {
        root.actionError = ""
        root.actionHint = ""
        root.actionStatus = String(root.actionStatus || "")
      }
      actionStatusTimer.restart()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: pickProcess
    running: false
    command: []
    stdout: StdioCollector { id: pickStdout; waitForEnd: true }
    stderr: StdioCollector { id: pickStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // The helper already folds a cancelled zenity dialog into exit 0, so any
      // non-zero code here is a real failure — treating 1 as "cancelled" would
      // swallow every die() the picker path can report (unknown monitor,
      // missing zenity, unreadable file).
      if (exitCode !== 0) {
        var failure = root.parseFailure(String(pickStderr.text || ""), exitCode, "The file picker could not complete")
        root.actionError = failure.message
        root.actionHint = failure.hint
      }
      root.actionStatus = ""
      actionStatusTimer.stop()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
