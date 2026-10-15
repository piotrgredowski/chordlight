.pragma library

var PHASE_IDLE = "idle"
var PHASE_CHECKING = "checking"
var PHASE_ACTIVE = "active"
var HINT_HISTORY_MS = 3000
var MAX_HISTORY_ENTRIES = 2

function validId(value) {
  return typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value)
}

function validRoot(value) {
  return value === "SUPER" || value === "SHIFT" || value === "CTRL" || value === "ALT"
}

function initialState() {
  return {
    phase: PHASE_IDLE,
    root: "",
    modifiers: "",
    pendingEntries: [],
    history: [],
    nextSequence: 1,
    nextVisualId: 1
  }
}

function normalizedHistoryLimit(value) {
  var limit = Number(value)
  if (!isFinite(limit)) return MAX_HISTORY_ENTRIES
  return Math.max(0, Math.min(MAX_HISTORY_ENTRIES, Math.floor(limit)))
}

function copyState(source, historyLimit) {
  var state = source && typeof source === "object" ? source : {}
  var retainedHistoryLimit = normalizedHistoryLimit(historyLimit)
  var phase = state.phase === PHASE_CHECKING || state.phase === PHASE_ACTIVE
    ? state.phase : PHASE_IDLE
  var root = validRoot(state.root) ? state.root : ""
  var pendingEntries = []
  var sourcePending = Array.isArray(state.pendingEntries) ? state.pendingEntries : []
  var nextVisualId = Number(state.nextVisualId)
  if (!isFinite(nextVisualId) || nextVisualId < 1) nextVisualId = 1
  for (var pendingIndex = 0; pendingIndex < sourcePending.length; pendingIndex++) {
    var pendingEntry = sourcePending[pendingIndex]
    var pendingId = String(pendingEntry && pendingEntry.id || "")
    if (!validId(pendingId) || pendingIds(pendingEntries).indexOf(pendingId) !== -1) continue
    var visualId = String(pendingEntry.visualId || "")
    if (visualId === "") visualId = "hint-" + Math.floor(nextVisualId++)
    pendingEntries.push({ id: pendingId, visualId: visualId })
  }

  // Accept an older in-memory shape while keeping presentation identity
  // internal to this reducer.
  var legacyPending = Array.isArray(state.pendingIds) ? state.pendingIds : []
  for (var legacyIndex = 0; legacyIndex < legacyPending.length; legacyIndex++) {
    var legacyId = String(legacyPending[legacyIndex] || "")
    if (!validId(legacyId) || pendingIds(pendingEntries).indexOf(legacyId) !== -1) continue
    pendingEntries.push({ id: legacyId, visualId: "hint-" + Math.floor(nextVisualId++) })
  }

  var history = []
  var sourceHistory = Array.isArray(state.history) ? state.history : []
  for (var historyIndex = 0; historyIndex < sourceHistory.length; historyIndex++) {
    var entry = sourceHistory[historyIndex]
    if (!entry || typeof entry !== "object" || !validId(entry.id)) continue
    var sequence = Number(entry.sequence)
    var completedAt = Number(entry.completedAt)
    var expiresAt = Number(entry.expiresAt)
    if (!isFinite(sequence) || !isFinite(completedAt) || !isFinite(expiresAt)) continue
    history.push({
      id: entry.id,
      visualId: String(entry.visualId || "history-" + sequence + ":" + entry.id),
      sequence: sequence,
      completedAt: completedAt,
      expiresAt: expiresAt
    })
  }

  var nextSequence = Number(state.nextSequence)
  if (!isFinite(nextSequence) || nextSequence < 1) nextSequence = 1
  return {
    phase: phase,
    root: phase === PHASE_IDLE ? "" : root,
    modifiers: phase === PHASE_IDLE ? "" : String(state.modifiers || ""),
    pendingEntries: phase === PHASE_IDLE ? [] : pendingEntries,
    history: history.slice(0, retainedHistoryLimit),
    nextSequence: Math.floor(nextSequence),
    nextVisualId: Math.floor(nextVisualId)
  }
}

