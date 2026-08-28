import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property string backendPath: ""
  property bool opened: false
  property string resourceType: "project"
  property string currentPath: ""
  property string parentPath: ""
  property string selectedPath: ""
  property string selectedKind: ""
  property bool showHidden: false
  property bool loading: false
  property bool truncated: false
  property string errorText: ""

  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color accent: Color.accent
  property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  property color subtle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  property string fontFamily: Style.font.family

  signal accepted(string path)
  signal canceled()

  visible: opened
  enabled: opened
  focus: opened
  z: 200

  ListModel { id: entryModel }

  function openPicker(type, initialPath) {
    root.resourceType = type === "file" ? "file" : "project"
    root.showHidden = false
    root.opened = true
    root.errorText = ""
    root.selectedPath = ""
    root.selectedKind = ""
    root.loadPath(initialPath || Quickshell.env("HOME"))
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function closePicker() {
    root.opened = false
    root.loading = false
    root.canceled()
  }

  function loadPath(path) {
    if (!root.opened || root.loading || !root.backendPath) return
    var requested = String(path || "").trim()
    if (!requested) requested = Quickshell.env("HOME")
    root.loading = true
    root.errorText = ""
    root.selectedPath = ""
    root.selectedKind = ""
    entryList.currentIndex = -1
    browseProcess.command = [root.backendPath, "api", "browse-path", "--path", requested,
      "--type", root.resourceType]
    if (root.showHidden) browseProcess.command.push("--show-hidden")
    browseProcess.running = true
  }

  function consumeResponse(raw) {
    root.loading = false
    try {
      var response = JSON.parse(String(raw || "{}"))
      if (!response.ok) {
        root.errorText = String(response.error || "Could not read this directory")
        return
      }
      var result = response.result || ({})
      root.currentPath = String(result.path || "")
      root.parentPath = String(result.parent || "")
      root.truncated = result.truncated === true
      pathField.text = root.currentPath
      entryModel.clear()
      var entries = Array.isArray(result.entries) ? result.entries : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        entryModel.append({
          entryName: String(entry.name || ""),
          entryPath: String(entry.path || ""),
          entryKind: String(entry.kind || "file"),
          entryHidden: entry.hidden === true,
          entrySymlink: entry.symlink === true
        })
      }
      if (entryModel.count > 0) root.selectIndex(0)
    } catch (e) {
      root.errorText = "Invalid directory response: " + e
    }
    Qt.callLater(function() { entryList.forceActiveFocus() })
  }

  function selectIndex(index) {
    if (index < 0 || index >= entryModel.count) return
    entryList.currentIndex = index
    var entry = entryModel.get(index)
    root.selectedPath = String(entry["entryPath"] || "")
    root.selectedKind = String(entry["entryKind"] || "")
  }

  function selectedEntry() {
    var count = entryModel.count
    var index = entryList.currentIndex
    return index >= 0 && index < count ? entryModel.get(index) : null
  }

  function activateIndex(index) {
    root.selectIndex(index)
    if (root.selectedKind === "directory") root.loadPath(root.selectedPath)
    else if (root.resourceType === "file" && root.selectedKind === "file") root.acceptSelection()
  }

  function acceptSelection() {
    var path = root.resourceType === "project" ? root.currentPath
      : (root.selectedKind === "file" ? root.selectedPath : "")
    if (!path) return
    root.opened = false
    root.accepted(path)
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.closePicker()
      event.accepted = true
      return
    }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
      pathField.forceActiveFocus()
      pathField.selectAll()
      event.accepted = true
      return
    }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H) {
      root.showHidden = !root.showHidden
      root.loadPath(root.currentPath)
      event.accepted = true
      return
    }
    if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up && root.parentPath) {
      root.loadPath(root.parentPath)
      event.accepted = true
      return
    }
    if (pathField.activeFocus) return
    if (event.key === Qt.Key_Down && entryModel.count > 0) {
      root.selectIndex(Math.min(entryModel.count - 1, entryList.currentIndex + 1))
      entryList.positionViewAtIndex(entryList.currentIndex, ListView.Contain)
      event.accepted = true
    } else if (event.key === Qt.Key_Up && entryModel.count > 0) {
      root.selectIndex(Math.max(0, entryList.currentIndex - 1))
      entryList.positionViewAtIndex(entryList.currentIndex, ListView.Contain)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activateIndex(entryList.currentIndex)
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.64)
    MouseArea { anchors.fill: parent }
  }

  Rectangle {
    id: pickerCard
    anchors.centerIn: parent
    width: Math.max(Style.space(560), parent.width - Style.space(44))
    height: Math.max(Style.space(480), parent.height - Style.space(44))
    radius: Style.cornerRadius
    color: root.background
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(12)

      Row {
        width: parent.width
        height: Style.space(38)
        spacing: Style.space(10)

        Column {
          width: parent.width - closeButton.width - parent.spacing
          spacing: Style.space(2)
          Text {
            text: root.resourceType === "project" ? "Choose a project directory" : "Choose a file"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            text: "QOpen safe browser · no GTK/GVFS file dialog"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          id: closeButton
          width: Style.space(38)
          height: Style.space(34)
          text: "×"
          foreground: root.foreground
          focusable: true
          onClicked: root.closePicker()
        }
      }

      Row {
        width: parent.width
        height: Style.space(36)
        spacing: Style.space(7)

        Button {
          width: Style.space(42); height: parent.height
          iconText: "󰁍"; tooltipText: "Parent directory · Alt+Up"
          foreground: root.foreground; bordered: true
          enabled: root.parentPath !== "" && !root.loading
          opacity: enabled ? 1 : 0.38
          onClicked: root.loadPath(root.parentPath)
        }
        Button {
          width: Style.space(42); height: parent.height
          iconText: "󰋜"; tooltipText: "Home"
          foreground: root.foreground; bordered: true
          enabled: !root.loading
          onClicked: root.loadPath(Quickshell.env("HOME"))
        }
        TextField {
          id: pathField
          width: parent.width - Style.space(42 * 4) - parent.spacing * 4
          height: parent.height
          text: root.currentPath
          placeholderText: "Enter a directory path"
          foreground: root.foreground
          onAccepted: root.loadPath(text)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.forceActiveFocus()
              event.accepted = true
            }
          }
        }
        Button {
          width: Style.space(42); height: parent.height
          text: "Go"; tooltipText: "Open typed path"
          foreground: root.foreground; bordered: true
          enabled: !root.loading
          onClicked: root.loadPath(pathField.text)
        }
        Button {
          width: Style.space(42); height: parent.height
          iconText: root.showHidden ? "󰈈" : "󰈉"
          tooltipText: "Toggle hidden files · Ctrl+H"
          foreground: root.foreground; bordered: true; selected: root.showHidden
          enabled: !root.loading
          onClicked: {
            root.showHidden = !root.showHidden
            root.loadPath(root.currentPath)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: parent.height - Style.space(38 + 36 + 52) - parent.spacing * 3
        radius: Style.cornerRadius
        color: root.subtle
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
        clip: true

        ListView {
          id: entryList
          anchors.fill: parent
          anchors.margins: 1
          model: entryModel
          clip: true
          focus: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged: {
            if (currentIndex >= 0 && currentIndex < entryModel.count)
              root.selectIndex(currentIndex)
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down && entryModel.count > 0) {
              root.selectIndex(Math.min(entryModel.count - 1, currentIndex + 1))
              positionViewAtIndex(currentIndex, ListView.Contain)
              event.accepted = true
            } else if (event.key === Qt.Key_Up && entryModel.count > 0) {
              root.selectIndex(Math.max(0, currentIndex - 1))
              positionViewAtIndex(currentIndex, ListView.Contain)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateIndex(currentIndex)
              event.accepted = true
            }
          }

          delegate: Rectangle {
            required property int index
            required property string entryName
            required property string entryPath
            required property string entryKind
            required property bool entryHidden
            required property bool entrySymlink

            width: entryList.width
            height: Style.space(40)
            color: entryList.currentIndex === index
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
              : (entryMouse.containsMouse ? root.subtle : "transparent")

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                width: Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                text: entryKind === "directory" ? "󰉋" : "󰈙"
                color: entryKind === "directory" ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                width: parent.width - Style.space(90)
                anchors.verticalCenter: parent.verticalCenter
                text: entryName
                color: root.foreground
                opacity: entryHidden ? 0.68 : 1
                elide: Text.ElideMiddle
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: Style.space(42)
                anchors.verticalCenter: parent.verticalCenter
                text: entrySymlink ? "link" : (entryKind === "directory" ? "folder" : "file")
                color: root.muted
                horizontalAlignment: Text.AlignRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: entryMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectIndex(index)
              onDoubleClicked: root.activateIndex(index)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !root.loading && !root.errorText && entryModel.count === 0
            text: root.resourceType === "project" ? "No subdirectories" : "This directory is empty"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.loading
          text: "Loading…"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          visible: root.errorText !== ""
          text: root.errorText
          color: Color.urgent
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        width: parent.width
        height: Style.space(52)
        spacing: Style.space(10)

        Column {
          width: parent.width - cancelButton.width - chooseButton.width - parent.spacing * 2
          spacing: Style.space(3)
          Text {
            width: parent.width
            text: root.resourceType === "project"
              ? "Current folder: " + root.currentPath
              : (root.selectedKind === "file" ? "Selected: " + root.selectedPath : "Select a file or double-click it")
            color: root.muted
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.truncated
            text: "Showing the first 1000 entries"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Button {
          id: cancelButton
          height: Style.space(38)
          text: "Cancel"
          foreground: root.foreground
          bordered: true
          focusable: true
          onClicked: root.closePicker()
        }
        Button {
          id: chooseButton
          height: Style.space(38)
          text: root.resourceType === "project" ? "Use this folder" : "Choose file"
          foreground: root.foreground
          accent: root.accent
          selected: true
          bordered: true
          focusable: true
          enabled: !root.loading && root.errorText === "" &&
            (root.resourceType === "project" ? root.currentPath !== ""
              : root.selectedKind === "file")
          opacity: enabled ? 1 : 0.42
          onClicked: root.acceptSelection()
        }
      }
    }
  }

  Process {
    id: browseProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.consumeResponse(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.loading) root.loading = false
    }
  }
}
