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

function pillSizeFactor(size) {
  if (size === "small") return 0.8
  if (size === "large") return 1.2
  return 1
}

function stackGapUnits(gap) {
  if (gap === "tight") return 8
  if (gap === "loose") return 24
  return 16
}

function stackRowOffsets(scales, baseHeight, gap, anchorAtTop) {
  var rows = Array.isArray(scales) ? scales : []
  var height = Math.max(0, Number(baseHeight) || 0)
  var spacing = Math.max(0, Number(gap) || 0)
  var offsets = new Array(rows.length)

  if (anchorAtTop) {
    var top = 0
    for (var topIndex = 0; topIndex < rows.length; topIndex++) {
      var topScale = Number(rows[topIndex])
      if (!isFinite(topScale) || topScale < 0) topScale = 1
      offsets[topIndex] = top - (1 - topScale) * height / 2
      top += topScale * height + spacing
    }
    return offsets
  }

  var bottom = rows.length * height + Math.max(0, rows.length - 1) * spacing
  for (var bottomIndex = rows.length - 1; bottomIndex >= 0; bottomIndex--) {
    var bottomScale = Number(rows[bottomIndex])
    if (!isFinite(bottomScale) || bottomScale < 0) bottomScale = 1
    var rowTop = bottom - bottomScale * height
    offsets[bottomIndex] = rowTop - (1 - bottomScale) * height / 2
    bottom = rowTop - spacing
  }
  return offsets
}

function historyOpacity(transparency, age) {
  var profiles = {
    faded: [0.30, 0.52],
    balanced: [0.45, 0.72],
    clear: [0.62, 0.86]
  }
  var profile = profiles[String(transparency || "balanced")] || profiles.balanced
  var ageIndex = Math.max(0, Number(age) || 0)
  return profile[Math.max(0, profile.length - 1 - ageIndex)]
}

function historyScale(age) {
  return Number(age) <= 0 ? 0.8 : 0.6
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

function hintRows(catalog, activeEntries, recentEntries, mask, guideRoot, showPrefix, settings) {
  var byId = catalog && catalog.byId ? catalog.byId : null
  var rows = []
  if (!byId) return rows
  var options = settings && typeof settings === "object" ? settings : {}
  var requestedHistoryCount = Number(options.historyCount)
  if (!isFinite(requestedHistoryCount)) requestedHistoryCount = 2
  var historyLimit = Math.max(0, Math.min(2, Math.floor(requestedHistoryCount)))
  var transparency = String(options.historyTransparency || "balanced")

  function eligibleBinding(id) {
    var binding = byId[String(id || "")]
    return binding && binding.trackable === true && binding.guideEligible === true
      ? binding : null
  }

  var activeSource = Array.isArray(activeEntries) ? activeEntries : []
  var activeIdsOnly = []
  for (var activeIndex = 0; activeIndex < activeSource.length; activeIndex++) {
    var activeItem = activeSource[activeIndex]
    activeIdsOnly.push(typeof activeItem === "string"
      ? activeItem : String(activeItem && activeItem.id || ""))
  }
  var activeBinding = activeHintBinding(catalog, activeIdsOnly)
  var activeVisualId = ""
  if (activeBinding) {
    for (var visualIndex = activeSource.length - 1; visualIndex >= 0; visualIndex--) {
      var visualItem = activeSource[visualIndex]
      var visualItemId = typeof visualItem === "string"
        ? visualItem : String(visualItem && visualItem.id || "")
      if (visualItemId !== activeBinding.id) continue
      activeVisualId = String(visualItem && visualItem.visualId || "")
      break
    }
  }
  var prefixBinding = !activeBinding && showPrefix === true
    && hasMatchingPrefix(catalog, mask, guideRoot)

  var recent = Array.isArray(recentEntries) ? recentEntries : []
  var recentCount = Math.min(recent.length, historyLimit)
  for (var historyIndex = recentCount - 1; historyIndex >= 0; historyIndex--) {
    var entry = recent[historyIndex]
    var binding = eligibleBinding(entry && entry.id)
    if (!binding) continue
    var historyVisualId = String(entry && entry.visualId
      || "history:" + String(entry && entry.sequence) + ":" + binding.id)
    rows.push({
      key: historyVisualId,
      visualId: historyVisualId,
      phase: "history",
      binding: binding,
      combo: displayCombo(binding),
      description: displayDescription(binding),
      active: false
    })
  }

  if (activeBinding) {
    if (activeVisualId === "") activeVisualId = "active:" + activeBinding.id
    rows.push({
      key: activeVisualId,
      visualId: activeVisualId,
      phase: "current",
      binding: activeBinding,
      combo: displayCombo(activeBinding),
      description: displayDescription(activeBinding),
      active: true
    })
  } else if (prefixBinding) {
    var prefixVisualId = "prefix:" + String(mask || guideRoot || "")
    rows.push({
      key: prefixVisualId,
      visualId: prefixVisualId,
      phase: "current",
      binding: null,
      combo: String(mask || guideRoot || "").split("_").join(" + "),
      description: "",
      active: false
    })
  }

  var historyCountInRows = rows.length - (activeBinding || prefixBinding ? 1 : 0)
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    var isCurrentRow = rows[rowIndex].active === true
      || String(rows[rowIndex].key || "").indexOf("prefix:") === 0
    if (isCurrentRow) {
      rows[rowIndex].opacity = 1
      rows[rowIndex].scale = 1
      continue
    }
    var historyAge = historyCountInRows - rowIndex - 1
    rows[rowIndex].opacity = historyOpacity(transparency, historyAge)
    rows[rowIndex].scale = historyScale(historyAge)
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
