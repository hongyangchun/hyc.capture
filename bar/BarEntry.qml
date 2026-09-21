import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var bar: null
  property string moduleName: "hyc.capq8bar2"
  property var settings: ({})

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/cap-quick"
  readonly property string sentLog: stateDir + "/sent.log"
  readonly property string queueDir: stateDir + "/queue"

  property int todayCount: 0
  property int queueCount: 0
  readonly property bool hasQueue: queueCount > 0

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color alert: "#d1705f"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Component.onCompleted: refresh()

  function refresh() {
    countProc.command = ["/bin/sh", "-c", "today=$(date +%F); grep -c "$today" '" + sentLog + "' 2>/dev/null || echo 0"]
    countProc.running = true
    queueProc.command = ["/bin/sh", "-c", "ls '" + queueDir + "'/*.md 2>/dev/null | wc -l"]
    queueProc.running = true
  }

  Process {
    id: countProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.todayCount = parseInt(String(text).trim()) || 0
    }
  }

  Process {
    id: queueProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.queueCount = parseInt(String(text).trim()) || 0
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  FileView {
    path: root.sentLog
    printErrors: false
    watchChanges: true
    onFileChanged: root.refresh()
  }

  Item {
    implicitWidth: row.implicitWidth + 12
    implicitHeight: bar ? bar.barSize : 34

    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: openProc.running = true
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 3

      Text {
        text: "zap"
        color: root.hasQueue ? root.alert : root.fg
        font.family: root.fontFamily
        font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: root.todayCount > 0
        text: String(root.todayCount)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        visible: root.hasQueue
        width: 7; height: 7
        radius: 3.5
        color: root.alert
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      id: tip
      visible: ma.containsMouse
      width: tipText.implicitWidth + 16
      height: tipText.implicitHeight + 8
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
      radius: 6
      anchors.bottom: parent.top
      anchors.bottomMargin: 6
      anchors.horizontalCenter: parent.horizontalCenter
      z: 999

      Text {
        id: tipText
        anchors.centerIn: parent
        text: root.hasQueue ? "Cap Quick / today " + root.todayCount + " / queue " + root.queueCount
                            : "Cap Quick / today " + root.todayCount
        color: Color.menu.text
        font.pixelSize: 11
      }
    }
  }

  Process {
    id: openProc
    command: ["omarchy-shell", "shell", "summon", "hyc.capq8", "{}"]
  }
}
