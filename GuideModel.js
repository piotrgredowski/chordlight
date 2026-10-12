.pragma library

function displayCombo(binding) {
  var combo = String(binding && binding.combo || "")
  var key = String(binding && binding.key || "")
  var code = /^code:([0-9]+)$/i.exec(key)
  if (code) {
    var replacement = "KEY " + code[1]
    if (combo === "" || /^code:[0-9]+$/i.test(combo)) return replacement
    return combo.replace(/code:[0-9]+$/i, replacement)
  }
  return combo !== "" ? combo : key
}

function comboParts(combo) {
  var source = String(combo || "").split(/\s+\+\s+/)
  var result = []
  for (var i = 0; i < source.length; i++) {
    var key = source[i].trim()
    if (key !== "") result.push(key)
  }
  return result
}

function hintBinding(catalog, activeIds, lingeringId) {
  var byId = catalog && catalog.byId ? catalog.byId : null
  if (!byId) return null

  function eligibleBinding(id) {
    var binding = byId[String(id || "")]
    return binding && binding.trackable === true && binding.guideEligible === true
      ? binding : null
  }

  var ids = Array.isArray(activeIds) ? activeIds : []
  for (var i = ids.length - 1; i >= 0; i--) {
    var active = eligibleBinding(ids[i])
    if (active) return active
  }
  return eligibleBinding(lingeringId)
}

function displayDescription(binding) {
  return binding && typeof binding.description === "string" ? binding.description.trim() : ""
}

function hasMatchingPrefix(catalog, mask, root) {
  var held = String(mask || root || "").split("_")
  var rootName = String(root || "")
  if (held.length === 0 || held[0] === "" || rootName === "" || held.indexOf(rootName) === -1) return false

  var source = catalog && Array.isArray(catalog.bindings) ? catalog.bindings : []
  for (var i = 0; i < source.length; i++) {
    var binding = source[i]
    var modifiers = binding && binding.modifiers
    if (!binding || binding.trackable !== true || binding.guideEligible !== true
        || !Array.isArray(binding.xkbCodes) || binding.xkbCodes.length === 0
        || !Array.isArray(modifiers)) continue

    var matches = true
    for (var heldIndex = 0; heldIndex < held.length; heldIndex++) {
      if (modifiers.indexOf(held[heldIndex]) === -1) {
        matches = false
        break
      }
    }
    if (matches) return true
  }
  return false
}

function eligible(state) {
  if (!state || state.integrationState !== "enabled" || state.catalogState !== "ready") return false
  if (state.lockStateKnown !== true || state.credentialPromptStateKnown !== true) return false
  if (state.desktopLocked === true || state.credentialPromptActive === true) return false
  return state.showInFullscreen === true || state.activeWindowFullscreen !== true
}

function delayMode(guideVisible, delay) {
  if (guideVisible !== true) return "hidden"
  var value = Number(delay)
  if (value === 0) return "immediate"
  if (value === 80 || value === 150 || value === 250) return "delayed"
  return "disabled"
}

function focusedVisible(shouldShow, screenName, focusedName) {
  return shouldShow === true && String(screenName || "") !== ""
    && String(screenName || "") === String(focusedName || "")
}
