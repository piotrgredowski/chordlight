import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.zaremb.chordlight"

  property var service: null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string statusMark: !service || service.integrationState === "disabled"
    ? " ·" : service.integrationState === "error" ? " !" : service.integrationState === "disconnected" ? " ?" : ""
  readonly property string statusGlyph: statusMark.trim()
  readonly property string tooltipSummary: service && service.integrationState === "enabled"
    ? "Chordlight keyboard shortcuts enabled"
    : service && service.integrationState === "disconnected"
      ? "Chordlight keyboard shortcuts disconnected"
      : service && service.integrationState === "error"
        ? "Chordlight needs attention"
        : "Set up Chordlight keyboard shortcuts"

  function syncService() {
    service = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor(moduleName) : null
  }

  onServiceChanged: if (panelLoader.item) panelLoader.item.service = service

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: syncService()
  Component.onCompleted: syncService()

  Timer {
    interval: 250
    repeat: true
    running: root.service === null
    onTriggered: root.syncService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      item.bar = root.bar
      // Anchor to the registered bar-widget surface. It has the reliable
      // QsWindow relationship used by KeyboardPanel even when the nested
      // visual button is incubated before the bar finishes configuring it.
      item.anchorItem = root
      item.hostWidget = root
      item.service = root.service
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    labelVisible: false
    fixedWidth: root.statusGlyph.length > 0 ? 35 : 26
    tooltipText: root.tooltipSummary
    fontSize: Style.font.body

    ChordCompactPillMark {
      x: (26 - width * scale) / 2
      y: (parent.height - height * scale) / 2
      transformOrigin: Item.TopLeft
      scale: 0.92
      iconColor: button.foreground
      enabled: false
    }

    Text {
      visible: root.statusGlyph.length > 0
      x: 26
      width: 8
      height: parent.height
      text: root.statusGlyph
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Math.max(8, button.fontSize * 0.75)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.toggle()
    }
  }
}