function pendingIds(entriesOrState) {
  var entries = entriesOrState && Array.isArray(entriesOrState.pendingEntries)
    ? entriesOrState.pendingEntries
    : Array.isArray(entriesOrState) ? entriesOrState : []
  var result = []
  for (var i = 0; i < entries.length; i++) {
    var id = typeof entries[i] === "string" ? entries[i] : String(entries[i] && entries[i].id || "")
    if (validId(id) && result.indexOf(id) === -1) result.push(id)
  }
  return result
}

function canTrack(state) {
  return (state.phase === PHASE_CHECKING || state.phase === PHASE_ACTIVE)
    && state.root !== ""
}

function unexpiredHistory(entries, now) {
  var timestamp = Number(now)
  if (!isFinite(timestamp)) return entries.slice()
  var result = []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].expiresAt > timestamp) result.push(entries[i])
  }
  return result
}

function transition(source, event, settings) {
  var options = settings && typeof settings === "object" ? settings : {}
  var historyLimit = normalizedHistoryLimit(options.historyCount)
  var historyDurationMs = Number(options.historyDurationMs)
  if (!isFinite(historyDurationMs) || historyDurationMs <= 0) historyDurationMs = HINT_HISTORY_MS
  var state = copyState(source, historyLimit)
  if (!event || typeof event.type !== "string") return state

  switch (event.type) {
  case "sessionStarted":
    if (!validRoot(event.root)) return state
    state.phase = PHASE_CHECKING
    state.root = event.root
    state.modifiers = event.root
    state.pendingEntries = []
    return state

  case "sessionOpened":
    state.phase = PHASE_ACTIVE
    state.root = ""
    state.modifiers = ""
    state.pendingEntries = []
    return state

  case "sessionActivated":
    if (state.phase === PHASE_CHECKING) state.phase = PHASE_ACTIVE
    return state

  case "modifiersChanged":
    if (state.phase === PHASE_IDLE) return state
    var nextModifiers = String(event.modifiers || "")
    if (state.modifiers !== nextModifiers) {
      state.modifiers = nextModifiers
      state.pendingEntries = []
    }
    return state

  case "hintDown":
    if (!canTrack(state) || !validId(event.id)) return state
    if (pendingIds(state.pendingEntries).indexOf(event.id) === -1) {
      state.pendingEntries.push({
        id: event.id,
        visualId: "hint-" + state.nextVisualId
      })
      state.nextVisualId += 1
    }
    return state

  case "hintUp":
    if (!canTrack(state) || !validId(event.id)) return state
    var completedAt = Number(event.at)
    if (!isFinite(completedAt)) return state
    var pendingIndex = pendingIds(state.pendingEntries).indexOf(event.id)
    if (pendingIndex === -1) return state

    var completedEntry = state.pendingEntries.splice(pendingIndex, 1)[0]
    state.history = unexpiredHistory(state.history, completedAt)
    state.history.unshift({
      id: event.id,
      visualId: completedEntry.visualId,
      sequence: state.nextSequence,
      completedAt: completedAt,
      expiresAt: completedAt + historyDurationMs
    })
    state.history = state.history.slice(0, historyLimit)
    state.nextSequence += 1
    return state

  case "sessionEnded":
    state.phase = PHASE_IDLE
    state.root = ""
    state.modifiers = ""
    state.pendingEntries = []
    return state

  case "expire":
    var now = Number(event.at)
    if (!isFinite(now)) return state
    state.history = unexpiredHistory(state.history, now)
    return state

  case "reset":
    return initialState()
  }

  return state
}

function nextExpiryAt(state) {
  var entries = state && Array.isArray(state.history) ? state.history : []
  var nextExpiry = Number.POSITIVE_INFINITY
  for (var i = 0; i < entries.length; i++) {
    var expiresAt = Number(entries[i] && entries[i].expiresAt)
    if (isFinite(expiresAt) && expiresAt < nextExpiry) nextExpiry = expiresAt
  }
  return isFinite(nextExpiry) ? nextExpiry : null
}
