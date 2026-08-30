import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One row per setup, plus Auto on top. Clicking a row pins that arrangement;
// the capture button on the right saves however the screens are placed right
// now into that row, which is the only way profiles ever get filled in.
Panel {
  id: root
  moduleName: "themo.monitor-profiles"
  // Everything IPC lives on "<plugin id>.control", never on the bare plugin id:
  // that name does not survive a shell restart for a bar-widget plugin -- calls
  // to it come back "Target not found" -- while the sub-target is registered
  // reliably. manageIpc is off because this component registers it below.
  ipcTarget: "themo.monitor-profiles.control"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var profiles: service ? service.profiles : []
  readonly property string active: service ? service.active : "auto"
  readonly property string effectiveId: service ? service.effectiveId : ""
  readonly property string autoId: service ? service.autoId : ""
  readonly property string errorText: service ? service.error : ""
  readonly property bool busy: service ? service.busy : false

  readonly property string glyphAuto: "󰀘"
  readonly property string glyphSingle: "󰍹"
  readonly property string glyphMulti: "󰍺"
  readonly property string glyphCapture: "󰆓"
  readonly property string glyphActive: "󰄬"
  readonly property string glyphDelete: "󰆴"
  readonly property string glyphNew: "󰐕"

  // Auto is a row like any other, so one Repeater and one set of key handlers
  // cover the whole list.
  // "New setup" is a row like the others so that one Repeater and one set of
  // key handlers still cover the whole list -- it is reachable with the arrow
  // keys and Return, not only with the mouse. Its id cannot collide with a
  // profile's: ID_RE does not allow a "+".
  readonly property string newRowId: "+new"
  readonly property int maxProfiles: service ? service.maxProfiles : 12

  readonly property var rows: {
    var out = [{ "id": "auto", "isAuto": true, "isNew": false }]
    for (var i = 0; i < profiles.length; i++)
      out.push({ "id": profiles[i].id, "isAuto": false, "isNew": false,
                 "profile": profiles[i] })
    if (profiles.length < maxProfiles)
      out.push({ "id": newRowId, "isAuto": false, "isNew": true })
    return out
  }

  // Keyboard cursor, tracked by id so a refresh that reorders the list cannot
  // silently move the selection onto a different setup.
  property string cursorId: "auto"

  readonly property int cursorIndex: {
    for (var i = 0; i < rows.length; i++)
      if (rows[i].id === cursorId) return i
    return 0
  }

  function moveCursor(step) {
    if (!rows.length) return
    var next = (cursorIndex + step + rows.length) % rows.length
    cursorId = rows[next].id
  }

  function open() { root.controller.show(); refresh() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function refresh() { if (service) service.refresh() }

  // Drives the panel from a keybinding or a script:
  //   omarchy-shell themo.monitor-profiles.control toggle
  //   omarchy-shell themo.monitor-profiles.control use desk
  // use/capture call the same functions a click on a row does, so a binding and
  // the mouse cannot drift apart. The bar builds one panel per screen and both
  // register this target; the first wins and the second logs a warning, which
  // is harmless -- either one drives the same profiles.json.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function use(id: string): string { root.applyRow(id); return "ok" }
    function capture(id: string): string { root.captureRow(id); return "ok" }
    // add names a setup and saves the screens into it in one go; remove deletes
    // one outright. The panel's two-click confirmation is a guard against a
    // misclick, not a rule -- a script that asks for a delete has decided.
    function add(name: string): string { root.commitCreate(name); return "ok" }
    function remove(id: string): string {
      if (root.service) root.service.remove(id)
      return "ok"
    }
    function cycle(): string { if (root.service) root.service.cycle(1); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
  }

  // ---- Creating and deleting ---------------------------------------------

  property bool creating: false
  // Deleting throws away a captured arrangement, so it takes two clicks: the
  // first arms this, the second does it. Anything else disarms it again.
  property string pendingDeleteId: ""

  // The field lives inside the Repeater delegate, where its id is out of reach
  // from here, so it takes its own focus when it appears and hands the typed
  // name back rather than being read out of.
  function startCreating() {
    if (busy || profiles.length >= maxProfiles) return
    pendingDeleteId = ""
    cursorId = newRowId
    creating = true
  }

  function cancelCreating() {
    creating = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitCreate(name) {
    var wanted = String(name || "").trim()
    if (wanted === "") { cancelCreating(); return }
    // The helper turns the name into an id and then captures the screens as
    // they are right now -- arrange, name, saved.
    if (service) service.add(wanted)
    cancelCreating()
  }

  function deleteRow(id) {
    if (!service || busy || id === "auto" || id === newRowId) return
    if (pendingDeleteId === id) {
      pendingDeleteId = ""
      service.remove(id)
      return
    }
    pendingDeleteId = id
    deleteArmed.restart()
  }

  function disarmDelete() {
    pendingDeleteId = ""
    deleteArmed.stop()
  }

  // An armed delete that nobody confirms goes back to sleep rather than
  // waiting for the next visit to the panel.
  Timer {
    id: deleteArmed
    interval: 4000
    repeat: false
    onTriggered: root.pendingDeleteId = ""
  }

  onOpenedChanged: {
    if (!opened) {
      disarmDelete()
      creating = false
    }
  }

  function applyRow(id) {
    if (id === newRowId) { root.startCreating(); return }
    disarmDelete()
    if (!service || busy) return
    service.use(id)
  }

  function captureRow(id) {
    if (!service || busy || id === "auto" || id === newRowId) return
    disarmDelete()
    service.capture(id)
  }

  // Profile names and connector names both come from a file the user edits by
  // hand. Everything below renders them as PlainText; this bounds the length so
  // one very long name cannot push the rest of a row off the panel.
  readonly property int maxField: 60

  function safe(value) {
    return String(value === undefined || value === null ? "" : value).substring(0, maxField)
  }

  function profileName(profile) {
    if (!profile) return ""
    return safe(profile.name && profile.name !== "" ? profile.name : profile.id)
  }

  function profileIcon(profile) {
    if (!profile) return glyphSingle
    if (profile.icon && profile.icon !== "") return safe(profile.icon)
    return (profile.monitors && profile.monitors.length > 1) ? glyphMulti : glyphSingle
  }

  function outputSummary(profile) {
    if (!profile || !profile.monitors || !profile.monitors.length)
      return "empty — press 󰆓 to save the current arrangement here"

    var names = []
    for (var i = 0; i < profile.monitors.length && i < 6; i++) {
      names.push(safe(profile.monitors[i].output)
        + (profile.monitors[i].disabled ? " (off)" : ""))
    }
    if (profile.monitors.length > names.length)
      names.push("+" + (profile.monitors.length - names.length))

    var line = names.join(", ")
    return profile.matches ? line : line + " — not connected"
  }

  function autoSummary() {
    if (autoId === "") return "no saved setup matches the connected screens"
    var picked = null
    for (var i = 0; i < profiles.length; i++)
      if (profiles[i].id === autoId) picked = profiles[i]
    return "follows the connected screens — now: " + profileName(picked)
  }

  readonly property int rowHeight: Style.space(46)

  readonly property int desiredHeight:
    Style.space(96) + rowHeight * Math.max(1, rows.length)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(root.desiredHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.applyRow(root.cursorId)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Keys.onUpPressed: root.moveCursor(-1)
      Keys.onDownPressed: root.moveCursor(1)

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        // -------------------------------------------------------- header
        Item {
          width: parent.width
          height: Math.max(headline.implicitHeight, editButton.implicitHeight) + Style.space(6)

          Row {
            id: headline
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: "Displays"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: {
                if (root.errorText !== "") return root.safe(root.errorText)
                if (root.busy) return "applying…"
                return root.active === "auto" ? "auto" : "pinned"
              }
              color: root.errorText !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelActionButton {
            id: editButton
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰏫"
            tooltipText: "Edit profiles.json"
            onClicked: { if (root.service) root.service.editConfig(); root.close() }
          }
        }

        PanelSeparator { width: parent.width }

        // --------------------------------------------------------- rows
        Flickable {
          id: rowScroll
          width: parent.width
          height: parent.height - y
          contentWidth: width
          contentHeight: rowColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: rowColumn
            width: rowScroll.width

            Repeater {
              model: root.rows

              Rectangle {
                id: row
                width: rowColumn.width
                height: root.rowHeight

                readonly property bool isAuto: modelData.isAuto
                readonly property bool isNew: modelData.isNew === true
                readonly property bool armed: root.pendingDeleteId === modelData.id
                readonly property var profile: modelData.profile || null
                readonly property bool pinned: root.active === modelData.id
                readonly property bool onScreen: !isAuto && root.effectiveId === modelData.id
                readonly property bool hovered: rowMouse.containsMouse
                readonly property bool cursored: root.cursorId === modelData.id

                color: row.pinned
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                  : (row.hovered || row.cursored
                     ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                     : "transparent")
                radius: Style.space(4)

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.cursorId = modelData.id
                  onClicked: root.applyRow(modelData.id)
                }

                Text {
                  id: rowIcon
                  textFormat: Text.PlainText
                  text: row.isAuto ? root.glyphAuto
                    : row.isNew ? root.glyphNew : root.profileIcon(row.profile)
                  color: row.pinned ? root.accent
                    : row.isNew ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.left: rowIcon.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: rowActions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    // Profile names come from a hand-edited file; without this
                    // Qt guesses whether to render them as markup.
                    textFormat: Text.PlainText
                    visible: !(row.isNew && root.creating)
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.isAuto ? "Auto"
                      : row.isNew ? "New setup" : root.profileName(row.profile)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  TextField {
                    id: nameField
                    visible: row.isNew && root.creating
                    width: parent.width
                    placeholderText: "Name this setup, then Return"
                    foreground: root.foreground
                    font.family: root.fontFamily

                    onVisibleChanged: {
                      if (!visible) return
                      text = ""
                      Qt.callLater(function() { nameField.forceActiveFocus() })
                    }

                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        root.cancelCreating()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return
                                 || event.key === Qt.Key_Enter) {
                        root.commitCreate(nameField.text)
                        event.accepted = true
                      }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: {
                      if (row.isAuto) return root.autoSummary()
                      if (row.isNew)
                        return "saves the screens as they are now under a name you pick"
                      if (row.armed) return "click the bin again to delete this setup"
                      return root.outputSummary(row.profile)
                    }
                    color: row.armed ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: root.glyphActive
                    visible: row.onScreen || (row.isAuto && root.active === "auto")
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PanelActionButton {
                    visible: !row.isAuto && !row.isNew
                    iconText: root.glyphCapture
                    tooltipText: "Save the current arrangement into this setup"
                    enabled: !root.busy
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.captureRow(modelData.id)
                  }

                  PanelActionButton {
                    visible: !row.isAuto && !row.isNew
                    iconText: root.glyphDelete
                    tooltipText: row.armed ? "Click again to delete this setup"
                      : "Delete this setup"
                    // Armed is worth seeing before the second click lands.
                    foreground: row.armed ? root.urgent : root.foreground
                    enabled: !root.busy
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.deleteRow(modelData.id)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
