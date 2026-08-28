import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backendPath: ""
  property var availableGroups: []
  property bool saving: false
  property bool dirty: false
  property bool initializing: false
  property bool advancedOpen: false
  property bool confirmDiscard: false
  property string editorMode: "add"
  property var originalItem: null

  property string selectedType: "web"
  property string nameValue: ""
  property string idValue: ""
  property string groupValue: "web"
  property string descriptionValue: ""
  property string iconValue: ""
  property string targetValue: ""
  property string commandValue: ""
  property string webModeValue: "app"
  property string focusValue: ""
  property string editorValue: ""
  property bool favoriteValue: false
  property bool terminalValue: false
  property bool idTouched: false

  property string formError: ""
  property string targetStatus: ""
  property string targetLevel: ""
  property string expandedTarget: ""
  property string clipboardOutput: ""
  property int clipboardRequestSerial: 0
  property int targetRequestSerial: 0

  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color subtle: Style.hoverFillFor(foreground, Color.accent)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color borderColor: Color.menu.border
  readonly property int radius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var typeOptions: [
    { id: "web", icon: "󰖟", label: "Web" },
    { id: "project", icon: "󰉋", label: "Project" },
    { id: "file", icon: "󰈙", label: "File" },
    { id: "tui", icon: "", label: "TUI" },
    { id: "command", icon: "󰘳", label: "Command" },
    { id: "ssh", icon: "󰒍", label: "SSH" }
  ]

  readonly property var defaultGroups: ({
    web: "web", project: "projects", file: "config",
    tui: "tools", command: "system", ssh: "infra"
  })
  readonly property var defaultIcons: ({
    web: "󰖟", project: "󰉋", file: "󰈙",
    tui: "", command: "󰘳", ssh: "󰒍"
  })

  signal cancelRequested()
  signal submitRequested(string action, string payload, string originalPayload)

  function slugify(value) {
    var slug = String(value || "").toLowerCase()
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return slug || "item"
  }

  function shellQuote(value) {
    var text = String(value)
    if (text === "") return "''"
    if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(text)) return text
    return "'" + text.replace(/'/g, "'\"'\"'") + "'"
  }

  function argvToCommand(argv) {
    if (!Array.isArray(argv)) return String(argv || "")
    var quoted = []
    for (var i = 0; i < argv.length; i++) quoted.push(root.shellQuote(argv[i]))
    return quoted.join(" ")
  }

  function markDirty() {
    if (!root.initializing) root.dirty = true
    root.formError = ""
  }

  function beginCreate(contextGroup, favorite, initialType) {
    root.initializing = true
    root.editorMode = "add"
    root.originalItem = null
    var requestedType = String(initialType || "web")
    root.selectedType = root.defaultGroups[requestedType] ? requestedType : "web"
    root.nameValue = ""
    root.idValue = ""
    root.groupValue = contextGroup && contextGroup !== "all" && contextGroup !== "favorites"
      ? contextGroup : root.defaultGroups[root.selectedType]
    root.descriptionValue = ""
    root.iconValue = root.defaultIcons[root.selectedType]
    root.targetValue = ""
    root.commandValue = ""
    root.webModeValue = "app"
    root.focusValue = ""
    root.editorValue = ""
    root.favoriteValue = favorite === true
    root.terminalValue = false
    root.idTouched = false
    root.advancedOpen = false
    root.confirmDiscard = false
    root.formError = ""
    root.targetStatus = ""
    root.targetLevel = ""
    root.expandedTarget = ""
    root.dirty = false
    root.saving = false
    root.initializing = false
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function beginEdit(item) {
    root.initializing = true
    root.editorMode = "edit"
    root.originalItem = JSON.parse(JSON.stringify(item))
    root.selectedType = String(item.type || "web")
    root.nameValue = String(item.name || "")
    root.idValue = String(item.id || "")
    root.groupValue = String(item.group || root.defaultGroups[root.selectedType])
    root.descriptionValue = String(item.description || "")
    root.iconValue = String(item.icon || root.defaultIcons[root.selectedType])
    root.targetValue = String(item.target || "")
    root.commandValue = root.argvToCommand(item.command)
    root.webModeValue = String(item.mode || "app")
    root.focusValue = String(item.focus || "")
    root.editorValue = root.argvToCommand(item.editor)
    root.favoriteValue = item.favorite === true
    root.terminalValue = item.terminal === true
    root.idTouched = true
    root.advancedOpen = false
    root.confirmDiscard = false
    root.formError = ""
    root.targetStatus = ""
    root.targetLevel = ""
    root.expandedTarget = ""
    root.dirty = false
    root.saving = false
    root.initializing = false
    Qt.callLater(function() { nameField.forceActiveFocus(); nameField.selectAll() })
  }

  function setType(nextType) {
    if (root.editorMode === "edit" || root.selectedType === nextType) return
    var oldType = root.selectedType
    var oldDefaultGroup = root.defaultGroups[oldType]
    var oldDefaultIcon = root.defaultIcons[oldType]
    root.selectedType = nextType
    if (!root.groupValue || root.groupValue === oldDefaultGroup)
      root.groupValue = root.defaultGroups[nextType]
    if (!root.iconValue || root.iconValue === oldDefaultIcon)
      root.iconValue = root.defaultIcons[nextType]
    root.targetStatus = ""
    root.expandedTarget = ""
    root.markDirty()
  }

  function primaryLabel() {
    if (root.selectedType === "web") return "URL"
    if (root.selectedType === "project") return "Project directory"
    if (root.selectedType === "file") return "File path"
    if (root.selectedType === "ssh") return "SSH destination"
    return "Command"
  }

  function primaryPlaceholder() {
    if (root.selectedType === "web") return "https://example.com/docs"
    if (root.selectedType === "project") return "~/Code/my-project"
    if (root.selectedType === "file") return "~/.config/app/config.toml"
    if (root.selectedType === "ssh") return "user@example.com"
    if (root.selectedType === "tui") return "lazygit"
    return "notify-send 'Finished'"
  }

  function primaryValue() {
    return root.selectedType === "tui" || root.selectedType === "command"
      ? root.commandValue : root.targetValue
  }

  function setPrimaryValue(value) {
    if (root.selectedType === "tui" || root.selectedType === "command")
      root.commandValue = value
    else
      root.targetValue = value
  }

  function buildItem() {
    var item = {
      id: root.idValue.trim(),
      name: root.nameValue.trim(),
      type: root.selectedType,
      group: root.groupValue.trim(),
      description: root.descriptionValue.trim(),
      icon: root.iconValue.trim(),
      favorite: root.favoriteValue
    }
    if (root.selectedType === "web") {
      item.target = root.targetValue.trim()
      item.mode = root.webModeValue
      item.focus = root.focusValue.trim()
    } else if (root.selectedType === "file") {
      item.target = root.targetValue.trim()
      item.editor = root.editorValue.trim()
    } else if (root.selectedType === "project" || root.selectedType === "ssh") {
      item.target = root.targetValue.trim()
    } else {
      item.command = root.commandValue.trim()
      if (root.selectedType === "command") item.terminal = root.terminalValue
    }
    return item
  }

  function localValidation() {
    if (!root.nameValue.trim()) return "Name is required"
    if (root.idValue.trim() && !/^[a-z0-9][a-z0-9_-]*$/.test(root.idValue.trim()))
      return "ID must use lowercase letters, numbers, _ or -"
    if (!root.groupValue.trim()) return "Group is required"
    if (!root.primaryValue().trim()) return root.primaryLabel() + " is required"
    return ""
  }

  function requestSubmit() {
    if (root.saving) return
    var error = root.localValidation()
    if (error) {
      root.formError = error
      return
    }
    root.saving = true
    root.formError = ""
    root.submitRequested(root.editorMode === "edit" ? "update" : "create",
      JSON.stringify(root.buildItem()),
      root.originalItem ? JSON.stringify(root.originalItem) : "")
  }

  function saveFailed(message) {
    root.saving = false
    root.formError = message || "Could not save the resource"
  }

  function saveSucceeded() {
    root.saving = false
    root.dirty = false
  }

  function requestCancel() {
    if (root.saving) return
    if (root.dirty) root.confirmDiscard = true
    else root.cancelRequested()
  }

  function checkTarget() {
    var value = root.primaryValue().trim()
    if (!value || root.backendPath === "" || targetProcess.running) return
    if (value.length > 8192) {
      root.targetStatus = "Value exceeds the safety limit"
      root.targetLevel = "error"
      return
    }
    root.targetStatus = "Checking…"
    root.targetLevel = ""
    root.targetRequestSerial++
    targetProcess.start(
      [root.backendPath, "api", "check-target", "--type", root.selectedType, "--value", value],
      root.targetRequestSerial
    )
  }

  function useClipboard() {
    if (clipboardProcess.running || !root.backendPath) return
    root.clipboardOutput = ""
    root.targetStatus = "Reading clipboard…"
    root.targetLevel = ""
    root.clipboardRequestSerial++
    clipboardProcess.start(
      [root.backendPath, "api", "clipboard-read"],
      root.clipboardRequestSerial
    )
  }

  function expandedLocalPath(value) {
    var path = String(value || "").trim()
    if (path.indexOf("file://") === 0) path = root.fileUrlToPath(path)
    if (path === "~") path = Quickshell.env("HOME")
    else if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.slice(1)
    if (path.charAt(0) !== "/") path = Quickshell.env("HOME") + "/" + path
    return path
  }

  function initialPickerFolder() {
    var path = root.expandedLocalPath(root.targetValue)
    if (!path || path === "/") path = Quickshell.env("HOME")
    if (root.selectedType === "file") {
      var slash = path.lastIndexOf("/")
      path = slash > 0 ? path.slice(0, slash) : Quickshell.env("HOME")
    }
    return path
  }

  function fileUrlToPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try { value = decodeURIComponent(value) } catch (e) { /* keep raw path */ }
    return value
  }

  function inferNameFromPath(path) {
    if (root.nameValue.trim()) return
    var clean = String(path || "").replace(/\/+$/, "")
    var slash = clean.lastIndexOf("/")
    var base = slash >= 0 ? clean.slice(slash + 1) : clean
    if (root.selectedType === "file") {
      var dot = base.lastIndexOf(".")
      if (dot > 0) base = base.slice(0, dot)
    }
    if (!base) return
    root.nameValue = base.replace(/[-_]+/g, " ")
    nameField.text = root.nameValue
    if (!root.idTouched) root.idValue = root.slugify(root.nameValue)
  }

  function applyPickedPath(path) {
    path = String(path || "")
    if (!path) return
    root.setPrimaryValue(path)
    primaryField.text = path
    root.inferNameFromPath(path)
    root.markDirty()
    Qt.callLater(function() { root.checkTarget(); primaryField.forceActiveFocus() })
  }

  function openPathPicker() {
    if (root.selectedType !== "file" && root.selectedType !== "project") return
    pathPicker.openPicker(root.selectedType, root.initialPickerFolder())
  }

  BoundedProcess {
    id: clipboardProcess
    timeoutMs: 1500
    responseLimit: 16384
    onFinished: function(raw, exitCode, requestId, error) {
      if (requestId !== root.clipboardRequestSerial) return
      try {
        var response = error ? ({ ok: false, error: error }) : JSON.parse(String(raw || "{}"))
        var value = response.ok && response.result ? String(response.result.text || "") : ""
        if (!value) {
          root.targetStatus = String(response.error || "Clipboard is unavailable or does not contain text")
          root.targetLevel = "error"
          return
        }
        root.clipboardOutput = value
      } catch (e) {
        root.targetStatus = "Clipboard returned an invalid response"
        root.targetLevel = "error"
        return
      }
      root.setPrimaryValue(root.clipboardOutput)
      primaryField.text = root.clipboardOutput
      root.markDirty()
      Qt.callLater(root.checkTarget)
    }
  }

  BoundedProcess {
    id: targetProcess
    timeoutMs: 1500
    responseLimit: 32768
    onFinished: function(raw, exitCode, requestId, error) {
      if (requestId !== root.targetRequestSerial) return
      try {
        var response = error ? ({ ok: false, error: error }) : JSON.parse(String(raw || "{}"))
        if (!response.ok) {
          root.targetStatus = String(response.error || "Could not validate this value")
          root.targetLevel = "error"
          root.expandedTarget = ""
          return
        }
        var result = response.result || ({})
        root.targetStatus = String(result.message || "")
        root.targetLevel = String(result.level || "")
        root.expandedTarget = String(result.expanded || "")
      } catch (e) {
        root.targetStatus = "Could not validate this value"
        root.targetLevel = "error"
      }
    }
  }

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      root.requestSubmit()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.requestCancel()
      event.accepted = true
    }
  }

  Column {
    anchors.fill: parent

    Item {
      width: parent.width
      height: Style.space(58)

      Column {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          text: root.editorMode === "edit" ? "Edit resource" : "Add resource"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }
        Text {
          text: root.editorMode === "edit"
            ? "Update all fields without leaving QOpen"
            : "Choose a type, then complete the fields below"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(78); height: Style.space(34); radius: root.radius
          color: cancelMouse.containsMouse ? root.subtle : "transparent"
          border.width: 1; border.color: root.borderColor
          Text { text: "Cancel"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; anchors.centerIn: parent }
          MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestCancel() }
        }

        Rectangle {
          width: Style.space(96); height: Style.space(34); radius: root.radius
          color: root.saving ? root.muted : (saveMouse.containsMouse ? Qt.lighter(root.accent, 1.08) : root.accent)
          Text {
            text: root.saving ? "Saving…" : "Save"
            color: root.background; font.family: root.fontFamily; font.pixelSize: Style.font.body
            font.weight: Font.DemiBold; anchors.centerIn: parent
          }
          MouseArea { id: saveMouse; anchors.fill: parent; enabled: !root.saving; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestSubmit() }
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: root.borderColor; opacity: 0.35 }

    Flickable {
      id: formFlick
      width: parent.width
      height: parent.height - Style.space(59)
      contentWidth: width
      contentHeight: formColumn.implicitHeight + Style.space(24)
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: formColumn
        width: formFlick.width
        topPadding: Style.space(16)
        bottomPadding: Style.space(16)
        spacing: Style.space(14)

        Column {
          width: parent.width
          spacing: Style.space(7)
          Text {
            text: "RESOURCE TYPE"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            font.letterSpacing: Style.space(1)
          }
          Row {
            width: parent.width
            spacing: Style.space(7)
            Repeater {
              model: root.typeOptions
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.selectedType === modelData.id
                width: (parent.width - parent.spacing * 5) / 6
                height: Style.space(58)
                radius: root.radius
                color: active ? root.selectedBackground : (typeMouse.containsMouse ? root.subtle : "transparent")
                border.width: active ? 1 : 0
                border.color: root.accent
                opacity: root.editorMode === "edit" && !active ? 0.42 : 1
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(3)
                  Text { text: modelData.icon; color: active ? root.accent : root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.title; anchors.horizontalCenter: parent.horizontalCenter }
                  Text { text: modelData.label; color: active ? root.foreground : root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
                }
                MouseArea {
                  id: typeMouse; anchors.fill: parent; hoverEnabled: true
                  enabled: root.editorMode !== "edit"; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.setType(modelData.id)
                }
              }
            }
          }
          Text {
            visible: root.editorMode === "edit"
            text: "Resource type is fixed while editing"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          Column {
            width: (parent.width - parent.spacing) * 0.58
            spacing: Style.space(6)
            Text { text: "Name *"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            TextField {
              id: nameField
              width: parent.width
              text: root.nameValue
              placeholderText: "Resource name"
              foreground: root.foreground
              onTextChanged: {
                root.nameValue = text
                if (!root.idTouched) root.idValue = root.slugify(text)
                root.markDirty()
              }
            }
          }

          Column {
            width: parent.width - parent.spacing - (parent.width - parent.spacing) * 0.58
            spacing: Style.space(6)
            Text { text: "Group *"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            TextField {
              width: parent.width
              text: root.groupValue
              placeholderText: root.defaultGroups[root.selectedType]
              foreground: root.foreground
              onTextChanged: { root.groupValue = text; root.markDirty() }
            }
          }
        }

        ListView {
          visible: root.availableGroups && root.availableGroups.length > 0
          width: parent.width
          height: visible ? Style.space(28) : 0
          orientation: ListView.Horizontal
          spacing: Style.space(6)
          clip: true
          model: root.availableGroups
          delegate: Rectangle {
            required property var modelData
            width: groupText.implicitWidth + Style.space(18)
            height: Style.space(26)
            radius: height / 2
            color: root.groupValue === String(modelData) ? root.selectedBackground : (groupMouse.containsMouse ? root.subtle : "transparent")
            border.width: 1; border.color: root.borderColor
            Text { id: groupText; text: String(modelData); color: root.groupValue === String(modelData) ? root.accent : root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
            MouseArea { id: groupMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.groupValue = String(modelData); root.markDirty() } }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Text { text: root.primaryLabel() + " *"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Row {
            width: parent.width
            spacing: Style.space(8)
            TextField {
              id: primaryField
              width: parent.width - pasteButton.width - checkButton.width
                - (browseButton.visible ? browseButton.width + parent.spacing : 0)
                - parent.spacing * 2
              text: root.primaryValue()
              placeholderText: root.primaryPlaceholder()
              foreground: root.foreground
              onTextChanged: {
                root.setPrimaryValue(text)
                root.targetStatus = ""
                root.expandedTarget = ""
                root.markDirty()
              }
              onEditingFinished: root.checkTarget()
              Keys.onPressed: function(event) {
                if ((event.modifiers & Qt.ControlModifier) !== 0
                    && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.requestSubmit(); event.accepted = true
                }
              }
            }
            Rectangle {
              id: pasteButton
              width: Style.space(72); height: primaryField.height; radius: root.radius
              color: pasteMouse.containsMouse ? root.subtle : "transparent"
              border.width: 1; border.color: root.borderColor
              Text { text: "  Paste"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
              MouseArea { id: pasteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.useClipboard() }
            }
            Rectangle {
              id: browseButton
              visible: root.selectedType === "file" || root.selectedType === "project"
              width: Style.space(78); height: primaryField.height; radius: root.radius
              color: browseMouse.containsMouse ? root.subtle : "transparent"
              border.width: 1; border.color: root.borderColor
              Text { text: "  Browse"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
              MouseArea { id: browseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPathPicker() }
            }
            Rectangle {
              id: checkButton
              width: Style.space(70); height: primaryField.height; radius: root.radius
              color: checkMouse.containsMouse ? root.subtle : "transparent"
              border.width: 1; border.color: root.borderColor
              Text { text: "✓  Check"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
              MouseArea { id: checkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.checkTarget() }
            }
          }
          Text {
            visible: root.targetStatus !== ""
            width: parent.width
            text: (root.targetLevel === "ok" ? "✓  " : root.targetLevel === "warning" ? "  " : "  ")
              + root.targetStatus + (root.expandedTarget ? "  ·  " + root.expandedTarget : "")
            color: root.targetLevel === "ok" ? root.accent : (root.targetLevel === "warning" ? "#d6a84b" : root.urgent)
            font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Text { text: "Description"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            text: root.descriptionValue
            placeholderText: "Why this resource is useful"
            foreground: root.foreground
            onTextChanged: { root.descriptionValue = text; root.markDirty() }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(142); height: Style.space(34); radius: root.radius
            color: favoriteMouse.containsMouse ? root.subtle : "transparent"
            border.width: 1; border.color: root.favoriteValue ? root.accent : root.borderColor
            Text {
              text: (root.favoriteValue ? "" : "") + (root.favoriteValue ? "  Favorite" : "  Add favorite")
              color: root.favoriteValue ? root.accent : root.muted
              font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent
            }
            MouseArea { id: favoriteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.favoriteValue = !root.favoriteValue; root.markDirty() } }
          }

          Row {
            visible: root.selectedType === "web"
            spacing: Style.space(6)
            Text { text: "Open as"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
              model: ["app", "browser"]
              delegate: Rectangle {
                required property var modelData
                width: Style.space(76); height: Style.space(34); radius: root.radius
                color: root.webModeValue === String(modelData) ? root.selectedBackground : (modeMouse.containsMouse ? root.subtle : "transparent")
                border.width: 1; border.color: root.webModeValue === String(modelData) ? root.accent : root.borderColor
                Text { text: String(modelData); color: root.webModeValue === String(modelData) ? root.accent : root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
                MouseArea { id: modeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.webModeValue = String(modelData); root.markDirty() } }
              }
            }
          }

          Rectangle {
            visible: root.selectedType === "command"
            width: Style.space(154); height: Style.space(34); radius: root.radius
            color: terminalMouse.containsMouse ? root.subtle : "transparent"
            border.width: 1; border.color: root.terminalValue ? root.accent : root.borderColor
            Text {
              text: (root.terminalValue ? "󰆍" : "󰘳") + (root.terminalValue ? "  Run in terminal" : "  Run detached")
              color: root.terminalValue ? root.accent : root.muted
              font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent
            }
            MouseArea { id: terminalMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.terminalValue = !root.terminalValue; root.markDirty() } }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(36)
          radius: root.radius
          color: advancedMouse.containsMouse ? root.subtle : "transparent"
          border.width: 1; border.color: root.borderColor
          Text {
            text: (root.advancedOpen ? "" : "") + "  Advanced settings"
            color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
          }
          MouseArea { id: advancedMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.advancedOpen = !root.advancedOpen }
        }

        Column {
          visible: root.advancedOpen
          width: parent.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(12)
            Column {
              width: (parent.width - parent.spacing) * 0.65
              spacing: Style.space(6)
              Text { text: "Stable ID"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              TextField {
                width: parent.width; text: root.idValue; placeholderText: root.slugify(root.nameValue); foreground: root.foreground
                onTextEdited: root.idTouched = true
                onTextChanged: { root.idValue = text; root.markDirty() }
              }
            }
            Column {
              width: parent.width - parent.spacing - (parent.width - parent.spacing) * 0.65
              spacing: Style.space(6)
              Text { text: "Icon"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              TextField { width: parent.width; text: root.iconValue; placeholderText: root.defaultIcons[root.selectedType]; foreground: root.foreground; onTextChanged: { root.iconValue = text; root.markDirty() } }
            }
          }

          Column {
            visible: root.selectedType === "web"
            width: parent.width; spacing: Style.space(6)
            Text { text: "Window focus pattern"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            TextField { width: parent.width; text: root.focusValue; placeholderText: "Optional app window match"; foreground: root.foreground; onTextChanged: { root.focusValue = text; root.markDirty() } }
          }

          Column {
            visible: root.selectedType === "file"
            width: parent.width; spacing: Style.space(6)
            Text { text: "Editor command"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            TextField { width: parent.width; text: root.editorValue; placeholderText: "Uses the default editor when empty"; foreground: root.foreground; onTextChanged: { root.editorValue = text; root.markDirty() } }
          }
        }

        Rectangle {
          visible: root.formError !== ""
          width: parent.width
          height: errorText.implicitHeight + Style.space(18)
          radius: root.radius
          color: Style.hoverFillFor(root.urgent, root.urgent)
          border.width: 1; border.color: root.urgent
          Text {
            id: errorText
            width: parent.width - Style.space(20)
            text: "  " + root.formError
            color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap; anchors.centerIn: parent
          }
        }
      }
    }
  }

  Rectangle {
    visible: root.confirmDiscard
    anchors.fill: parent
    color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.88)
    z: 20

    BorderSurface {
      width: Style.space(360)
      height: Style.space(170)
      anchors.centerIn: parent
      radius: root.radius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.borderColor, 1)

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(12)
        Text { text: "Discard unsaved changes?"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.weight: Font.DemiBold }
        Text { width: parent.width; text: "The resource has not been saved."; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        Row {
          anchors.right: parent.right
          spacing: Style.space(8)
          Rectangle {
            width: Style.space(90); height: Style.space(34); radius: root.radius
            color: keepMouse.containsMouse ? root.subtle : "transparent"; border.width: 1; border.color: root.borderColor
            Text { text: "Keep editing"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
            MouseArea { id: keepMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.confirmDiscard = false }
          }
          Rectangle {
            width: Style.space(88); height: Style.space(34); radius: root.radius
            color: discardMouse.containsMouse ? Qt.lighter(root.urgent, 1.1) : root.urgent
            Text { text: "Discard"; color: root.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
            MouseArea { id: discardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.confirmDiscard = false; root.dirty = false; root.cancelRequested() } }
          }
        }
      }
    }
  }

  PathPicker {
    id: pathPicker
    anchors.fill: parent
    backendPath: root.backendPath
    foreground: root.foreground
    background: root.background
    accent: root.accent
    fontFamily: root.fontFamily
    onAccepted: function(path) {
      root.applyPickedPath(path)
      Qt.callLater(function() { primaryField.forceActiveFocus() })
    }
    onCanceled: Qt.callLater(function() { primaryField.forceActiveFocus() })
  }
}
