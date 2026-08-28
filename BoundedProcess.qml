import Quickshell.Io
import QtQuick

Item {
  id: root

  width: 0
  height: 0
  visible: false

  property int timeoutMs: 2000
  property int responseLimit: 1310720
  readonly property bool running: child.running
  readonly property var processId: child.processId

  property int activeRequestId: 0
  property string responseText: ""
  property string protocolError: ""
  property bool responseSeen: false
  property bool timedOut: false
  property bool canceled: false

  signal finished(string response, int exitCode, int requestId, string error)

  function start(command, requestId) {
    if (child.running || !Array.isArray(command) || command.length === 0) return false
    root.activeRequestId = Number(requestId || 0)
    root.responseText = ""
    root.protocolError = ""
    root.responseSeen = false
    root.timedOut = false
    root.canceled = false
    deadlineTimer.restart()
    child.command = command
    child.running = true
    return true
  }

  function cancel() {
    root.canceled = true
    deadlineTimer.stop()
    if (child.running) {
      child.signal(15)
      killTimer.restart()
    }
  }

  function abortProtocol(message) {
    if (root.protocolError) return
    root.protocolError = String(message || "Invalid backend response")
    if (child.running) {
      child.signal(15)
      killTimer.restart()
    }
  }

  Process {
    id: child

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (root.canceled || root.protocolError) return
        var line = String(data || "")
        if (root.responseSeen) {
          root.abortProtocol("Backend returned more than one response")
          return
        }
        if (line.length > root.responseLimit) {
          root.abortProtocol("Backend response exceeded its safety limit")
          return
        }
        root.responseText = line
        root.responseSeen = true
      }
    }

    onExited: function(exitCode) {
      deadlineTimer.stop()
      killTimer.stop()
      var error = root.protocolError
      if (root.timedOut) error = "Backend operation timed out"
      else if (root.canceled) error = "Backend operation canceled"
      else if (!root.responseSeen) error = "Backend returned no response"
      root.finished(root.responseText, exitCode, root.activeRequestId, error)
    }
  }

  Timer {
    id: deadlineTimer
    interval: root.timeoutMs
    onTriggered: {
      root.timedOut = true
      if (child.running) {
        child.signal(15)
        killTimer.restart()
      }
    }
  }

  Timer {
    id: killTimer
    interval: 250
    onTriggered: {
      if (child.running) child.signal(9)
    }
  }
}
