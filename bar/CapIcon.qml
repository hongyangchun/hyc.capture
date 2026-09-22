import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "hyc.capcount"
  ipcTarget: "hyc.capcount"

  property int todayCount: 0
  property int queueCount: 0
  readonly property bool hasQueue: queueCount > 0
  readonly property color alert: "#d1705f"

  // herdr-style sizing: standard icon slot, wider optical canvas for text
  readonly property real barSlot: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real barContentWidth: barSlot * 2.4

  readonly property string statusScript: {
    var u = Qt.resolvedUrl("status.sh").toString()
    if (u.indexOf("file://") === 0) u = u.substring(7)
    return u
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    statusProc.running = true
  }

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
    command: ["omarchy-shell", "shell", "summon", "hyc.cap"]
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
    // herdr-style: stretch the optical canvas so "CAP N" gets real width
    // instead of being squeezed into the single-glyph icon slot (which made
    // it overlap the neighbours and stretched the glyph spacing weirdly).
    slotSize: root.barSlot
    opticalSize: root.barSlot
    text: "CAP"
    tooltipText: root.hasQueue
      ? ("Cap Quick · 今日 " + root.todayCount + " 条 · 队列 " + root.queueCount + " 待补发")
      : ("Cap Quick · 今日 " + root.todayCount + " 条")
    useActiveColor: root.hasQueue

    onPressed: function(mouseButton) {
      openProc.running = true
    }
  }
}
