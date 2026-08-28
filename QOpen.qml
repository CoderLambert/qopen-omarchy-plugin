import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by omarchy-shell.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "qopen.launcher"
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || ""
  readonly property string backendPath: pluginDir ? pluginDir + "/bin/qopen" : ""
  readonly property string configPath: Quickshell.env("HOME") + "/.config/qopen/config.json"

  onPluginDirChanged: {
    if (root.pluginDir) root.requestCatalogReload()
  }

  property bool opened: false
  property string query: ""
  property string selectedGroup: "all"
  property int selectedIndex: 0
  property bool cursorActive: true
  property var catalog: ({ version: 1, defaults: ({}), items: [] })
  property string configError: ""
  property string statusText: ""
  property bool statusError: false
  property bool editorOpen: false
  property var availableGroupIds: []
  property string pendingAction: ""
  property string pendingActionItemId: ""
  property string pendingResourceType: ""
  property bool pendingBrowse: false
  property string pendingSelectedId: ""
  property bool apiResponseHandled: false
  property bool catalogResponseHandled: false
  property bool catalogReloadPending: false
  property bool mutationResponseHandled: false
  property bool confirmDelete: false
  property var deleteCandidate: null
  property bool configMissing: false
  property string pendingCopyText: ""

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color subtle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color accent: Color.accent
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property int radius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var groupMetadata: ({
    "react-editors": { icon: "󰨞", label: "React · Rich Text", description: "Editors for product content" },
    "react-motion": { icon: "󰔎", label: "React · Motion", description: "Animation and transitions" },
    "react-icons": { icon: "󰀻", label: "React · Icons", description: "SVG icon systems" },
    "react-state": { icon: "󰘨", label: "React · State", description: "Application state" },
    "react-forms": { icon: "󰗀", label: "React · Forms", description: "Forms and validation" },
    "react-interaction": { icon: "󰇀", label: "React · Interaction", description: "A11y and interaction" },
    "tanstack": { icon: "󰬁", label: "TanStack", description: "Type-safe app primitives" },
    "frameworks": { icon: "", label: "Frameworks", description: "React frameworks and routing" },
    "ui": { icon: "󰏘", label: "UI Systems", description: "Components and styling" },
    "tooling": { icon: "󰒓", label: "Tooling", description: "Build and package tools" },
    "testing": { icon: "󰙨", label: "Testing", description: "Unit and browser testing" },
    "reference": { icon: "󰈙", label: "Web Reference", description: "Platform standards" },
    "dev": { icon: "󰊤", label: "Development", description: "Development services" },
    "docs": { icon: "󰈙", label: "Other Docs", description: "Additional documentation" },
    "projects": { icon: "󰉋", label: "Projects", description: "Local project directories" },
    "config": { icon: "", label: "Config Files", description: "Configuration files" },
    "tools": { icon: "", label: "Terminal Tools", description: "Interactive terminal apps" },
    "system": { icon: "󰘳", label: "Commands", description: "System commands" },
    "infra": { icon: "󰒍", label: "Infrastructure", description: "SSH and remote systems" },
    "web": { icon: "󰖟", label: "Web", description: "Web resources" }
  })

  readonly property var groupOrder: [
    "react-editors", "react-motion", "react-icons", "react-state",
    "react-forms", "react-interaction", "tanstack", "frameworks", "ui",
    "tooling", "testing", "reference", "dev", "docs", "projects",
    "config", "tools", "system", "infra", "web"
  ]

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.selectedGroup = payload.favorites ? "favorites" : String(payload.group || "all")
    root.query = String(payload.query || "")
    root.statusText = ""
    root.statusError = false
    root.editorOpen = false
    root.pendingAction = String(payload.action || "")
    root.pendingActionItemId = String(payload.item || "")
    root.pendingResourceType = String(payload.type || "")
    root.pendingBrowse = payload.browse === true
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("omarchy.menu")
    root.opened = true
    configFile.reload()
    Qt.callLater(function() {
      searchField.text = root.query
      if (!root.pendingAction) {
        searchField.forceActiveFocus()
        searchField.selectAll()
      }
    })
  }

  // Host-initiated close.
  function close() {
    root.opened = false
    root.editorOpen = false
    root.confirmDelete = false
    root.deleteCandidate = null
  }

  function dismiss() {
    if (root.confirmDelete) {
      root.cancelDelete()
      return
    }
    if (root.editorOpen && resourceEditor.dirty) {
      resourceEditor.requestCancel()
      return
    }
    root.opened = false
    root.confirmDelete = false
    root.deleteCandidate = null
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refresh() {
    configFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  function showStatus(message, isError) {
    root.statusText = String(message || "")
    root.statusError = isError === true
    statusTimer.restart()
  }

  function titleCase(value) {
    var words = String(value || "other").replace(/[-_]+/g, " ").split(" ")
    for (var i = 0; i < words.length; i++)
      if (words[i]) words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
    return words.join(" ")
  }

  function groupInfo(groupId) {
    var known = root.groupMetadata[groupId]
    return known || { icon: "󰉋", label: titleCase(groupId), description: "Resource collection" }
  }

  function groupRank(groupId) {
    var index = root.groupOrder.indexOf(groupId)
    return index < 0 ? root.groupOrder.length : index
  }

  function itemDetail(item) {
    if (item.description) return String(item.description)
    if (item.target) return String(item.target)
    if (Array.isArray(item.command)) return item.command.join(" ")
    return String(item.type || "resource")
  }

  function itemTarget(item) {
    if (item.target) return String(item.target)
    if (Array.isArray(item.command)) return item.command.join(" ")
    return ""
  }

  function searchableText(item) {
    return [
      item.id, item.name, item.type, item.group, item.description,
      item.target, Array.isArray(item.command) ? item.command.join(" ") : ""
    ].join(" ").toLowerCase()
  }

  function loadConfig(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed || !Array.isArray(parsed.items)) throw new Error("items must be an array")
      root.catalog = parsed
      root.configError = ""
      root.configMissing = false
      root.rebuildGroups()
      root.rebuildItems()
      root.runPendingAction()
      root.restorePendingSelection()
    } catch (e) {
      root.configError = "Cannot read config.json: " + e
      root.configMissing = false
      root.catalog = ({ version: 1, defaults: ({}), items: [] })
      root.rebuildGroups()
      root.rebuildItems()
    }
  }

  function requestCatalogReload() {
    if (!root.backendPath) return
    if (catalogProcess.running) {
      root.catalogReloadPending = true
      return
    }
    root.catalogResponseHandled = false
    catalogProcess.command = [root.backendPath, "api", "catalog"]
    catalogProcess.running = true
  }

  function handleCatalogResponse(raw) {
    if (root.catalogResponseHandled) return
    root.catalogResponseHandled = true
    if (root.catalogReloadPending) return
    try {
      var response = JSON.parse(String(raw || "{}"))
      if (!response.ok) {
        root.configError = String(response.error || "Cannot validate config.json")
        root.configMissing = false
        root.catalog = ({ version: 1, defaults: ({}), items: [] })
        root.rebuildGroups()
        root.rebuildItems()
        return
      }
      root.loadConfig(JSON.stringify(response.result || ({})))
    } catch (e) {
      root.configError = "Invalid catalog response: " + e
      root.configMissing = false
      root.catalog = ({ version: 1, defaults: ({}), items: [] })
      root.rebuildGroups()
      root.rebuildItems()
    }
  }

  function rebuildGroups() {
    var counts = ({})
    var favoriteCount = 0
    var items = root.catalog.items || []
    for (var i = 0; i < items.length; i++) {
      var groupId = String(items[i].group || "other")
      counts[groupId] = (counts[groupId] || 0) + 1
      if (items[i].favorite === true) favoriteCount++
    }

    var groups = Object.keys(counts)
    groups.sort(function(a, b) {
      var rank = root.groupRank(a) - root.groupRank(b)
      if (rank !== 0) return rank
      return root.groupInfo(a).label.localeCompare(root.groupInfo(b).label)
    })
    root.availableGroupIds = groups.slice()

    groupModel.clear()
    groupModel.append({ groupId: "all", icon: "󰍉", label: "All resources", count: items.length })
    groupModel.append({ groupId: "favorites", icon: "", label: "Favorites", count: favoriteCount })
    for (var j = 0; j < groups.length; j++) {
      var info = root.groupInfo(groups[j])
      groupModel.append({ groupId: groups[j], icon: info.icon, label: info.label, count: counts[groups[j]] })
    }
  }

  function rebuildItems() {
    var needle = root.query.trim().toLowerCase()
    var source = root.catalog.items || []
    var filtered = []
    for (var i = 0; i < source.length; i++) {
      var item = source[i]
      if (root.selectedGroup === "favorites" && item.favorite !== true) continue
      if (root.selectedGroup !== "all" && root.selectedGroup !== "favorites"
          && String(item.group || "other") !== root.selectedGroup) continue
      if (needle && root.searchableText(item).indexOf(needle) === -1) continue
      filtered.push(item)
    }

    filtered.sort(function(a, b) {
      if (!!a.favorite !== !!b.favorite) return a.favorite ? -1 : 1
      return String(a.name).localeCompare(String(b.name))
    })

    displayModel.clear()
    for (var j = 0; j < filtered.length; j++) {
      var row = filtered[j]
      displayModel.append({
        itemId: String(row.id),
        itemName: String(row.name),
        itemType: String(row.type),
        itemGroup: String(row.group || "other"),
        itemIcon: String(row.icon || "󰈙"),
        itemDescription: root.itemDetail(row),
        targetText: root.itemTarget(row),
        favorite: row.favorite === true
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
    root.cursorActive = displayModel.count > 0
    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function selectGroup(groupId) {
    root.selectedGroup = groupId
    root.selectedIndex = 0
    root.rebuildItems()
    searchField.forceActiveFocus()
  }

  function currentGroupTitle() {
    if (root.selectedGroup === "all") return "All resources"
    if (root.selectedGroup === "favorites") return "Favorites"
    return root.groupInfo(root.selectedGroup).label
  }

  function moveSelection(delta) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectedItemId() {
    if (displayModel.count === 0 || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return ""
    return String(displayModel.get(root.selectedIndex).itemId)
  }

  function findCatalogItem(itemId) {
    var items = root.catalog.items || []
    for (var i = 0; i < items.length; i++)
      if (String(items[i].id) === String(itemId)) return JSON.parse(JSON.stringify(items[i]))
    return null
  }

  function runPendingAction() {
    if (root.pendingAction === "edit" && root.pendingActionItemId) {
      var editItem = root.findCatalogItem(root.pendingActionItemId)
      root.pendingAction = ""
      root.pendingActionItemId = ""
      if (editItem) {
        root.editorOpen = true
        resourceEditor.beginEdit(editItem)
      }
      return
    }
    if (root.pendingAction !== "add") return
    var initialType = root.pendingResourceType
    var shouldBrowse = root.pendingBrowse
    root.pendingAction = ""
    root.pendingActionItemId = ""
    root.pendingResourceType = ""
    root.pendingBrowse = false
    root.editorOpen = true
    resourceEditor.beginCreate(root.selectedGroup, root.selectedGroup === "favorites", initialType)
    if (shouldBrowse) Qt.callLater(resourceEditor.openPathPicker)
  }

  function restorePendingSelection() {
    if (!root.pendingSelectedId) return
    for (var i = 0; i < displayModel.count; i++) {
      if (String(displayModel.get(i).itemId) === root.pendingSelectedId) {
        root.selectedIndex = i
        root.cursorActive = true
        resultList.positionViewAtIndex(i, ListView.Contain)
        break
      }
    }
    root.pendingSelectedId = ""
  }

  function launch(itemId) {
    if (!itemId || !root.backendPath) return
    root.dismiss()
    Qt.callLater(function() { Quickshell.execDetached([root.backendPath, itemId]) })
  }

  function manage(action, itemId) {
    if (!root.backendPath) return
    if (action === "add") {
      root.editorOpen = true
      resourceEditor.beginCreate(root.selectedGroup, root.selectedGroup === "favorites", "")
      return
    }
    if (action === "edit") {
      var item = root.findCatalogItem(itemId)
      if (!item) {
        root.showStatus("Resource no longer exists", true)
        return
      }
      root.editorOpen = true
      resourceEditor.beginEdit(item)
      return
    }
    if (action === "remove") {
      root.requestDelete(itemId)
      return
    }
    var args = [root.backendPath, action]
    if (itemId) args.push(itemId)
    root.dismiss()
    Qt.callLater(function() { Quickshell.execDetached(args) })
  }

  function editRawConfig() {
    if (!root.backendPath) return
    root.dismiss()
    Qt.callLater(function() { Quickshell.execDetached([root.backendPath, "--edit"]) })
  }

  function toggleFavorite(itemId) {
    if (!itemId || mutationProcess.running) return
    root.statusText = "Updating favorite…"
    root.statusError = false
    root.runMutation([root.backendPath, "api", "favorite", "--id", itemId, "--mode", "toggle"])
  }

  function copyTarget(value) {
    if (!value || copyProcess.running) return
    root.pendingCopyText = String(value)
    root.statusText = "Copying to clipboard…"
    root.statusError = false
    copyProcess.command = ["wl-copy", "--", root.pendingCopyText]
    copyProcess.running = true
  }

  function requestDelete(itemId) {
    var item = root.findCatalogItem(itemId)
    if (!item) {
      root.showStatus("Resource no longer exists", true)
      return
    }
    root.deleteCandidate = item
    root.confirmDelete = true
  }

  function cancelDelete() {
    root.confirmDelete = false
    root.deleteCandidate = null
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function confirmDeleteResource() {
    if (!root.deleteCandidate || mutationProcess.running) return
    var original = JSON.stringify(root.deleteCandidate)
    root.statusText = "Removing resource…"
    root.statusError = false
    root.confirmDelete = false
    root.runMutation([root.backendPath, "api", "delete", "--original", original])
  }

  function recoverCatalog() {
    if (mutationProcess.running) return
    root.statusText = "Restoring the last valid backup…"
    root.statusError = false
    root.runMutation([root.backendPath, "api", "recover"])
  }

  function runMutation(command) {
    if (mutationProcess.running) return
    root.mutationResponseHandled = false
    mutationProcess.command = command
    mutationProcess.running = true
  }

  function handleMutationResponse(raw) {
    if (root.mutationResponseHandled) return
    root.mutationResponseHandled = true
    try {
      var response = JSON.parse(String(raw || "{}"))
      if (!response.ok) {
        root.showStatus(response.error || "QOpen backend operation failed", true)
        return
      }
      if (response.action === "favorite")
        root.statusText = response.favorite === true ? "Added to favorites" : "Removed from favorites"
      else if (response.action === "delete")
        root.statusText = "Resource removed"
      else if (response.action === "recover")
        root.statusText = "Catalog restored from the last valid backup"
      else
        root.statusText = "Catalog updated"
      root.deleteCandidate = null
      configFile.reload()
      root.statusError = false
      statusTimer.restart()
    } catch (e) {
      root.showStatus("Invalid response from QOpen backend", true)
    }
  }

  function saveResource(action, payload, originalPayload) {
    if (apiProcess.running) {
      resourceEditor.saveFailed("Another save is already running")
      return
    }
    root.apiResponseHandled = false
    apiProcess.command = [root.backendPath, "api", action, "--payload", payload]
    if (action === "update") apiProcess.command.push("--original", originalPayload)
    apiProcess.running = true
  }

  function handleApiResponse(raw) {
    if (root.apiResponseHandled) return
    root.apiResponseHandled = true
    try {
      var response = JSON.parse(String(raw || "{}"))
      if (!response.ok) {
        resourceEditor.saveFailed(String(response.error || "Could not save the resource"))
        return
      }
      var item = response.item || ({})
      resourceEditor.saveSucceeded()
      root.editorOpen = false
      root.query = ""
      searchField.text = ""
      root.selectedGroup = String(item.group || "all")
      root.pendingSelectedId = String(item.id || "")
      var warnings = Array.isArray(response.warnings) ? response.warnings : []
      root.statusText = (response.action === "create" ? "Resource added" : "Resource updated")
        + (warnings.length ? " · " + warnings[0] : "")
      root.statusError = false
      statusTimer.restart()
      configFile.reload()
      Qt.callLater(function() { searchField.forceActiveFocus() })
    } catch (e) {
      resourceEditor.saveFailed("Invalid response from QOpen backend")
    }
  }

  ListModel { id: groupModel }
  ListModel { id: displayModel }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.requestCatalogReload()
    onLoadFailed: function(error) {
      root.configError = "Config not found. Add your first resource to create it."
      root.configMissing = true
      root.catalog = ({ version: 1, defaults: ({}), items: [] })
      root.rebuildGroups()
      root.rebuildItems()
      root.runPendingAction()
    }
    onFileChanged: reload()
  }

  Process {
    id: catalogProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        catalogFallbackTimer.stop()
        root.handleCatalogResponse(text)
      }
    }
    onExited: function(exitCode) {
      if (!root.catalogResponseHandled) catalogFallbackTimer.restart()
      if (root.catalogReloadPending) {
        root.catalogReloadPending = false
        Qt.callLater(root.requestCatalogReload)
      }
    }
  }

  Timer {
    id: catalogFallbackTimer
    interval: 120
    onTriggered: root.handleCatalogResponse('{"ok":false,"error":"QOpen catalog validation failed"}')
  }

  Process {
    id: mutationProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        mutationFallbackTimer.stop()
        root.handleMutationResponse(text)
      }
    }
    onExited: function(exitCode) {
      if (!root.mutationResponseHandled)
        mutationFallbackTimer.restart()
    }
  }

  Timer {
    id: mutationFallbackTimer
    interval: 120
    onTriggered: root.handleMutationResponse('{"ok":false,"error":"QOpen backend operation failed"}')
  }

  Process {
    id: copyProcess
    onExited: function(exitCode) {
      root.statusText = exitCode === 0 ? "Copied to clipboard" : "Could not copy to clipboard"
      root.statusError = exitCode !== 0
      root.pendingCopyText = ""
      statusTimer.restart()
    }
  }

  Process {
    id: apiProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        apiFallbackTimer.stop()
        root.handleApiResponse(text)
      }
    }
    onExited: function(exitCode) {
      if (!root.apiResponseHandled)
        apiFallbackTimer.restart()
    }
  }

  Timer {
    id: apiFallbackTimer
    interval: 120
    onTriggered: root.handleApiResponse('{"ok":false,"error":"QOpen backend failed"}')
  }

  Timer {
    id: statusTimer
    interval: 4000
    onTriggered: { root.statusText = ""; root.statusError = false }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "qopen-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1040), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(680), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: root.radius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.borderColor, Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent

        // Header
        Item {
          width: parent.width
          height: Style.space(82)

          Rectangle {
            width: Style.space(4)
            height: Style.space(38)
            radius: width / 2
            color: root.accent
            anchors.left: parent.left
            anchors.leftMargin: Style.space(24)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: logo
            text: "󰖟"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.leftMargin: Style.space(40)
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.left: logo.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "QOpen"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
            }
            Text {
              text: "One place for projects, docs, files and tools"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          TextField {
            id: searchField
            visible: !root.editorOpen
            width: Math.min(Style.space(390), parent.width * 0.4)
            anchors.right: addButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Search resources…"
            foreground: root.foreground

            onTextChanged: {
              if (root.query !== text) {
                root.query = text
                root.selectedIndex = 0
                root.rebuildItems()
              }
            }

            Keys.onPressed: function(event) {
              if (root.confirmDelete) {
                if (event.key === Qt.Key_Escape) root.cancelDelete()
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                  root.confirmDeleteResource()
                event.accepted = true
                return
              }
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              if (ctrl && event.key === Qt.Key_N) {
                root.manage("add", "")
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_E) {
                root.manage("edit", root.selectedItemId())
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_D) {
                root.manage("remove", root.selectedItemId())
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_R) {
                configFile.reload()
                root.statusText = "Catalog reloaded"
                root.statusError = false
                statusTimer.restart()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.launch(root.selectedItemId())
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (text) clear()
                else root.dismiss()
                event.accepted = true
              }
            }
          }

          Rectangle {
            id: addButton
            visible: !root.editorOpen
            width: Style.space(92)
            height: Style.space(36)
            radius: root.radius
            anchors.right: parent.right
            anchors.rightMargin: Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
            color: addMouse.containsMouse ? Qt.lighter(root.accent, 1.08) : root.accent

            Row {
              anchors.centerIn: parent
              spacing: Style.space(7)
              Text {
                text: ""
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: "Add"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
            }

            MouseArea {
              id: addMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.manage("add", "")
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            anchors.bottom: parent.bottom
            color: root.subtle
          }
        }

        // Main content
        Row {
          width: parent.width
          height: parent.height - Style.space(82) - Style.space(42)

          Rectangle {
            width: Style.space(232)
            height: parent.height
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(14)
              spacing: Style.space(10)

              Text {
                text: "COLLECTIONS"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: Style.space(1)
                leftPadding: Style.space(8)
              }

              ListView {
                id: groupList
                width: parent.width
                height: parent.height - rawConfigButton.height - parent.spacing * 2 - Style.space(18)
                model: groupModel
                clip: true
                spacing: Style.space(3)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: groupRow
                  required property int index
                  required property string groupId
                  required property string icon
                  required property string label
                  required property int count

                  readonly property bool active: root.selectedGroup === groupId
                  width: groupList.width
                  height: Style.space(38)
                  radius: root.radius
                  color: active ? root.selectedBackground : (groupMouse.containsMouse ? root.subtle : "transparent")

                  Rectangle {
                    visible: parent.active
                    width: Style.space(3)
                    height: Style.space(20)
                    radius: width / 2
                    color: root.accent
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: parent.icon
                    color: parent.active ? root.selectedText : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: parent.label
                    color: parent.active ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(38)
                    anchors.right: countText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: countText
                    text: String(parent.count)
                    color: parent.active ? root.selectedText : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  MouseArea {
                    id: groupMouse
                    anchors.fill: parent
                    enabled: !root.editorOpen
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectGroup(parent.groupId)
                  }
                }
              }

              Rectangle {
                id: rawConfigButton
                width: parent.width
                height: Style.space(36)
                radius: root.radius
                color: rawMouse.containsMouse ? root.subtle : "transparent"
                border.width: 1
                border.color: root.subtle

                Text {
                  text: "   Edit raw config"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.centerIn: parent
                }

                MouseArea {
                  id: rawMouse
                  anchors.fill: parent
                  enabled: !root.editorOpen
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.editRawConfig()
                }
              }
            }

            Rectangle {
              width: 1
              height: parent.height
              anchors.right: parent.right
              color: root.subtle
            }
          }

          Item {
            width: parent.width - Style.space(232)
            height: parent.height

            Column {
              id: browsePane
              visible: !root.editorOpen
              anchors.fill: parent
              anchors.margins: Style.space(18)
              spacing: Style.space(10)

              Item {
                width: parent.width
                height: Style.space(38)

                Column {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    text: root.currentGroupTitle()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.weight: Font.DemiBold
                  }
                  Text {
                    text: displayModel.count + (displayModel.count === 1 ? " resource" : " resources")
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  visible: root.query !== ""
                  text: "Filtering for “" + root.query + "”"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              ListView {
                id: resultList
                width: parent.width
                height: parent.height - Style.space(48)
                model: displayModel
                clip: true
                spacing: Style.space(6)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: resourceRow
                  required property int index
                  required property string itemId
                  required property string itemName
                  required property string itemType
                  required property string itemGroup
                  required property string itemIcon
                  required property string itemDescription
                  required property string targetText
                  required property bool favorite

                  readonly property bool selected: root.cursorActive && index === root.selectedIndex
                  width: resultList.width
                  height: Style.space(78)
                  radius: root.radius
                  color: selected ? root.selectedBackground : (rowMouse.containsMouse ? root.subtle : "transparent")
                  border.width: selected ? 1 : 0
                  border.color: selected ? Color.menu.selectedBorder : "transparent"

                  Rectangle {
                    width: Style.space(44)
                    height: Style.space(44)
                    radius: root.radius
                    color: parent.selected ? Qt.rgba(root.selectedText.r, root.selectedText.g, root.selectedText.b, 0.12) : root.subtle
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      text: itemIcon
                      color: parent.parent.selected ? root.selectedText : root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      anchors.centerIn: parent
                    }
                  }

                  Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(68)
                    anchors.right: actionRow.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Row {
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        text: itemName
                        color: resourceRow.selected ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, parent.width - typeBadge.width - parent.spacing)
                      }

                      Rectangle {
                        id: typeBadge
                        width: badgeText.implicitWidth + Style.space(12)
                        height: Style.space(19)
                        radius: height / 2
                        color: resourceRow.selected
                          ? Qt.rgba(root.selectedText.r, root.selectedText.g, root.selectedText.b, 0.12)
                          : root.subtle

                        Text {
                          id: badgeText
                          text: itemType.toUpperCase()
                          color: resourceRow.selected ? root.selectedText : root.muted
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(9, Style.font.caption - 1)
                          anchors.centerIn: parent
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      text: itemDescription + "  ·  " + root.groupInfo(itemGroup).label
                      color: resourceRow.selected ? Qt.rgba(root.selectedText.r, root.selectedText.g, root.selectedText.b, 0.68) : root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(142)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.cursorActive = true
                      root.selectedIndex = index
                    }
                    onClicked: root.launch(itemId)
                  }

                  Row {
                    id: actionRow
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)

                    PanelActionButton {
                      iconText: favorite ? "" : ""
                      tooltipText: favorite ? "Remove from favorites" : "Add to favorites"
                      foreground: parent.parent.selected ? root.selectedText : root.muted
                      hoverColor: root.accent
                      onClicked: root.toggleFavorite(itemId)
                    }
                    PanelActionButton {
                      iconText: ""
                      tooltipText: "Copy target"
                      enabled: targetText !== ""
                      foreground: parent.parent.selected ? root.selectedText : root.muted
                      onClicked: root.copyTarget(targetText)
                    }
                    PanelActionButton {
                      iconText: ""
                      tooltipText: "Edit resource"
                      foreground: parent.parent.selected ? root.selectedText : root.muted
                      onClicked: root.manage("edit", itemId)
                    }
                    PanelActionButton {
                      iconText: ""
                      tooltipText: "Remove resource"
                      foreground: parent.parent.selected ? root.selectedText : root.muted
                      hoverColor: Color.urgent
                      onClicked: root.manage("remove", itemId)
                    }
                  }
                }

                Column {
                  visible: displayModel.count === 0
                  anchors.centerIn: parent
                  spacing: Style.space(10)

                  Text {
                    width: parent.width
                    text: root.configError ? "󰅚" : "󰈉"
                    color: root.configError ? Color.urgent : root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                    horizontalAlignment: Text.AlignHCenter
                  }
                  Text {
                    width: Math.min(Style.space(420), resultList.width - Style.space(40))
                    text: root.configError || (root.query ? "No resources match your search" : "This collection is empty")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    text: root.configError
                      ? (root.configMissing ? "Press Ctrl+N to create your first resource"
                        : "Restore the last valid backup or edit the raw config")
                      : "Press Ctrl+N to add a resource"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                  }
                  Rectangle {
                    visible: root.configError !== "" && !root.configMissing
                    width: Style.space(176)
                    height: Style.space(36)
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: root.radius
                    color: recoverMouse.containsMouse ? Qt.lighter(root.accent, 1.08) : root.accent
                    Text {
                      text: "󰑐  Restore backup"
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.centerIn: parent
                    }
                    MouseArea {
                      id: recoverMouse
                      anchors.fill: parent
                      enabled: !mutationProcess.running
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.recoverCatalog()
                    }
                  }
                }
              }
            }

            ResourceEditor {
              id: resourceEditor
              visible: root.editorOpen
              anchors.fill: parent
              anchors.margins: Style.space(18)
              backendPath: root.backendPath
              availableGroups: root.availableGroupIds
              onCancelRequested: {
                root.editorOpen = false
                Qt.callLater(function() { searchField.forceActiveFocus() })
              }
              onSubmitRequested: function(action, payload, originalPayload) {
                root.saveResource(action, payload, originalPayload)
              }
            }
          }
        }

        // Footer
        Rectangle {
          width: parent.width
          height: Style.space(42)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)

          Rectangle {
            width: parent.width
            height: 1
            color: root.subtle
          }

          Text {
            text: root.statusText || (root.editorOpen
              ? "Tab move fields   Ctrl+Enter save   Esc cancel"
              : "↑↓ navigate   ↵ open   Ctrl+N add   Ctrl+E edit   Ctrl+D remove   Esc close")
            color: root.statusText ? (root.statusError ? Color.urgent : root.accent) : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
            anchors.leftMargin: Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "config.json · live"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.rightMargin: Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    Rectangle {
      visible: root.confirmDelete
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)
      z: 50
      MouseArea { anchors.fill: parent; onClicked: root.cancelDelete() }

      BorderSurface {
        width: Style.space(390)
        height: Style.space(190)
        anchors.centerIn: parent
        radius: root.radius
        color: root.background
        borderSpec: Border.surfaceSpec("menu", "border", root.borderColor, 1)

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(22)
          spacing: Style.space(13)

          Text {
            text: "Remove resource?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            text: root.deleteCandidate
              ? "“" + String(root.deleteCandidate.name || root.deleteCandidate.id) + "” will be removed from config.json."
              : "This resource will be removed from config.json."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Rectangle {
              width: Style.space(92); height: Style.space(36); radius: root.radius
              color: cancelDeleteMouse.containsMouse ? root.subtle : "transparent"
              border.width: 1; border.color: root.borderColor
              Text { text: "Cancel"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
              MouseArea { id: cancelDeleteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelDelete() }
            }
            Rectangle {
              width: Style.space(98); height: Style.space(36); radius: root.radius
              color: confirmDeleteMouse.containsMouse ? Qt.lighter(Color.urgent, 1.08) : Color.urgent
              Text { text: "Remove"; color: root.background; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.centerIn: parent }
              MouseArea { id: confirmDeleteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.confirmDeleteResource() }
            }
          }
        }
      }
    }
  }
}
