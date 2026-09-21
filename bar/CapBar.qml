import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "hyc.capqbar"
  ipcTarget: "hyc.capqbar"

  property int todayCount: 0
  property int queueCount: 0
  readonly property bool hasQueue: queueCount > 0
  readonly property color alert: "#d1705f"

  function refresh() {
    statusProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: [statusScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(" ")
        root.todayCount = parseInt(parts[0]) || 0
        root.queueCount = parseInt(parts[1]) || 0
      }
    }
  }

  Process {
    id: openProc
    command: ["omarchy-shell", "shell", "summon", "hyc.capq8"]
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.todayCount > 0 ? ("CAP " + root.todayCount) : "CAP"
    tooltipText: root.hasQueue
      ? ("Cap Quick · 今日 " + root.todayCount + " 条 · 队列 " + root.queueCount + " 待补发")
      : ("Cap Quick · 今日 " + root.todayCount + " 条")

    onPressed: function(mouseButton) {
      openProc.running = true
    }
  }
}
