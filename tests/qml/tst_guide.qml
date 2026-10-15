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

  function test_hintDescriptionUsesActiveThenRecentRegisteredBinding() {
    var source = catalog()
    var first = source.bindings[0]
    var second = source.bindings[1]
    var history = [{ id: first.id, sequence: 1, expiresAt: 3000 }]
    var current = GuideModel.hintBinding(source, [first.id, second.id], history)
    compare(current.id, second.id)
    compare(GuideModel.displayDescription(current), "Command 2")

    var recent = GuideModel.hintBinding(source, [], history)
    compare(recent.id, first.id)
    compare(GuideModel.displayDescription(recent), "Command 1")
    verify(GuideModel.hintBinding(source, [], []) === null)
    verify(GuideModel.hintBinding(source, [source.bindings[2].id], []) === null)

    var blank = binding(6, ["SUPER"])
    blank.description = "  "
    source.byId[blank.id] = blank
    compare(GuideModel.displayDescription(GuideModel.hintBinding(source, [], [
      { id: blank.id, sequence: 2, expiresAt: 3000 }
    ])), "")
  }

  function test_shortHistoryStacksOldestToNewestAboveCurrentRow() {
    var source = catalog()
    var right = binding(6, ["SUPER", "SHIFT"])
    right.key = "RIGHT"
    right.combo = "SUPER + SHIFT + RIGHT"
    var left = binding(7, ["SUPER", "SHIFT"])
    left.key = "LEFT"
    left.combo = "SUPER + SHIFT + LEFT"
    source.bindings.push(right, left)
    source.byId[right.id] = right
    source.byId[left.id] = left

    // Newest first internally: RIGHT, LEFT.
    var history = [
      { id: right.id, sequence: 3, expiresAt: 5000 },
      { id: left.id, sequence: 2, expiresAt: 4500 }
    ]
    var rows = GuideModel.hintRows(source, [], history, "SUPER_SHIFT", "SUPER", true)
    compare(rows.length, 3)
    compare(rows[0].combo, "SUPER + SHIFT + LEFT")
    compare(rows[1].combo, "SUPER + SHIFT + RIGHT")
    compare(rows[2].combo, "SUPER + SHIFT")
    compare(rows[0].opacity, 0.45)
    compare(rows[1].opacity, 0.72)
    compare(rows[2].opacity, 1)

    var afterGuideEnd = GuideModel.hintRows(
      source, [], history, "SUPER_SHIFT", "SUPER", false)
    compare(afterGuideEnd.length, 2)
    compare(afterGuideEnd[0].combo, "SUPER + SHIFT + LEFT")
    compare(afterGuideEnd[1].combo, "SUPER + SHIFT + RIGHT")

    var activeRows = GuideModel.hintRows(
      source, [right.id], history, "SUPER_SHIFT", "SUPER", true)
    compare(activeRows.length, 3)
    compare(activeRows[0].combo, "SUPER + SHIFT + LEFT")
    compare(activeRows[1].combo, "SUPER + SHIFT + RIGHT")
    compare(activeRows[2].combo, "SUPER + SHIFT + RIGHT")
    compare(activeRows[2].active, true)
  }

  function test_hintRowsKeepVisualIdentityWhenChordBecomesHistory() {
    var source = catalog()
    var chord = source.bindings[0]
    var visualId = "hint-42"
    var activeRows = GuideModel.hintRows(
      source, [{ id: chord.id, visualId: visualId }], [], "SUPER", "SUPER", false)
    compare(activeRows.length, 1)
    compare(activeRows[0].visualId, visualId)
    compare(activeRows[0].phase, "current")

    var history = [{
      id: chord.id,
      visualId: visualId,
      sequence: 7,
      expiresAt: 3000
    }]
    var stackedRows = GuideModel.hintRows(
      source, [], history, "SUPER", "SUPER", true)
    compare(stackedRows.length, 2)
    compare(stackedRows[0].visualId, visualId)
    compare(stackedRows[0].phase, "history")
    compare(stackedRows[1].phase, "current")

    var releasedRows = GuideModel.hintRows(
      source, [], history, "SUPER", "SUPER", false)
    compare(releasedRows.length, 1)
    compare(releasedRows[0].visualId, visualId)
    compare(releasedRows[0].phase, "history")
  }

  function test_displaySettingsControlHistoryCountAndOpacity() {
    var source = catalog()
    var history = [
      { id: source.bindings[1].id, sequence: 2, expiresAt: 4000 },
      { id: source.bindings[0].id, sequence: 1, expiresAt: 3000 }
    ]

    var disabled = GuideModel.hintRows(
      source, [], history, "SUPER", "SUPER", false,
      { historyCount: 0, historyTransparency: "clear" })
    compare(disabled.length, 0)

    var oneChord = GuideModel.hintRows(
      source, [], history, "SUPER", "SUPER", false,
      { historyCount: 1, historyTransparency: "clear" })
    compare(oneChord.length, 1)
    compare(oneChord[0].binding.id, source.bindings[1].id)
    compare(oneChord[0].opacity, 0.86)
    compare(oneChord[0].scale, 0.8)

    var twoChords = GuideModel.hintRows(
      source, [], history, "SUPER", "SUPER", false,
      { historyCount: 2, historyTransparency: "faded" })
    compare(twoChords.length, 2)
    compare(twoChords[0].binding.id, source.bindings[0].id)
    compare(twoChords[0].opacity, 0.3)
    compare(twoChords[1].binding.id, source.bindings[1].id)
    compare(twoChords[1].opacity, 0.52)

    compare(GuideModel.pillSizeFactor("small"), 0.8)
    compare(GuideModel.pillSizeFactor("medium"), 1)
    compare(GuideModel.pillSizeFactor("large"), 1.2)
    compare(GuideModel.stackGapUnits("tight"), 0)
    compare(GuideModel.stackGapUnits("default"), 8)
    compare(GuideModel.stackGapUnits("loose"), 16)
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
