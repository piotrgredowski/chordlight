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
    pendingIds: [],
    history: [],
    nextSequence: 1
  }
}

function copyState(source) {
  var state = source && typeof source === "object" ? source : {}
  var phase = state.phase === PHASE_CHECKING || state.phase === PHASE_ACTIVE
    ? state.phase : PHASE_IDLE
  var root = validRoot(state.root) ? state.root : ""
  var pendingIds = []
  var sourcePending = Array.isArray(state.pendingIds) ? state.pendingIds : []
  for (var pendingIndex = 0; pendingIndex < sourcePending.length; pendingIndex++) {
    var pendingId = sourcePending[pendingIndex]
    if (validId(pendingId) && pendingIds.indexOf(pendingId) === -1)
      pendingIds.push(pendingId)
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
    pendingIds: phase === PHASE_IDLE ? [] : pendingIds,
    history: history.slice(0, MAX_HISTORY_ENTRIES),
    nextSequence: Math.floor(nextSequence)
  }
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

function transition(source, event) {
  var state = copyState(source)
  if (!event || typeof event.type !== "string") return state

  switch (event.type) {
  case "sessionStarted":
    if (!validRoot(event.root)) return state
    state.phase = PHASE_CHECKING
    state.root = event.root
    state.modifiers = event.root
    state.pendingIds = []
    return state

  case "sessionOpened":
    state.phase = PHASE_ACTIVE
    state.root = ""
    state.modifiers = ""
    state.pendingIds = []
    return state

  case "sessionActivated":
    if (state.phase === PHASE_CHECKING) state.phase = PHASE_ACTIVE
    return state

  case "modifiersChanged":
    if (state.phase === PHASE_IDLE) return state
    var nextModifiers = String(event.modifiers || "")
    if (state.modifiers !== nextModifiers) {
      state.modifiers = nextModifiers
      state.pendingIds = []
    }
    return state

  case "hintDown":
    if (!canTrack(state) || !validId(event.id)) return state
    if (state.pendingIds.indexOf(event.id) === -1)
      state.pendingIds.push(event.id)
    return state

  case "hintUp":
    if (!canTrack(state) || !validId(event.id)) return state
    var completedAt = Number(event.at)
    if (!isFinite(completedAt)) return state
    var pendingIndex = state.pendingIds.indexOf(event.id)
    if (pendingIndex === -1) return state

    state.pendingIds.splice(pendingIndex, 1)
    state.history = unexpiredHistory(state.history, completedAt)
    state.history.unshift({
      id: event.id,
      sequence: state.nextSequence,
      completedAt: completedAt,
      expiresAt: completedAt + HINT_HISTORY_MS
    })
    state.history = state.history.slice(0, MAX_HISTORY_ENTRIES)
    state.nextSequence += 1
    return state

  case "sessionEnded":
    state.phase = PHASE_IDLE
    state.root = ""
    state.modifiers = ""
    state.pendingIds = []
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
