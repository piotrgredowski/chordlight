import QtQuick 2.15
import QtTest 1.3
import "../../GuideState.js" as GuideState

TestCase {
  name: "ChordlightGuideState"

  function id(letter) { return "sha256:" + String(letter).repeat(64) }

  function activeState(root) {
    var state = GuideState.initialState()
    state = GuideState.transition(state, { type: "sessionStarted", root: root || "SUPER" })
    return GuideState.transition(state, { type: "sessionActivated" })
  }

  function complete(state, bindingId, at) {
    state = GuideState.transition(state, { type: "hintDown", id: bindingId })
    return GuideState.transition(state, { type: "hintUp", id: bindingId, at: at })
  }

  function test_differentChordsKeepIndependentDeadlines() {
    var right = id("a")
    var left = id("b")
    var state = complete(activeState("SUPER"), right, 0)
    state = GuideState.transition(state, { type: "hintDown", id: left })
    compare(state.history.length, 1)
    compare(state.history[0].id, right)
    compare(state.history[0].expiresAt, 3000)
    state = GuideState.transition(state, { type: "hintUp", id: left, at: 1000 })
    compare(state.history.length, 2)
    compare(state.history[0].id, left)
    compare(state.history[0].expiresAt, 4000)
    compare(state.history[1].id, right)
    compare(state.history[1].expiresAt, 3000)
    state = GuideState.transition(state, { type: "expire", at: 2999 })
    compare(state.history.length, 2)
    state = GuideState.transition(state, { type: "expire", at: 3000 })
    compare(state.history.length, 1)
    compare(state.history[0].id, left)
    state = GuideState.transition(state, { type: "expire", at: 4000 })
    compare(state.history.length, 0)
  }

  function test_repeatedChordCreatesDistinctHistoryEntries() {
    var bindingId = id("c")
    var state = complete(activeState("SUPER"), bindingId, 100)
    state = complete(state, bindingId, 500)
    compare(state.history.length, 2)
    compare(state.history[0].id, bindingId)
    compare(state.history[1].id, bindingId)
    compare(state.history[0].sequence, 2)
    compare(state.history[1].sequence, 1)
    compare(state.history[0].expiresAt, 3500)
    compare(state.history[1].expiresAt, 3100)
    state = GuideState.transition(state, { type: "expire", at: 3100 })
    compare(state.history.length, 1)
    compare(state.history[0].sequence, 2)
  }

  function test_visualIdentityMovesFromPendingChordIntoHistory() {
    var bindingId = id("a")
    var state = activeState("SUPER")
    state = GuideState.transition(state, { type: "hintDown", id: bindingId })
    compare(state.pendingEntries.length, 1)
    compare(GuideState.pendingIds(state)[0], bindingId)
    var firstVisualId = state.pendingEntries[0].visualId
    verify(firstVisualId !== "")

    state = GuideState.transition(state, { type: "hintDown", id: bindingId })
    compare(state.pendingEntries.length, 1)
    compare(state.pendingEntries[0].visualId, firstVisualId)

    state = GuideState.transition(state, { type: "hintUp", id: bindingId, at: 100 })
    compare(state.pendingEntries.length, 0)
    compare(GuideState.pendingIds(state).length, 0)
    compare(state.history[0].visualId, firstVisualId)
    compare(state.history[0].sequence, 1)

    state = GuideState.transition(state, { type: "hintDown", id: bindingId })
    verify(state.pendingEntries[0].visualId !== firstVisualId)
    state = GuideState.transition(state, { type: "hintUp", id: bindingId, at: 200 })
    compare(state.history[0].sequence, 2)
    verify(state.history[0].visualId !== state.history[1].visualId)
  }

  function test_modifierChangeCancelsOnlyPendingChord() {
    var completedId = id("d")
    var pendingId = id("e")
    var state = complete(activeState("SUPER"), completedId, 1000)
    state = GuideState.transition(state, { type: "hintDown", id: pendingId })
    state = GuideState.transition(state, {
      type: "modifiersChanged",
      modifiers: "SUPER_SHIFT"
    })
    compare(state.pendingEntries.length, 0)
    compare(state.history.length, 1)
    compare(state.history[0].id, completedId)
    compare(state.history[0].expiresAt, 4000)
    state = GuideState.transition(state, { type: "expire", at: 3999 })
    compare(state.history.length, 1)
    state = GuideState.transition(state, { type: "expire", at: 4000 })
    compare(state.history.length, 0)
  }

  function test_sessionEndAndRestartPreserveHistory() {
    var bindingId = id("f")
    var state = complete(activeState("SUPER"), bindingId, 1000)
    state = GuideState.transition(state, { type: "sessionEnded" })
    compare(state.phase, GuideState.PHASE_IDLE)
    compare(state.history.length, 1)
    state = GuideState.transition(state, { type: "sessionStarted", root: "ALT" })
    compare(state.phase, GuideState.PHASE_CHECKING)
    compare(state.root, "ALT")
    compare(state.history.length, 1)
    state = GuideState.transition(state, { type: "expire", at: 3999 })
    compare(state.history.length, 1)
    state = GuideState.transition(state, { type: "expire", at: 4000 })
    compare(state.history.length, 0)
  }

  function test_historyLimitEvictsOldestOnlyOnCompletion() {
    var state = activeState("SUPER")
    var first = id("1")
    var second = id("2")
    var third = id("3")
    state = complete(state, first, 100)
    state = GuideState.transition(state, { type: "hintDown", id: second })
    compare(state.history.length, 1)
    state = GuideState.transition(state, { type: "hintUp", id: second, at: 200 })
    state = GuideState.transition(state, { type: "hintDown", id: third })
    compare(state.history.length, 2)
    compare(state.history[1].id, first)
    state = GuideState.transition(state, { type: "hintUp", id: third, at: 300 })
    compare(state.history.length, 2)
    compare(state.history[0].id, third)
    compare(state.history[1].id, second)
    compare(state.nextSequence, 4)
  }

  function test_unmatchedReleaseDoesNotCreateHistory() {
    var state = activeState("SUPER")
    state = GuideState.transition(state, { type: "hintUp", id: id("4"), at: 100 })
    compare(state.pendingEntries.length, 0)
    compare(state.history.length, 0)
  }

  function test_resetClearsSessionAndHistory() {
    var state = complete(activeState("SUPER"), id("5"), 100)
    state = GuideState.transition(state, { type: "reset" })
    compare(state.phase, GuideState.PHASE_IDLE)
    compare(state.root, "")
    compare(state.pendingEntries.length, 0)
    compare(state.history.length, 0)
    compare(state.nextSequence, 1)
    compare(state.nextVisualId, 1)
  }
}
