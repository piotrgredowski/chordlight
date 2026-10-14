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

function hintBinding(catalog, activeIds, recentEntries) {
  var byId = catalog && catalog.byId ? catalog.byId : null
  if (!byId) return null

  function eligibleBinding(id) {
    var binding = byId[String(id || "")]
    return binding && binding.trackable === true && binding.guideEligible === true
      ? binding : null
  }

  var active = activeHintBinding(catalog, activeIds)
  if (active) return active

  var recent = Array.isArray(recentEntries) ? recentEntries : []
  for (var recentIndex = 0; recentIndex < recent.length; recentIndex++) {
    var recentBinding = eligibleBinding(recent[recentIndex] && recent[recentIndex].id)
    if (recentBinding) return recentBinding
  }
  return null
}

function activeHintBinding(catalog, activeIds) {
  var byId = catalog && catalog.byId ? catalog.byId : null
  if (!byId) return null

  var ids = Array.isArray(activeIds) ? activeIds : []
  for (var i = ids.length - 1; i >= 0; i--) {
    var binding = byId[String(ids[i] || "")]
    if (binding && binding.trackable === true && binding.guideEligible === true) return binding
  }
  return null
}

function hintRows(catalog, activeIds, recentEntries, mask, guideRoot, showPrefix) {
  var byId = catalog && catalog.byId ? catalog.byId : null
  var rows = []
  if (!byId) return rows

  function eligibleBinding(id) {
    var binding = byId[String(id || "")]
    return binding && binding.trackable === true && binding.guideEligible === true
      ? binding : null
  }

  var activeBinding = activeHintBinding(catalog, activeIds)
  var prefixBinding = !activeBinding && showPrefix === true
    && hasMatchingPrefix(catalog, mask, guideRoot)

  var recent = Array.isArray(recentEntries) ? recentEntries : []
  var historyLimit = Math.max(0, 3 - (activeBinding || prefixBinding ? 1 : 0))
  var recentCount = Math.min(recent.length, historyLimit)
  for (var historyIndex = recentCount - 1; historyIndex >= 0; historyIndex--) {
    var entry = recent[historyIndex]
    var binding = eligibleBinding(entry && entry.id)
    if (!binding) continue
    rows.push({
      key: "history:" + String(entry.sequence) + ":" + binding.id,
      binding: binding,
      combo: displayCombo(binding),
      description: displayDescription(binding),
      active: false
    })
  }

  if (activeBinding) {
    rows.push({
      key: "active:" + activeBinding.id,
      binding: activeBinding,
      combo: displayCombo(activeBinding),
      description: displayDescription(activeBinding),
      active: true
    })
  } else if (prefixBinding) {
    rows.push({
      key: "prefix:" + String(mask || guideRoot || ""),
      binding: null,
      combo: String(mask || guideRoot || "").split("_").join(" + "),
      description: "",
      active: false
    })
  }

  var historyCountInRows = rows.length - (activeBinding || prefixBinding ? 1 : 0)
  var historyOpacityByAge = [0.72, 0.45, 0.45]
  var historyScaleByAge = [0.8, 0.6, 0.6]
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    var isCurrentRow = rows[rowIndex].active === true
      || String(rows[rowIndex].key || "").indexOf("prefix:") === 0
    if (isCurrentRow) {
      rows[rowIndex].opacity = 1
      rows[rowIndex].scale = 1
      continue
    }
    var historyAge = historyCountInRows - rowIndex - 1
    rows[rowIndex].opacity = historyOpacityByAge[
      Math.min(historyAge, historyOpacityByAge.length - 1)]
    rows[rowIndex].scale = historyScaleByAge[
      Math.min(historyAge, historyScaleByAge.length - 1)]
  }
  return rows
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
