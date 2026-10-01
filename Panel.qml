import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar slot + popup panel for animated wallpapers. The heavy lifting (mpvpaper
// lifecycle, per-monitor assignments) lives in bin/wallpaper-video via
// Service.qml; this file is presentation only.
//
// Keyboard and mouse share one cursor model: every highlight comes from
// focusSection/selectedIndex/actionIndex, never from containsMouse. Hover
// writes the same state, so there is ever exactly one highlighted control.
Panel {
  id: root
  moduleName: "r4venward.wallpaper-video"
  ipcTarget: "r4venward.wallpaper-video"
  manageIpc: false

  // nf-md-video (U+F0567) as its surrogate pair: a private-use codepoint is
  // invisible in a diff and unreadable without a Nerd Font in the editor.
  readonly property string glyph: "\uDB81\uDD67"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------- shared keyboard/mouse cursor model
  property string focusSection: "header"
  property int selectedIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property var cursorItem: null

  readonly property bool showError: service.lastError !== ""
  readonly property bool showStatus: !showError && service.actionStatus !== ""
  readonly property bool showChooseCta: service.total > 0 && service.configuredCount === 0 && !showError

  // Top-level controls between the hero and the monitor list, in visual
  // order. They appear and disappear as state changes, so every index is
  // resolved through this array instead of being hard-coded.
  readonly property var globalActions: {
    var a = []
    if (showError) a.push("dismiss")
    if (showChooseCta) a.push("choose")
    a.push("image")
    a.push("refresh")
    return a
  }

  function globalStopIndex(action) { return globalActions.indexOf(action) }

  function monitorActionCount(monitor) { return monitor && monitor.video ? 3 : 1 }

  function setCursor(section, index, action) {
    if (index < 0) return
    cursorActive = true
    focusSection = section
    selectedIndex = index
    actionIndex = action === undefined ? 0 : action
    Qt.callLater(scrollCursorIntoView)
  }

  function headerHasCursor() { return cursorActive && focusSection === "header" }
  function globalHasCursor(action) {
    return cursorActive && focusSection === "global" && selectedIndex === globalStopIndex(action)
  }
  function monitorHasCursor(row, action) {
    return cursorActive && focusSection === "monitor" && selectedIndex === row && actionIndex === action
  }

  // Keeps the cursor inside what is actually rendered: a monitor can lose its
  // video (three actions become one) and the global row can change while a
  // message is up.
  function ensureCursor() {
    if (focusSection === "global") {
      if (globalActions.length === 0) { focusSection = "header"; selectedIndex = 0; actionIndex = 0; return }
      selectedIndex = Math.max(0, Math.min(selectedIndex, globalActions.length - 1))
      actionIndex = 0
      return
    }
    if (focusSection === "monitor") {
      if (service.monitors.length === 0) {
        focusSection = globalActions.length > 0 ? "global" : "header"
        selectedIndex = 0; actionIndex = 0; return
      }
      selectedIndex = Math.max(0, Math.min(selectedIndex, service.monitors.length - 1))
      actionIndex = Math.max(0, Math.min(actionIndex, monitorActionCount(service.monitors[selectedIndex]) - 1))
      return
    }
    focusSection = "header"
    selectedIndex = 0
    actionIndex = 0
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; ensureCursor(); return }
    if (delta === 0) return

    if (focusSection === "header") {
      if (delta > 0) {
        if (globalActions.length > 0) setCursor("global", 0)
        else if (service.monitors.length > 0) setCursor("monitor", 0, 0)
      }
      return
    }

    if (focusSection === "global") {
      var g = selectedIndex + delta
      if (g >= 0 && g < globalActions.length) { setCursor("global", g); return }
      if (delta > 0) { if (service.monitors.length > 0) setCursor("monitor", 0, 0); return }
      setCursor("header", 0)
      return
    }

    var m = selectedIndex + delta
    if (m >= 0 && m < service.monitors.length) {
      selectedIndex = m
      actionIndex = Math.min(actionIndex, monitorActionCount(service.monitors[m]) - 1)
      cursorActive = true
      Qt.callLater(scrollCursorIntoView)
      return
    }
    if (delta < 0) {
      if (globalActions.length > 0) setCursor("global", globalActions.length - 1)
      else setCursor("header", 0)
    }
  }

  function moveCursorH(delta) {
    if (!cursorActive) { cursorActive = true; ensureCursor(); return }
    if (delta === 0) return

    if (focusSection === "header") {
      if (delta > 0) {
        if (globalActions.length > 0) setCursor("global", 0)
        else if (service.monitors.length > 0) setCursor("monitor", 0, 0)
      }
      return
    }

    if (focusSection === "global") { moveCursor(delta); return }

    var count = monitorActionCount(service.monitors[selectedIndex])
    var a = actionIndex + delta
    if (a < 0 || a >= count) return
    actionIndex = a
    cursorActive = true
    Qt.callLater(scrollCursorIntoView)
  }

  function cursorStop() {
    if (focusSection === "header") return { kind: "header" }
    if (focusSection === "global") return { kind: "global", action: globalActions[selectedIndex] || "" }
    if (focusSection === "monitor") return { kind: "monitor", index: selectedIndex, action: actionIndex }
    return null
  }

  function activateCursor() {
    var stop = cursorStop()
    if (!stop) return
    if (stop.kind === "header") { service.toggle(); return }

    if (stop.kind === "global") {
      // Dismiss and Refresh must stay usable while a command runs — they are
      // how the user gets out of a wedged panel.
      if (stop.action === "dismiss") { service.clearError(); return }
      if (stop.action === "refresh") { service.refresh(); return }
      if (service.busy) return
      if (stop.action === "choose") service.pickFor("all")
      else if (stop.action === "image") service.pickImage()
      return
    }

    if (service.busy) return
    var monitor = service.monitors[stop.index]
    if (!monitor) return
    if (stop.action === 0) service.pickFor(monitor.name)
    else if (stop.action === 1) { if (monitor.available !== false) service.toggleMonitor(monitor.name, !monitor.running) }
    else if (stop.action === 2) service.clearFor(monitor.name)
  }

  function scrollCursorIntoView() {
    var item = cursorItem
    if (!item || !panelFlick) return
    if (panelFlick.contentHeight <= panelFlick.height) return
    // Viewport-relative deltas: correct whatever the content offset
    // convention, and it never fights Flickable's own bounds clamping.
    var mapped = item.mapToItem(panelFlick, 0, 0)
    var pad = Style.space(8)
    if (mapped.y < pad) panelFlick.contentY += mapped.y - pad
    else if (mapped.y + item.height > panelFlick.height - pad)
      panelFlick.contentY += mapped.y + item.height - panelFlick.height + pad
  }

  Connections {
    target: service
    function onMonitorsChanged() { Qt.callLater(root.ensureCursor) }
    function onLastErrorChanged() { Qt.callLater(root.ensureCursor) }
  }

  // ------------------------------------------------------------- status
  readonly property string labelMode: String(setting("barLabel", "Nothing"))
  readonly property string labelSuffix: {
    if ((bar && bar.vertical) || labelMode !== "Active monitors") return ""
    if (service.total === 0) return ""
    return " " + service.active + "/" + service.total
  }

  readonly property string tooltip: {
    var lines = []
    if (service.total === 0) lines.push("No monitors detected")
    else {
      for (var i = 0; i < service.monitors.length; i++) {
        var m = service.monitors[i]
        if (m.running) lines.push(m.name + ": " + (m.videoName || "video") + " (playing)")
        else if (m.video) lines.push(m.name + ": " + m.videoName + " (stopped)")
        else lines.push(m.name + ": no video")
      }
    }
    if (service.lastError !== "") lines.push("Error: " + service.lastError)
    lines.push("Left-click: toggle · Right-click: configure")
    return lines.join("\n")
  }

  readonly property string heroMeta: {
    if (service.lastError !== "") return "Needs attention"
    if (service.total === 0) return "No monitors detected"
    if (service.mode === "image") return "Static wallpaper"
    if (service.running) {
      var playing = ""
      for (var i = 0; i < service.monitors.length; i++) {
        if (service.monitors[i].running) { playing = service.monitors[i].videoName || "playing"; break }
      }
      return service.active + (service.active === 1 ? " monitor · " : " monitors · ") + playing
    }
    if (service.configuredCount > 0) return "Stopped"
    return "No videos configured"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.syncBackground()
    focusSection = "header"
    selectedIndex = 0
    actionIndex = 0
    cursorActive = false
    cursorItem = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
    function start(): string { service.startAll(); return "ok" }
    function stop(): string { service.stopAll(); return "ok" }
    function pick(monitor: string): string { service.pickFor(String(monitor || "all")); return "ok" }
    function image(): string { service.pickImage(); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph + root.labelSuffix
    tooltipText: root.tooltip
    // An error is a reason to look at the widget, so the bar says so.
    active: root.showError

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) service.refresh()
      else service.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") service.toggle()
        else if (t === "r" || t === "R") service.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Wallpaper"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: service.running ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.glyph
                color: service.running ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: headerSwitch
                checked: service.running
                busy: service.busy
                foreground: root.foreground
                hasCursor: root.headerHasCursor()
                onHovered: function(isHovered) { if (isHovered) root.setCursor("header", 0) }
                onHasCursorChanged: if (hasCursor) root.cursorItem = headerSwitch
                onToggled: service.toggle()
              }
            }
          }

          RowLayout {
            visible: root.showError || root.showStatus
            width: parent.width
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.showError ? service.lastError : service.actionStatus
              color: root.showError ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              id: dismissButton
              visible: root.showError
              text: "Dismiss"
              tooltipText: "Dismiss this message"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              hasCursor: root.globalHasCursor("dismiss")
              onHovered: function(isHovered) { if (isHovered) root.setCursor("global", root.globalStopIndex("dismiss")) }
              onHasCursorChanged: if (hasCursor) root.cursorItem = dismissButton
              onClicked: service.clearError()
            }
          }

          Button {
            id: ctaButton
            visible: root.showChooseCta
            width: parent.width
            text: "Choose video for a monitor…"
            tooltipText: "Pick one video and assign it to every monitor"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !service.busy
            hasCursor: root.globalHasCursor("choose")
            onHovered: function(isHovered) { if (isHovered) root.setCursor("global", root.globalStopIndex("choose")) }
            onHasCursorChanged: if (hasCursor) root.cursorItem = ctaButton
            onClicked: service.pickFor("all")
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: imageButton
              Layout.fillWidth: true
              text: "Static image…"
              tooltipText: "Apply an Omarchy background and stop active video layers"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !service.busy
              hasCursor: root.globalHasCursor("image")
              onHovered: function(isHovered) { if (isHovered) root.setCursor("global", root.globalStopIndex("image")) }
              onHasCursorChanged: if (hasCursor) root.cursorItem = imageButton
              onClicked: service.pickImage()
            }

            Button {
              id: refreshButton
              Layout.fillWidth: true
              text: "Refresh"
              tooltipText: "Re-read the current wallpaper state"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              hasCursor: root.globalHasCursor("refresh")
              onHovered: function(isHovered) { if (isHovered) root.setCursor("global", root.globalStopIndex("refresh")) }
              onHasCursorChanged: if (hasCursor) root.cursorItem = refreshButton
              onClicked: service.refresh()
            }
          }

          PanelSeparator {
            visible: service.total > 0
            foreground: root.foreground
          }

          Column {
            visible: service.total > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "MONITORS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: monitorColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: service.monitors

                MonitorRow {
                  required property var modelData
                  required property int index
                  width: monitorColumn.width
                  monitor: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: service.total === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "No monitors detected."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component MonitorRow: Item {
    id: row

    property var monitor: null
    property int rowIndex: 0

    readonly property string name: monitor ? String(monitor.name) : ""
    readonly property string description: monitor ? String(monitor.description || "") : ""
    readonly property string video: monitor ? String(monitor.video || "") : ""
    readonly property string videoName: monitor ? String(monitor.videoName || "") : ""
    readonly property bool available: monitor ? monitor.available !== false : true
    readonly property bool isRunning: monitor ? monitor.running === true : false
    readonly property string label: {
      if (video) return available ? videoName : "Missing or unreadable"
      if (description !== "") return "No video · " + description
      return "No video chosen"
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: rowBody.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: row.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          // Theme-colored status dot instead of ▶/⏹ glyphs: those come out as
          // emoji-colored squares in the bar font.
          Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: Style.space(8)
            height: width
            radius: width / 2
            color: row.isRunning ? Color.accent : root.dim
            opacity: row.isRunning ? 1 : 0.5
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.label
          color: row.video && row.available ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Button {
        id: pickButton
        text: "Pick"
        tooltipText: "Choose a video for " + row.name
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy
        hasCursor: root.monitorHasCursor(row.rowIndex, 0)
        onHovered: function(isHovered) { if (isHovered) root.setCursor("monitor", row.rowIndex, 0) }
        onHasCursorChanged: if (hasCursor) root.cursorItem = pickButton
        onClicked: service.pickFor(row.name)
      }

      Button {
        id: toggleButton
        visible: row.video !== ""
        text: row.isRunning ? "Stop" : "Start"
        tooltipText: (row.isRunning ? "Stop" : "Start") + " the wallpaper on " + row.name
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy && row.available
        hasCursor: root.monitorHasCursor(row.rowIndex, 1)
        onHovered: function(isHovered) { if (isHovered) root.setCursor("monitor", row.rowIndex, 1) }
        onHasCursorChanged: if (hasCursor) root.cursorItem = toggleButton
        onClicked: service.toggleMonitor(row.name, !row.isRunning)
      }

      Button {
        id: clearButton
        visible: row.video !== ""
        text: "Clear"
        tooltipText: "Remove the assigned video"
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy
        hasCursor: root.monitorHasCursor(row.rowIndex, 2)
        onHovered: function(isHovered) { if (isHovered) root.setCursor("monitor", row.rowIndex, 2) }
        onHasCursorChanged: if (hasCursor) root.cursorItem = clearButton
        onClicked: service.clearFor(row.name)
      }
    }
  }
}
