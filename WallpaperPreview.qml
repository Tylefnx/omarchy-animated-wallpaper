import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  required property var service
  property string selectedLayout: "fill"

  readonly property bool isGif: /\.gif$/i.test(service.previewPath)
  readonly property bool isVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(service.previewPath)
  readonly property string previewUrl: service.previewPath ? Util.fileUrl(service.previewPath) : ""
  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color surface: Color.background
  readonly property var layouts: [
    { value: "fill", label: "Fill" },
    { value: "fit", label: "Fit" },
    { value: "stretch", label: "Stretch" },
    { value: "center", label: "Center" }
  ]

  function layoutIndex() {
    for (var i = 0; i < layouts.length; i++)
      if (layouts[i].value === selectedLayout) return i
    return 0
  }

  function moveLayout(delta) {
    var next = (layoutIndex() + delta + layouts.length) % layouts.length
    selectedLayout = layouts[next].value
  }

  onServiceChanged: selectedLayout = service.previewLayout || "fill"
  Connections {
    target: root.service
    function onPreviewPathChanged() { root.selectedLayout = root.service.previewLayout || "fill" }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: previewWindow
      required property var modelData
      screen: modelData
      visible: root.service.previewPath !== "" && modelData.name === root.service.previewMonitor
      readonly property real previewScale: Math.min(
        previewFrame.width / Math.max(screen.width, 1),
        previewFrame.height / Math.max(screen.height, 1))
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "r4venward-wallpaper-preview"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.82)
      }

      FocusScope {
        id: keyboardScope
        anchors.fill: parent
        focus: previewWindow.visible

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.service.cancelPreview()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!root.service.busy) root.service.applyPreview(root.selectedLayout)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveLayout(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveLayout(1)
            event.accepted = true
          }
        }

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)

        Rectangle {
          id: card
          width: Math.min(parent.width - 48, 1040)
          height: Math.min(parent.height - 48, 820)
          anchors.centerIn: parent
          radius: Style.space(4)
          color: root.surface
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32)

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(24)
            spacing: Style.space(12)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(3)

                Text {
                  text: "Preview wallpaper"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                }

                Text {
                  Layout.fillWidth: true
                  text: root.service.previewMonitor + "  ·  " + root.service.previewPath.split("/").pop()
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Text {
                text: root.isVideo ? "VIDEO PREVIEW" : root.isGif ? "ANIMATION PREVIEW" : "IMAGE PREVIEW"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
            }

            Rectangle {
              id: previewFrame
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 160
              radius: Style.space(3)
              color: "#090a10"
              clip: true

              Image {
                id: previewImage
                anchors.centerIn: parent
                width: root.selectedLayout === "center"
                  ? (sourceSize.width > 0 ? sourceSize.width * previewWindow.previewScale : parent.width * 0.5)
                  : parent.width
                height: root.selectedLayout === "center"
                  ? (sourceSize.height > 0 ? sourceSize.height * previewWindow.previewScale : parent.height * 0.5)
                  : parent.height
                visible: !root.isVideo && !root.isGif
                source: visible ? root.previewUrl : ""
                asynchronous: true
                cache: false
                fillMode: root.selectedLayout === "fill" ? Image.PreserveAspectCrop
                  : root.selectedLayout === "stretch" ? Image.Stretch
                  : Image.PreserveAspectFit
              }

              AnimatedImage {
                anchors.centerIn: parent
                width: root.selectedLayout === "center"
                  ? (sourceSize.width > 0 ? sourceSize.width * previewWindow.previewScale : parent.width * 0.5)
                  : parent.width
                height: root.selectedLayout === "center"
                  ? (sourceSize.height > 0 ? sourceSize.height * previewWindow.previewScale : parent.height * 0.5)
                  : parent.height
                visible: root.isGif
                source: visible ? root.previewUrl : ""
                asynchronous: true
                cache: false
                fillMode: root.selectedLayout === "fill" ? Image.PreserveAspectCrop
                  : root.selectedLayout === "stretch" ? Image.Stretch
                  : Image.PreserveAspectFit
              }

              VideoOutput {
                id: previewVideoOutput
                anchors.centerIn: parent
                readonly property var sourceResolution: previewPlayer.metaData.value(MediaMetaData.Resolution)
                width: root.selectedLayout === "center" && sourceResolution && sourceResolution.width > 0
                  ? sourceResolution.width * previewWindow.previewScale : parent.width
                height: root.selectedLayout === "center" && sourceResolution && sourceResolution.height > 0
                  ? sourceResolution.height * previewWindow.previewScale : parent.height
                visible: root.isVideo
                fillMode: root.selectedLayout === "fill" ? VideoOutput.PreserveAspectCrop
                  : root.selectedLayout === "stretch" ? VideoOutput.Stretch
                  : VideoOutput.PreserveAspectFit
              }

              Text {
                anchors.centerIn: parent
                visible: !root.isVideo && !root.isGif && previewImage.status === Image.Error
                text: "This image could not be previewed"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)

              Text {
                text: "LAYOUT"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Repeater {
                model: root.layouts

                delegate: Rectangle {
                  required property var modelData
                  Layout.preferredWidth: 94
                  Layout.preferredHeight: 34
                  radius: height / 2
                  color: root.selectedLayout === modelData.value
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                    : "transparent"
                  border.width: 1
                  border.color: root.selectedLayout === modelData.value ? root.foreground : root.dim

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.selectedLayout = modelData.value
                  }
                }
              }

              Item { Layout.fillWidth: true }

              Text {
                text: "← → to change layout · Esc to cancel"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              Text {
                Layout.fillWidth: true
                visible: root.service.lastError !== ""
                text: root.service.lastError
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Rectangle {
                Layout.preferredWidth: 108
                Layout.preferredHeight: 38
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: root.dim

                Text {
                  anchors.centerIn: parent
                  text: "Cancel"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: !root.service.busy
                  onClicked: root.service.cancelPreview()
                }
              }

              Rectangle {
                Layout.preferredWidth: 128
                Layout.preferredHeight: 38
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                border.width: 1
                border.color: root.foreground
                opacity: root.service.busy ? 0.55 : 1

                Text {
                  anchors.centerIn: parent
                  text: root.service.busy ? "Applying…" : "Set wallpaper"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: !root.service.busy
                  onClicked: root.service.applyPreview(root.selectedLayout)
                }
              }
            }
          }
        }
      }

      MediaPlayer {
        id: previewPlayer
        source: previewWindow.visible && root.isVideo ? root.previewUrl : ""
        loops: MediaPlayer.Infinite
        videoOutput: previewVideoOutput
        audioOutput: AudioOutput { muted: true }
        onSourceChanged: if (source.toString() !== "") play()
      }
    }
  }
}
