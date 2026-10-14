import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "GuideModel.js" as GuideModel

Item {
  id: root

  property var service: null
  property bool delayedVisible: false
  property int focusRevision: 0

  readonly property bool eligible: service ? GuideModel.eligible({
    integrationState: service.integrationState,
    catalogState: service.catalogState,
    lockStateKnown: service.lockStateKnown,
    desktopLocked: service.desktopLocked,
    credentialPromptStateKnown: service.credentialPromptStateKnown,
    credentialPromptActive: service.credentialPromptActive,
    activeWindowFullscreen: service.activeWindowFullscreen,
    showInFullscreen: service.showInFullscreen
  }) : false
  readonly property int delayValue: service ? Number(service.guideDelayMs) : -1
  readonly property int keyFontSize: Math.max(26, Style.font.displayLarge * 0.95)
  readonly property int pillHorizontalPadding: Style.space(32)
  readonly property int pillScreenGutter: Style.space(24)
  readonly property int maximumHintRows: 3
  readonly property int hintRowSpacing: Style.space(8)
  readonly property int hintFadeDurationMs: 180
  readonly property real hintPillHeight: pillHeightSample.implicitHeight
    + Style.space(10) + Style.space(18)
  readonly property real maximumHintStackHeight: maximumHintRows * hintPillHeight
    + (maximumHintRows - 1) * hintRowSpacing
  readonly property color pillFill: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.84)
  readonly property color pillOutline: Color.accent
  readonly property color keyOutline: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9)
  readonly property string currentMask: service && String(service.activeModifiers || "") !== ""
    ? String(service.activeModifiers)
    : service && String(service.activeGuideRoot || "") !== "" ? String(service.activeGuideRoot) : "SUPER"
  readonly property string currentGuideRoot: service && String(service.activeGuideRoot || "") !== ""
    ? String(service.activeGuideRoot) : "SUPER"
  readonly property bool showPrefixRow: service && service.guideVisible === true
    && String(service.activeGuideRoot || "") !== "" && eligible && delayedVisible
    && GuideModel.hasMatchingPrefix(service.catalog, currentMask, currentGuideRoot)
  readonly property var hintRows: GuideModel.hintRows(
    service ? service.catalog : null,
    service && Array.isArray(service.activeHintIds) ? service.activeHintIds : [],
    service && Array.isArray(service.recentHintEntries) ? service.recentHintEntries : [],
    currentMask,
    currentGuideRoot,
    showPrefixRow)
  readonly property var hintRowSlots: {
    var rows = hintRows
    var slots = [null, null, null]
    if (!Array.isArray(rows) || rows.length === 0) return slots

    var last = rows[rows.length - 1]
    var hasCurrentRow = last && (last.active === true
      || String(last.key || "").indexOf("prefix:") === 0)
    if (hasCurrentRow) {
      var historyCount = Math.min(rows.length - 1, maximumHintRows - 1)
      var historyStart = maximumHintRows - 1 - historyCount
      for (var historyIndex = 0; historyIndex < historyCount; historyIndex++)
        slots[historyStart + historyIndex] = rows[historyIndex]
      slots[maximumHintRows - 1] = last
    } else {
      var visibleHistoryCount = Math.min(rows.length, maximumHintRows - 1)
      var visibleHistoryStart = maximumHintRows - 1 - visibleHistoryCount
      for (var visibleIndex = 0; visibleIndex < visibleHistoryCount; visibleIndex++)
        slots[visibleHistoryStart + visibleIndex] = rows[rows.length - visibleHistoryCount + visibleIndex]
    }
    return slots
  }
  readonly property bool hasHintHistory: service && Array.isArray(service.recentHintEntries)
    && service.recentHintEntries.length > 0
  readonly property bool hintVisible: eligible && hintRows.length > 0
    && (delayedVisible || hasHintHistory)

  Text {
    id: pillHeightSample
    visible: false
    text: "M"
    color: "transparent"
    font.family: Style.font.family
    font.pixelSize: root.keyFontSize
    font.weight: Font.Medium
    font.letterSpacing: Style.space(1)
  }

  function focusedScreenName() {
    var revision = focusRevision
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function syncVisibility() {
    var mode = GuideModel.delayMode(service && service.guideVisible === true, delayValue)
    if (!eligible || delayValue < 0 || mode === "disabled") {
      if (service && service.clearGuide)
        service.clearGuide(!eligible ? "guide-ineligible" : "guide-delay-disabled")
      hideGuide()
      return
    }
    if (mode === "hidden") {
      hideGuide()
      return
    }
    if (mode === "immediate") {
      guideDelayTimer.stop()
      delayedVisible = true
      return
    }
    if (!delayedVisible) {
      guideDelayTimer.interval = delayValue
      guideDelayTimer.restart()
    }
  }

  function hideGuide() {
    guideDelayTimer.stop()
    delayedVisible = false
  }

  Timer {
    id: guideDelayTimer
    repeat: false
    onTriggered: {
      if (root.eligible && root.service && root.service.guideVisible === true)
        root.delayedVisible = true
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onGuideVisibleChanged() { root.syncVisibility() }
    function onGuideDelayMsChanged() { root.syncVisibility() }
    function onIntegrationStateChanged() { root.syncVisibility() }
    function onCatalogStateChanged() { root.syncVisibility() }
    function onDesktopLockedChanged() { root.syncVisibility() }
    function onCredentialPromptActiveChanged() { root.syncVisibility() }
    function onActiveWindowFullscreenChanged() { root.syncVisibility() }
    function onShowInFullscreenChanged() { root.syncVisibility() }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { root.focusRevision += 1 }
  }

  Component.onCompleted: syncVisibility()

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: hintWindow
        required property var modelData
        property bool hintFadeHold: false
        property bool hintWasVisible: false

        screen: modelData
        visible: GuideModel.focusedVisible(
          root.eligible && (root.hintVisible || hintFadeHold),
          modelData ? modelData.name : "",
          root.focusedScreenName())
        color: "transparent"
        implicitHeight: root.maximumHintStackHeight + Style.space(36)
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; left: true; right: true }

        WlrLayershell.namespace: "chordlight-guide"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        onVisibleChanged: {
          if (visible && root.service && root.service.recordGuideVisible)
            root.service.recordGuideVisible()
        }

        Component.onCompleted: hintWasVisible = root.hintVisible

        Connections {
          target: root
          function onHintVisibleChanged() {
            if (root.hintVisible) {
              hintWindow.hintWasVisible = true
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            } else if (hintWindow.hintWasVisible && root.eligible) {
              hintWindow.hintWasVisible = false
              hintWindow.hintFadeHold = true
              hintFadeTimer.restart()
            } else {
              hintWindow.hintWasVisible = false
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            }
          }

          function onEligibleChanged() {
            if (!root.eligible) {
              hintWindow.hintWasVisible = false
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            }
          }
        }

        Timer {
          id: hintFadeTimer
          interval: root.hintFadeDurationMs
          repeat: false
          onTriggered: hintWindow.hintFadeHold = false
        }

        Item {
          id: screenHost
          anchors.fill: parent

          Item {
            id: hintStack
            width: parent.width
            height: root.maximumHintStackHeight
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(18)

            Repeater {
              model: root.maximumHintRows

              delegate: BorderSurface {
                id: hintPill
                required property int index

                readonly property var rowModel: root.hintRowSlots[index] || null
                property var exitingRowModel: null
                property bool isFadingOut: false
                readonly property var displayedRowModel: rowModel
                  || (isFadingOut ? exitingRowModel : null)
                readonly property string rowCombo: String(displayedRowModel ? displayedRowModel.combo || "" : "")
                readonly property string rowDescription: String(displayedRowModel ? displayedRowModel.description || "" : "")
                readonly property var rowKeys: GuideModel.comboParts(rowCombo)

                visible: displayedRowModel !== null
                x: (hintStack.width - width) / 2
                y: hintStack.height - height
                  - (root.maximumHintRows - index - 1) * (height + root.hintRowSpacing)
                width: Math.max(0, Math.min(
                  contentRow.implicitWidth + root.pillHorizontalPadding,
                  screenHost.width - root.pillScreenGutter * 2))
                height: root.hintPillHeight
                implicitWidth: width
                implicitHeight: height
                opacity: rowModel ? Number(rowModel.opacity) : 0
                scale: displayedRowModel ? Number(displayedRowModel.scale || 1) : 1
                color: root.pillFill
                borderSpec: Border.flat(root.pillOutline, Math.max(2, Style.space(2)))
                radius: height / 2

                Behavior on opacity {
                  NumberAnimation { duration: root.hintFadeDurationMs; easing.type: Easing.OutCubic }
                }

                Behavior on scale {
                  NumberAnimation { duration: root.hintFadeDurationMs; easing.type: Easing.OutCubic }
                }

                onRowModelChanged: {
                  if (rowModel !== null) {
                    exitFadeTimer.stop()
                    isFadingOut = false
                    exitingRowModel = rowModel
                  } else if (exitingRowModel !== null) {
                    isFadingOut = true
                    exitFadeTimer.restart()
                  }
                }

                Component.onCompleted: {
                  if (rowModel !== null)
                    exitingRowModel = rowModel
                }

                Timer {
                  id: exitFadeTimer
                  interval: root.hintFadeDurationMs
                  repeat: false
                  onTriggered: {
                    hintPill.isFadingOut = false
                    hintPill.exitingRowModel = null
                  }
                }

                Row {
                  id: contentRow
                  anchors.centerIn: parent
                  spacing: Style.space(10)

                  Row {
                    id: keyRow
                    spacing: Style.space(8)

                    Repeater {
                      model: hintPill.rowKeys

                      delegate: Row {
                        required property string modelData
                        required property int index
                        spacing: Style.space(6)

                        Text {
                          visible: index > 0
                          text: "+"
                          color: Color.accent
                          font.family: Style.font.family
                          font.pixelSize: root.keyFontSize * 0.8
                          font.weight: Font.Medium
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        BorderSurface {
                          width: keyLabel.implicitWidth + Style.space(20)
                          height: keyLabel.implicitHeight + Style.space(10)
                          implicitWidth: width
                          implicitHeight: height
                          color: "transparent"
                          borderSpec: Border.flat(root.keyOutline, Math.max(2, Style.space(2)))
                          radius: Math.max(Style.cornerRadius, Style.space(8))

                          Text {
                            id: keyLabel
                            anchors.centerIn: parent
                            text: String(modelData || "").toUpperCase()
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: root.keyFontSize
                            font.weight: Font.Medium
                            font.letterSpacing: Style.space(1)
                          }
                        }
                      }
                    }
                  }

                  Text {
                    id: descriptionLabel
                    readonly property real availableWidth: Math.max(0,
                      screenHost.width - keyRow.implicitWidth - contentRow.spacing
                      - root.pillHorizontalPadding - root.pillScreenGutter * 2)
                    visible: hintPill.rowDescription !== "" && availableWidth > 0
                    width: hintPill.rowDescription === "" ? 0 : Math.min(implicitWidth, availableWidth)
                    text: hintPill.rowDescription
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: root.keyFontSize * 0.8
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    anchors.verticalCenter: parent.verticalCenter
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
