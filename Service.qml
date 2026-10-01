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
  property string lastError: ""
  property string actionStatus: ""
  property bool refreshing: false

  readonly property bool running: active > 0
  readonly property bool busy: statusProcess.running || actionProcess.running || pickProcess.running
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

  function act(args, statusText) {
    if (actionProcess.running) return
    actionStatus = statusText || ""
    lastError = ""
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
    lastError = ""
    actionStatus = "Choose a video for " + monitor + "…"
    pickProcess.command = [root.helper, "pick", monitor]
    pickProcess.running = true
  }

  function clearFor(monitor) {
    act(["clear", monitor], "Clearing " + monitor + "…")
  }

  function applyStatus(raw) {
    var data = null
    try { data = JSON.parse(raw) } catch (e) { data = null }
    if (!data || !Array.isArray(data.monitors)) {
      lastError = "wallpaper-video status returned no data"
      return
    }
    monitors = data.monitors
    active = Number(data.active || 0)
    total = Number(data.total || 0)
    lastError = ""
  }

  function elideError(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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
      if (exitCode === 0) root.applyStatus(String(statusStdout.text || ""))
      else root.lastError = root.elideError(String(statusStderr.text || "") || "Could not read wallpaper status")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stderr = String(actionStderr.text || "").trim()
      if (exitCode !== 0) {
        root.lastError = root.elideError(stderr || "wallpaper-video exited with " + exitCode)
        root.actionStatus = ""
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = String(root.actionStatus || "")
        actionStatusTimer.restart()
      }
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
      // zenity exits 1 when the dialog is cancelled — that is not an error.
      var stderr = String(pickStderr.text || "").trim()
      if (exitCode !== 0 && exitCode !== 1)
        root.lastError = root.elideError(stderr || "The file picker could not complete")
      root.actionStatus = ""
      actionStatusTimer.stop()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
