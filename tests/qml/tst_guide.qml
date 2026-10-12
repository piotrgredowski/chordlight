import QtQuick 2.15
import QtTest 1.3
import "../../GuideModel.js" as GuideModel

TestCase {
  name: "ChordlightGuideModel"

  function binding(number, modifiers, trackable, eligible) {
    return {
      id: "sha256:" + String(number).repeat(64),
      combo: modifiers.join(" + ") + " + KEY" + number,
      modifiers: modifiers,
      key: "KEY" + number,
      xkbCodes: [number + 10],
      description: "Command " + number,
      category: "other",
      phase: "press",
      submap: "",
      dispatcherKind: "exec",
      trackable: trackable === undefined ? true : trackable,
      guideEligible: eligible === undefined ? true : eligible,
      repeat: false
    }
  }

  function catalog() {
    var unresolved = binding(5, ["CTRL"])
    unresolved.xkbCodes = []
    var bindings = [
      binding(1, ["SUPER"]),
      binding(2, ["SUPER", "SHIFT"]),
      binding(3, ["SUPER", "CTRL"], false),
      binding(4, ["ALT"], true, false),
      unresolved
    ]
    var byId = {}
    for (var i = 0; i < bindings.length; i++) byId[bindings[i].id] = bindings[i]
    return { bindings: bindings, byId: byId }
  }

  function test_outlinesOnlyRegisteredModifierPrefixes() {
    var source = catalog()
    verify(GuideModel.hasMatchingPrefix(source, "SUPER", "SUPER"))
    verify(GuideModel.hasMatchingPrefix(source, "SUPER_SHIFT", "SUPER"))
    verify(GuideModel.hasMatchingPrefix(source, "SHIFT", "SHIFT"))
    verify(!GuideModel.hasMatchingPrefix(source, "SUPER_CTRL", "SUPER"))
    verify(!GuideModel.hasMatchingPrefix(source, "ALT", "ALT"))
    verify(!GuideModel.hasMatchingPrefix(source, "CTRL", "CTRL"))
    verify(!GuideModel.hasMatchingPrefix(source, "SUPER", "ALT"))
  }

  function test_chordLabelsBecomeOutlinedKeyParts() {
    var parts = GuideModel.comboParts("SUPER + SPACE")
    compare(parts.length, 2)
    compare(parts[0], "SUPER")
    compare(parts[1], "SPACE")
    var fullParts = GuideModel.comboParts("SUPER + SHIFT + SPACE")
    compare(fullParts.length, 3)
    compare(fullParts[2], "SPACE")
    var plusKey = GuideModel.comboParts("SUPER + +")
    compare(plusKey.length, 2)
    compare(plusKey[1], "+")

    var coded = binding(20, ["SUPER"])
    coded.key = "code:20"
    coded.combo = "SUPER + code:20"
    compare(GuideModel.displayCombo(coded), "SUPER + KEY 20")
  }

  function test_hintDescriptionUsesActiveThenLingeringRegisteredBinding() {
    var source = catalog()
    var first = source.bindings[0]
    var second = source.bindings[1]
    var current = GuideModel.hintBinding(source, [first.id, second.id], first.id)
    compare(current.id, second.id)
    compare(GuideModel.displayDescription(current), "Command 2")

    var lingering = GuideModel.hintBinding(source, [], first.id)
    compare(lingering.id, first.id)
    compare(GuideModel.displayDescription(lingering), "Command 1")
    verify(GuideModel.hintBinding(source, [], "") === null)
    verify(GuideModel.hintBinding(source, [source.bindings[2].id], "") === null)

    var blank = binding(6, ["SUPER"])
    blank.description = "  "
    source.byId[blank.id] = blank
    compare(GuideModel.displayDescription(GuideModel.hintBinding(source, [], blank.id)), "")
  }

  function test_suppressionAndDelayModes() {
    var state = {
      integrationState: "enabled",
      catalogState: "ready",
      lockStateKnown: true,
      desktopLocked: false,
      credentialPromptStateKnown: true,
      credentialPromptActive: false,
      activeWindowFullscreen: false,
      showInFullscreen: false
    }
    verify(GuideModel.eligible(state))
    state.lockStateKnown = false
    verify(!GuideModel.eligible(state))
    state.lockStateKnown = true
    state.credentialPromptStateKnown = false
    verify(!GuideModel.eligible(state))
    state.credentialPromptStateKnown = true
    state.desktopLocked = true
    verify(!GuideModel.eligible(state))
    state.desktopLocked = false
    state.credentialPromptActive = true
    verify(!GuideModel.eligible(state))
    state.credentialPromptActive = false
    state.activeWindowFullscreen = true
    verify(!GuideModel.eligible(state))
    state.showInFullscreen = true
    verify(GuideModel.eligible(state))

    compare(GuideModel.delayMode(false, 0), "hidden")
    compare(GuideModel.delayMode(true, 0), "immediate")
    compare(GuideModel.delayMode(true, 80), "delayed")
    compare(GuideModel.delayMode(true, 150), "delayed")
    compare(GuideModel.delayMode(true, 250), "delayed")
    compare(GuideModel.delayMode(true, -1), "disabled")
  }

  function test_focusFollowsActiveMonitor() {
    verify(GuideModel.focusedVisible(true, "DP-1", "DP-1"))
    verify(!GuideModel.focusedVisible(true, "DP-1", "HDMI-A-1"))
    verify(!GuideModel.focusedVisible(false, "DP-1", "DP-1"))
    verify(!GuideModel.focusedVisible(true, "", "DP-1"))
  }
}
