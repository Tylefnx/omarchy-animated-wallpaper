import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar slot + popup panel for animated wallpapers. The heavy lifting (mpvpaper
// lifecycle, per-monitor assignments) lives in bin/wallpaper-video via
// Service.qml; this file is presentation only.
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

  readonly property string labelMode: String(setting("barLabel", "Nothing"))
  readonly property string labelSuffix: {
    if ((bar && bar.vertical) || labelMode !== "Active monitors") return ""
    if (service.total === 0) return ""
    return " " + service.active + "/" + service.total
  }

  readonly property string tooltip: {
    if (service.total === 0) return "Animated wallpaper\nNo monitors detected"
    var lines = []
    for (var i = 0; i < service.monitors.length; i++) {
      var m = service.monitors[i]
      if (m.running) lines.push(m.name + ": " + (m.videoName || "video") + " (playing)")
      else if (m.video) lines.push(m.name + ": " + m.videoName + " (stopped)")
      else lines.push(m.name + ": no video")
    }
    lines.push("Left-click: toggle · Right-click: configure")
    return lines.join("\n")
  }

  readonly property string heroMeta: {
    if (service.total === 0) return "No monitors detected"
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
    service.refresh()
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
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph + root.labelSuffix
    tooltipText: root.tooltip

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
                checked: service.running
                busy: service.busy
                foreground: root.foreground
                onToggled: service.toggle()
              }
            }
          }

          Text {
            visible: service.actionStatus !== "" || service.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: service.lastError !== "" ? service.lastError : service.actionStatus
            color: service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: service.total > 0 && service.configuredCount === 0 && service.lastError === ""
            width: parent.width
            textFormat: Text.PlainText
            text: "Pick a video for each monitor to get started."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
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
        text: "Pick"
        tooltipText: "Choose a video for " + row.name
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy
        onClicked: service.pickFor(row.name)
      }

      Button {
        visible: row.video !== ""
        text: row.isRunning ? "Stop" : "Start"
        tooltipText: (row.isRunning ? "Stop" : "Start") + " the wallpaper on " + row.name
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy && row.available
        onClicked: service.toggleMonitor(row.name, !row.isRunning)
      }

      Button {
        visible: row.video !== ""
        text: "Clear"
        tooltipText: "Remove the assigned video"
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !service.busy
        onClicked: service.clearFor(row.name)
      }
    }
  }
}
