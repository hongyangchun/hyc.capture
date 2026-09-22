import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property bool sending: false
  property bool draftRestored: false
  property string sendError: ""
  property string clipboardHint: ""

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/cap-quick"
  readonly property string draftPath: stateDir + "/draft.txt"
  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("send.sh").toString()
    if (u.indexOf("file://") === 0) u = u.substring(7)
    return u
  }

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color muted: Color.muted
  readonly property color errColor: "#d1705f"
  readonly property int cardWidth: 560
  readonly property int cornerRadius: Style.cornerRadius

  function open(payloadJson) {
    root.opened = true
    root.sendError = ""
    root.sending = false
    root.draftRestored = false
    input.text = ""
    loadDraft()
    loadClipboardHint()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    if (root.sending) { root.sendError = "正在发送…"; return }
    const t = input.text.trim()
    if (t.length > 0 && !root.sending) saveDraft(t)
    else if (t.length === 0) clearDraft()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function loadDraft() {
    draftReadProc.command = ["/bin/sh", "-c", "cat '" + draftPath + "' 2>/dev/null || true"]
    draftReadProc.running = true
  }

  function loadClipboardHint() {
    hintProc.command = ["/bin/sh", "-c", "wl-paste --type text/plain --no-newline 2>/dev/null | head -c 300"]
    hintProc.running = true
  }

  function saveDraft(t) {
    draftWriteProc.command = ["/bin/sh", "-c",
    'mkdir -p "$3"; printf "%s" "$1" > "$2"',
    "sh", t, root.draftPath, root.stateDir]
    draftWriteProc.running = true
  }

  function clearDraft() {
    clearProc.running = true
  }

  function send() {
    const t = input.text.trim()
    if (t.length === 0) {
      shake.start()
      return
    }
    if (root.sending) return
    root.sending = true
    root.sendError = ""
    stageAndSend(t)
  }

  function stageAndSend(t) {
    // content travels as argv ($1); never heredoc, never shell-parsed
    sendProc.command = ["/bin/sh", "-c",
      'export https_proxy=http://127.0.0.1:10808 http_proxy=http://127.0.0.1:10808; printf "%s" "$1" > "$2"; '
      + scriptPath + ' "$2"',
      'sh', t, root.stateDir + '/pending.txt']
    sendProc.running = true
  }

  // ---- IO ----
  Process {
    id: draftReadProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text).trim()
        if (t.length > 0) {
          input.text = t
          root.draftRestored = true
        }
      }
    }
  }

  Process {
    id: hintProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text).trim()
        root.clipboardHint = (t.length > 0 && t.length < 500) ? t : ""
      }
    }
  }




  Process { id: draftWriteProc; command: [] }
  Process { id: clearProc; command: ["/bin/sh", "-c", "rm -f '" + root.draftPath + "'"] }


  Process {
    id: sendProc
    command: []
    onExited: function(code) {
      root.sending = false
      if (code === 0) {
        input.clear()
        clearProc.running = true
        close()
        okNotify.running = true
      } else if (code === 1) {
        root.sendError = "网络异常 — 内容已存本地队列，将在下次发送成功后自动补发"
      } else if (code === 3) {
        root.sendError = "token missing"
      } else {
        root.sendError = "send failed (code " + code + ")"
      }
    }
  }

  Process { id: okNotify; command: ["notify-send", "-a", "Cap Quick", "✓ Appended to Capacities daily note"] }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "hyc-cap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: cardCol.implicitHeight + 32
      x: (parent.width - width) / 2
      y: (parent.height - height) / 2
      color: root.background
      radius: root.cornerRadius
      border.width: 1
      border.color: root.border

      MouseArea { anchors.fill: parent; onClicked: function(mouse) {} }

      SequentialAnimation {
        id: shake
        PropertyAnimation { target: card; property: "x"; from: card.x - 8; to: card.x + 8; duration: 60 }
        PropertyAnimation { target: card; property: "x"; from: card.x + 8; to: card.x - 8; duration: 60 }
        PropertyAnimation { target: card; property: "x"; to: card.x; duration: 60 }
      }

      Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        Item {
          width: parent.width
          height: titleText.implicitHeight
          Text {
            id: titleText
            text: "⚡ Quick Capture"
            color: root.foreground
            font.pixelSize: 15
            font.bold: true
            anchors.left: parent.left
          }
          Text {
            text: root.sending ? "sending…" : ""
            color: root.muted
            font.pixelSize: 11
            anchors.right: parent.right
          }
        }

        TextEdit {
          id: input
          width: parent.width
          height: Math.min(Math.max(64, contentHeight + 8), 200)
          color: root.foreground
          font.pixelSize: 13
          wrapMode: TextEdit.Wrap
          clip: true
          selectedTextColor: root.background
          selectionColor: root.border
          Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: 6
            color: Qt.darker(root.background, 1.12)
            border.width: 1
            border.color: input.activeFocus ? root.border : Qt.lighter(root.background, 1.25)
            z: -1
          }
          Text {
            visible: input.text.length === 0 && !input.activeFocus
            text: "记点什么…"
            color: root.muted
            font.pixelSize: 12
            anchors.fill: parent
            anchors.margins: 4
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
              event.accepted = true
              root.send()
            } else if (event.key === Qt.Key_Escape) {
              event.accepted = true
              root.close()
            } else if (event.key === Qt.Key_Tab && root.clipboardHint.length > 0 && input.text.length === 0) {
              event.accepted = true
              input.text = root.clipboardHint
              input.cursorPosition = input.text.length
            }
          }
        }


        Text {
          width: parent.width
          visible: true
          text: "Enter / Ctrl+Enter 发送 · Shift+Enter 换行 · Tab 粘贴剪贴板 · Esc 关闭"
          color: root.muted
          font.pixelSize: 10
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: root.clipboardHint.length > 0 && input.text.length === 0
          text: "📋 剪贴板（Tab 粘贴）：" + (root.clipboardHint.length > 60 ? root.clipboardHint.slice(0, 60) + "…" : root.clipboardHint)
          color: root.muted
          font.pixelSize: 11
          elide: Text.ElideRight
          MouseArea {
            anchors.fill: parent
            onClicked: {
              input.text = root.clipboardHint
              input.cursorPosition = input.text.length
              input.forceActiveFocus()
            }
          }
        }

        Text {
          width: parent.width
          visible: root.sendError.length > 0
          text: root.sendError
          color: root.errColor
          font.pixelSize: 11
          wrapMode: Text.Wrap
        }

        Text {
          visible: root.draftRestored && input.text.length > 0
          text: "已恢复草稿"
          color: root.muted
          font.pixelSize: 11
        }

        Rectangle {
          width: parent.width
          height: 36
          radius: 6
          color: sendMa.pressed ? Qt.darker(root.border, 1.2) : sendMa.containsMouse ? Qt.lighter(root.border, 1.15) : root.border
          Text {
            anchors.centerIn: parent
            text: root.sending ? "发送中…" : "发送 (Enter)"
            color: root.background
            font.pixelSize: 13
            font.bold: true
          }
          MouseArea {
            id: sendMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.send()
          }
        }
      }
    }
  }
}
