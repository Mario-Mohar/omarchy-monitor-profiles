import QtQuick
import qs.Commons
import qs.Ui

// One pill showing the arrangement currently on screen. The profile list lives
// in the panel, so adding a fourth setup costs no bar space.
BarWidget {
  id: root
  moduleName: "themo.monitor-profiles"

  Service {
    id: profiles
    settings: root.settings
  }

  readonly property string glyphMulti: "󰍺"
  readonly property string glyphSingle: "󰍹"

  readonly property bool showLabel: profiles.boolSetting("showLabel", true)

  readonly property var current: profiles.effectiveProfile

  // The profile's own icon when it has one, otherwise something honest about
  // how many screens the arrangement covers.
  readonly property string icon: {
    if (!current) return glyphSingle
    if (current.icon && current.icon !== "") return current.icon
    return (current.monitors && current.monitors.length > 1) ? glyphMulti : glyphSingle
  }

  readonly property string label: current ? String(current.name || current.id) : "no profile"

  readonly property string barText: {
    if (root.vertical) return icon
    return showLabel ? icon + " " + label : icon
  }

  // Profile names come out of a file the user edits by hand, and the tooltip
  // component decides for itself whether to render rich text. Bound the length
  // and drop the one character that could turn a name into markup.
  readonly property int maxTooltipField: 80

  function tooltipSafe(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[<>]/g, "")
      .substring(0, root.maxTooltipField)
  }

  readonly property string tooltip: {
    if (profiles.error !== "") return "Monitor Profiles — " + tooltipSafe(profiles.error)
    if (!profiles.everLoaded) return "Monitor Profiles — reading profiles…"
    if (!current)
      return "Monitor Profiles — no profile matches the connected screens.\nClick to pick one."

    var lines = []
    lines.push(tooltipSafe(label)
      + (profiles.isAuto ? " (auto)" : " (pinned)"))
    var outputs = []
    var monitors = current.monitors || []
    for (var i = 0; i < monitors.length && i < 8; i++) {
      outputs.push(tooltipSafe(monitors[i].output)
        + (monitors[i].disabled ? " (off)" : ""))
    }
    if (outputs.length) lines.push(outputs.join(", "))
    lines.push("Click to switch · middle click cycles")
    return lines.join("\n")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("service" in target) target.service = profiles
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() { profiles.refresh() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // WidgetButton, not BarIconButton: the latter pins itself to a fixed glyph
  // slot, so a label next to the icon overflows into the next widget.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    labelVisible: true
    tooltipText: root.tooltip
    active: root.opened
    dimmed: profiles.error !== "" || !root.current

    onPressed: function(b) {
      if (b === Qt.MiddleButton) profiles.cycle(1)
      else root.togglePanel()
    }

    onWheelMoved: function(delta) { profiles.cycle(delta > 0 ? -1 : 1) }
  }
}
