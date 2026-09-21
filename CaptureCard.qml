import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool sending: false
  property string sendError: ""
  property bool draftRestored: false
  property string clipboardHint: ""

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/cap-quick"
  readonly property string draftPath: stateDir + "/draft.txt"
  readonly property string scriptPath: Qt.resolvedUrl("send.sh").toString().replace("file://", "")

  // ── theme tokens (menu surface, same contract as omarchy.clipboard) ──
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color muted: Color.muted
  readonly property color errColor: "#d1705f"
  readonly property int cardWidth: Math.min(560, Screen.width - 100)
  readonly property int cornerRadius: Style.cornerRadius

  function open(payloadJson) {
    root.opened = true
    root.sendError = ""
    root.sending = false
    root.draftRestored = false
    input.clear()
    draftLoader.reload()
    root.loadClipboardHint()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    const text = input.text.trim()
    if (text.length > 0 && !root.sending)
      root.saveDraft(text)
    else if (text.length === 0)
      root.clearDraft()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function loadClipboardHint() {
    clipboardProc.command = ["sh", "-c", "wl-paste --no-newline 2>/dev/null | head -c 300"]
    clipboardProc.running = true
  }

  function saveDraft(text) {
    // heredoc via shell keeps newlines; text arrives pre-trimmed
    saveDraftProc.command = ["/bin/sh", "-c",
      "mkdir -p '" + root.stateDir + "' && printf '%s\\n' $(cat <<'CAPEOF'\n" + text + "\nCAPEOF\n) > '" + root.draftPath + "' 2>/dev/null || true"]
    // simpler & robust: delegate to python-free printf via stdin file copy
    saveDraftProc.command = ["/bin/sh", "-c",
      "mkdir -p '" + root.stateDir + "' && cat > '" + root.draftPath + "' <<'CAPEOF'\n" + text + "\nCAPEOF"]
    saveDraftProc.running = true
  }

  function clearDraft() {
    clearDraftProc.running = true
  }

  function send() {
    const text = input.text.trim()
    if (text.length === 0 || root.sending) return
    root.sending = true
    root.sendError = ""
    // stage text to pending.txt via heredoc, then hand to send.sh (token/queue/flush)
    sendWrapProc.command = ["/bin/sh", "-c",
      "mkdir -p '" + root.stateDir + "' && cat > '" + root.stateDir + "/pending.txt' <<'CAPEOF'\n" + text + "\nCAPEOF\n" +
      "'" + root.scriptPath + "' '" + root.stateDir + "/pending.txt'"]
    sendWrapProc.running = true
  }

  // ── IO ──
  FileView {
    id: draftLoader
    path: root.draftPath
    printErrors: false
    onLoaded: {
      const t = text().trim()
      if (t.length > 0) {
        input.text = t
        root.draftRestored = true
      }
    }
    onLoadFailed: root.draftRestored = false
  }

  Process {
    id: clipboardProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text || "").trim()
        root.clipboardHint = (t.length > 0 && t.length < 500) ? t : ""
      }
    }
  }

  Process {
    id: saveDraftProc
    command: []
  }

  Process {
    id: clearDraftProc
    command: ["/bin/sh", "-c", "rm -f '" + root.draftPath + "'"]
  }

  Process {
    id: sendWrapProc
    command: []
    onExited: function(code) {
      root.sending = false
      if (code === 0) {
        input.clear()
        root.clearDraft()
        root.opened = false
        okNotify.running = true
      } else if (code === 1) {
        input.clear()
        root.clearDraft()
        root.opened = false
        queueNotify.running = true
      } else if (code === 3) {
        root.sendError = "token 无效或缺失（~/.config/cap-quick/token 或 ~/.hermes/.env）"
      } else {
        root.sendError = "发送失败（code " + code + "）"
      }
    }
  }

  Process {
    id: okNotify
    command: ["notify-send", "-a", "Cap Quick", "✓ 已入 Capacities Daily Note"]
  }

  Process {
    id: queueNotify
    command: ["notify-send", "-a", "Cap Quick", "✗ 网络失败，已入本地队列（下次成功自动补发）"]
  }

  // ── fullscreen layer-shell window ──
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "hyc-cap-quick"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    // capture Escape anywhere (TextArea may not own focus)
    Item {
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: cardCol.implicitHeight + Style.space(10)
      anchors.centerIn: parent
      color: root.background
      radius: root.cornerRadius
      border.width: Math.max(1, Style.space(0.5))
      border.color: root.border

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(5)
        spacing: Style.space(3)

        Item {
          width: parent.width
          height: Math.max(titleText.implicitHeight, sendingText.implicitHeight)
          Text {
            id: titleText
            text: "⚡ Quick Capture"
            color: root.foreground
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: sendingText
            text: root.sending ? "发送中…" : ""
            color: root.muted
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        TextEdit {
          id: input
          width: parent.width
          height: 64
          color: root.foreground
          font.pixelSize: Style.font.body
          wrapMode: TextEdit.Wrap
          selectedTextColor: root.background
          selectionColor: root.border
          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(-2)
            radius: root.cornerRadius * 0.6
            color: Qt.darker(root.background, 1.12)
            border.width: 1
            border.color: input.activeFocus ? root.border : Qt.lighter(root.background, 1.25)
            z: -1
          }
          Text {
            visible: input.text.length === 0 && !input.activeFocus
            text: "记点什么… (Enter 发送 · Esc 关闭)"
            color: root.muted
            font.pixelSize: 13
            anchors.fill: parent
            anchors.margins: 4
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
              event.accepted = true
              root.send()
            } else if (event.key === Qt.Key_Tab && root.clipboardHint.length > 0 && input.text.length === 0) {
              event.accepted = true
              input.text = root.clipboardHint
              input.cursorPosition = input.text.length
            }
          }
        }

        Text {
          width: parent.width
          visible: root.clipboardHint.length > 0 && input.text.length === 0
          text: "📋 " + (root.clipboardHint.length > 80 ? root.clipboardHint.slice(0, 80) + "…" : root.clipboardHint) + "  (Tab 填入)"
          color: root.muted
          font.pixelSize: Style.font.caption
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
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Text {
          visible: root.draftRestored && input.text.length > 0
          text: "已恢复上次未发送的草稿"
          color: root.muted
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          id: sendButton
          width: parent.width
          height: 36
          radius: 6
          color: sendMa.pressed ? Qt.darker(root.border, 1.2) : sendMa.containsMouse ? Qt.lighter(root.border, 1.15) : root.border

          Text {
            anchors.centerIn: parent
            text: root.sending ? "发送中…" : "发送 (Enter)"
            color: root.background
            font.pixelSize: Style.font.body
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
