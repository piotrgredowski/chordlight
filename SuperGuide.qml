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
  readonly property color pillFill: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.84)
  readonly property color pillOutline: Color.accent
  readonly property color keyOutline: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9)
  readonly property string currentMask: service && String(service.activeModifiers || "") !== ""
    ? String(service.activeModifiers)
    : service && String(service.activeGuideRoot || "") !== "" ? String(service.activeGuideRoot) : "SUPER"
  readonly property string currentGuideRoot: service && String(service.activeGuideRoot || "") !== ""
    ? String(service.activeGuideRoot) : "SUPER"
  readonly property var currentBinding: GuideModel.hintBinding(
    service ? service.catalog : null,
    service && Array.isArray(service.activeHintIds) ? service.activeHintIds : [],
    service ? service.lingeringHintId : "")
  readonly property string hintCombo: currentHintCombo()
  readonly property string hintDescription: GuideModel.displayDescription(currentBinding)
  readonly property var hintKeys: GuideModel.comboParts(hintCombo)
  readonly property bool hintVisible: eligible && hintCombo !== ""
    && (delayedVisible || (service && String(service.lingeringHintId || "") !== ""))

  function currentHintBinding() {
    return currentBinding
  }

  function currentHintCombo() {
    var binding = currentHintBinding()
    if (binding) return GuideModel.displayCombo(binding)
    if (GuideModel.hasMatchingPrefix(service ? service.catalog : null, currentMask, currentGuideRoot))
      return currentMask.split("_").join(" + ")
    return ""
  }

  function focusedScreenName() {
    var revision = focusRevision
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function syncVisibility() {
    var mode = GuideModel.delayMode(service && service.guideVisible === true, delayValue)
    if (!eligible || delayValue < 0 || mode === "disabled") {
      if (service && service.cancelHintLinger) service.cancelHintLinger()
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

        screen: modelData
        visible: GuideModel.focusedVisible(
          root.hintVisible,
          modelData ? modelData.name : "",
          root.focusedScreenName())
        color: "transparent"
        implicitHeight: hintSurface.height + Style.space(36)
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

        Item {
          id: screenHost
          anchors.fill: parent

          BorderSurface {
            id: hintSurface
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(18)
            width: Math.max(0, Math.min(
              contentRow.implicitWidth + root.pillHorizontalPadding,
              screenHost.width - root.pillScreenGutter * 2))
            height: contentRow.implicitHeight + Style.space(18)
            implicitWidth: width
            implicitHeight: height
            color: root.pillFill
            borderSpec: Border.flat(root.pillOutline, Math.max(2, Style.space(2)))
            radius: height / 2

            Row {
              id: contentRow
              anchors.centerIn: parent
              spacing: Style.space(10)

              Row {
                id: keyRow
                spacing: Style.space(8)

                Repeater {
                  model: root.hintKeys

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
                visible: root.hintDescription !== "" && availableWidth > 0
                width: root.hintDescription === "" ? 0 : Math.min(implicitWidth, availableWidth)
                text: root.hintDescription
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
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
