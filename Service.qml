import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "ServiceModel.js" as Model

Item {
  id: root

  readonly property string moduleName: "io.github.zaremb.chordlight"
  property var shell: null
  property var manifest: null

  property string integrationState: "disabled"
  property bool integrationStateKnown: false
  property var integrationDetails: ({})
  property var catalog: null
  property bool guideVisible: false
  property string activeModifiers: ""
  property string activeGuideRoot: ""
  property var activeHintIds: []
  property var recentHintEntries: []
  property int hintSequence: 0
  property bool prefixRowVisible: false
  property int guideDelayMs: 0
  property bool showInFullscreen: false
  property bool guideSuperEnabled: true
  property bool guideShiftEnabled: true
  property bool guideCtrlEnabled: true
  property bool guideAltEnabled: true
  // Suppression starts active until both independent sources have answered.
  // Unknown state must never briefly expose the guide over a protected surface.
  property bool desktopLocked: true
  property bool lockStateKnown: false
  property bool credentialPromptActive: true
  property bool credentialPromptStateKnown: false
  property bool activeWindowFullscreen: false
  property bool guideAwaitingLockCheck: false
  property bool lockStatusRefreshPending: false
  property bool lockStatusTimedOut: false
  property bool layerStatusTimedOut: false
  property bool layerRefreshPending: false
  property int layerEventRevision: 0
  property int layerRequestRevision: 0

  property string catalogState: "loading"
  property bool catalogPublicationPending: false
  property var pendingCatalogGeneration: null
  property string deferredBridgeReloadSourceHash: ""
  property string activeBridgeReloadSourceHash: ""
  property string pendingBridgeReloadSourceHash: ""
  property string lastBridgeReloadSourceHash: ""
  property string manualSnippet: ""
  property string lastProtocolError: ""
  property int bridgeEventCount: 0
  property var sessionDiagnostics: ({
    catalogLoadFailures: 0,
    integrationFailures: 0,
    fullscreenQueryCount: 0,
    fullscreenQueryFailures: 0,
    lockQueryFailures: 0,
    layerQueryFailures: 0
  })

  // These diagnostics remain intentionally in memory only. They are useful to
  // the feasibility IPC target and do not become a statistics implementation.
  property double pendingGuideReceivedMs: 0
  property int observedEventCount: 0
  property var latencySamples: []

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy/chordlight"

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.substring(7))
    return value
  }

  readonly property string generatorPath: localPath(Qt.resolvedUrl("scripts/generate-catalog"))
  readonly property string controllerPath: localPath(Qt.resolvedUrl("scripts/bridge-control"))
  readonly property bool catalogGenerationRunning: catalogGenerationProcess.running
  readonly property bool integrationInspectRunning: integrationInspectProcess.running
  readonly property bool integrationMutationRunning: integrationMutationProcess.running

  function protocolPayload(event) {
    if (!event || String(event.name || "") !== "custom") return ""
    var payload = String(event.data || "")
    return payload.indexOf("chordlight:") === 0 ? payload : ""
  }

  function setDiagnostic(name, delta) {
    var next = {}
    for (var key in sessionDiagnostics) next[key] = sessionDiagnostics[key]
    next[name] = Number(next[name] || 0) + Number(delta || 1)
    sessionDiagnostics = next
  }

  function handleProtocolEvent(payload) {
    bridgeEventCount += 1
    observedEventCount += 1
    var parsed = Model.parseProtocol(payload, root.catalog)
    if (!parsed.ok) {
      lastProtocolError = parsed.error
      return false
    }

    lastProtocolError = ""
    if (parsed.type === "guide") {
      if (parsed.phase === "down") {
        if (!root.guideRootEnabled(parsed.root)) {
          root.clearGuide()
          return true
        }
        root.endGuide()
        pendingGuideReceivedMs = Date.now()
        activeGuideRoot = parsed.root
        activeModifiers = parsed.root
        activeHintIds = []
        guideVisible = false
        guideAwaitingLockCheck = true
        root.requestLockStatus(true)
      } else {
        root.endGuide()
      }
      return true
    }
    if (parsed.type === "mods") {
      if (guideVisible || guideAwaitingLockCheck) {
        if (activeModifiers !== parsed.modifiers) {
          activeHintIds = []
        }
        activeModifiers = parsed.modifiers
      }
      return true
    }
    if (parsed.type === "match") {
      if (!parsed.known) {
        lastProtocolError = "unknown-binding-id"
        return false
      }
      return true
    }
    if (parsed.type === "hint") {
      if (!parsed.known) {
        lastProtocolError = "unknown-binding-id"
        return false
      }
      // A fast chord can arrive while lock/polkit state is still being
      // checked. Keep its opaque ID pending; clearGuide() discards it if the
      // fail-closed eligibility check rejects the guide.
      if (!Model.mayTrackHint(guideVisible, guideAwaitingLockCheck, activeGuideRoot)) return true
      var isCompletion = parsed.phase === "up" && activeHintIds.indexOf(parsed.id) !== -1
      var nextSequence = hintSequence + (isCompletion ? 1 : 0)
      var hintState = Model.updatedHintState(
        activeHintIds, recentHintEntries, parsed.id, parsed.phase, Date.now(), nextSequence,
        prefixRowVisible)
      activeHintIds = hintState.activeIds
      recentHintEntries = hintState.history
      if (hintState.added) hintSequence = nextSequence
      root.scheduleHintHistoryExpiry()
      return true
    }
    return false
  }

  function clearHintHistory() {
    hintHistoryTimer.stop()
    recentHintEntries = []
    hintSequence = 0
    prefixRowVisible = false
  }

  function setPrefixRowVisible(visible) {
    var next = visible === true
    if (prefixRowVisible === next) return false
    prefixRowVisible = next
    recentHintEntries = Model.prunedHintHistory(
      recentHintEntries, Date.now(), activeHintIds, prefixRowVisible)
    if (recentHintEntries.length === 0) hintSequence = 0
    root.scheduleHintHistoryExpiry()
    return true
  }

  function scheduleHintHistoryExpiry() {
    hintHistoryTimer.stop()
    if (!Array.isArray(recentHintEntries) || recentHintEntries.length === 0) return

    var now = Date.now()
    var nextExpiry = Number.POSITIVE_INFINITY
    for (var i = 0; i < recentHintEntries.length; i++) {
      var expiresAt = Number(recentHintEntries[i].expiresAt)
      if (isFinite(expiresAt) && expiresAt < nextExpiry) nextExpiry = expiresAt
    }
    if (!isFinite(nextExpiry)) {
      root.clearHintHistory()
      return
    }
    hintHistoryTimer.interval = Math.max(1, Math.ceil(nextExpiry - now))
    hintHistoryTimer.start()
  }

  function expireHintHistory() {
    recentHintEntries = Model.prunedHintHistory(
      recentHintEntries, Date.now(), activeHintIds, prefixRowVisible)
    if (recentHintEntries.length === 0) hintSequence = 0
    root.scheduleHintHistoryExpiry()
  }

  Timer {
    id: hintHistoryTimer
    interval: Model.HINT_HISTORY_MS
    repeat: false
    onTriggered: root.expireHintHistory()
  }

  function recordGuideVisible() {
    if (pendingGuideReceivedMs <= 0) return
    var next = latencySamples.slice()
    next.push(Math.max(0, Date.now() - pendingGuideReceivedMs))
    latencySamples = next
    pendingGuideReceivedMs = 0
  }

  function resetDiagnostics() {
    clearGuide()
    observedEventCount = 0
    bridgeEventCount = 0
    latencySamples = []
    lastProtocolError = ""
  }

  function diagnosticsJson() {
    return JSON.stringify({
      eventCount: observedEventCount,
      bridgeEventCount: bridgeEventCount,
      sampleCount: latencySamples.length,
      samplesMs: latencySamples,
      guideVisible: guideVisible,
      catalogState: catalogState,
      integrationState: integrationState,
      lastProtocolError: lastProtocolError,
      sessionDiagnostics: sessionDiagnostics
    })
  }

  function loadCatalog(raw) {
    var result = Model.normalizeCatalog(raw)
    root.clearHintHistory()
    if (!result.ok) {
      catalog = null
      catalogState = "error"
      activeHintIds = []
      setDiagnostic("catalogLoadFailures", 1)
      return false
    }
    catalog = result.catalog
    catalogState = "ready"
    activeHintIds = []
    return true
  }

  function openGuide() { guideVisible = true }
  function closeGuide() { clearGuide() }

  function settingsEntry() {
    return Model.settingsFor(shell ? shell.barConfig : null, root.moduleName)
  }

  function syncSettings() {
    var entry = settingsEntry()
    guideDelayMs = Model.normalizeDelay(entry.guideDelayMs)
    showInFullscreen = Model.normalizeFullscreen(entry.showInFullscreen)
    guideSuperEnabled = Model.normalizeGuideRoot(entry.guideSuperEnabled)
    guideShiftEnabled = Model.normalizeGuideRoot(entry.guideShiftEnabled)
    guideCtrlEnabled = Model.normalizeGuideRoot(entry.guideCtrlEnabled)
    guideAltEnabled = Model.normalizeGuideRoot(entry.guideAltEnabled)
    if (!guideRootEnabled(activeGuideRoot)) {
      clearGuide()
    }
  }

  function persistSettings(changes) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var next = Model.updatedSettingsEntry(settingsEntry(), changes, root.moduleName)
    return shell.updateEntryInline(root.moduleName, next) !== false
  }

  function setGuideDelayMs(value) {
    var next = Model.normalizeDelay(value)
    if (next === guideDelayMs) return false
    guideDelayMs = next
    return persistSettings({ guideDelayMs: next })
  }

  function setShowInFullscreen(value) {
    var next = Model.normalizeFullscreen(value)
    if (next === showInFullscreen) return false
    showInFullscreen = next
    return persistSettings({ showInFullscreen: next })
  }

  function guideRootEnabled(rootName) {
    if (rootName === "SUPER") return guideSuperEnabled
    if (rootName === "SHIFT") return guideShiftEnabled
    if (rootName === "CTRL") return guideCtrlEnabled
    if (rootName === "ALT") return guideAltEnabled
    return false
  }

  function setGuideRootEnabled(rootName, value) {
    var next = Model.normalizeGuideRoot(value)
    var setting = ""
    if (rootName === "SUPER") setting = "guideSuperEnabled"
    else if (rootName === "SHIFT") setting = "guideShiftEnabled"
    else if (rootName === "CTRL") setting = "guideCtrlEnabled"
    else if (rootName === "ALT") setting = "guideAltEnabled"
    else return false

    if (guideRootEnabled(rootName) === next) return false
    if (rootName === "SUPER") guideSuperEnabled = next
    else if (rootName === "SHIFT") guideShiftEnabled = next
    else if (rootName === "CTRL") guideCtrlEnabled = next
    else guideAltEnabled = next
    if (!next && activeGuideRoot === rootName) {
      clearGuide()
    }
    var changes = {}
    changes[setting] = next
    return persistSettings(changes)
  }

  function endGuide() {
    guideVisible = false
    guideAwaitingLockCheck = false
    activeModifiers = ""
    activeGuideRoot = ""
    activeHintIds = []
    prefixRowVisible = false
    pendingGuideReceivedMs = 0
    root.expireHintHistory()
  }

  function clearGuide() {
    root.clearHintHistory()
    root.endGuide()
  }

  function suppressGuide() {
    if (guideVisible || guideAwaitingLockCheck) clearGuide()
    else root.clearHintHistory()
  }

  function evaluatePendingGuide() {
    if (!guideAwaitingLockCheck) return false
    if (!lockStateKnown || !credentialPromptStateKnown) return false
    if (desktopLocked || credentialPromptActive) {
      clearGuide()
      return false
    }
    guideAwaitingLockCheck = false
    guideVisible = true
    return true
  }

  function setLockStateUnknown() {
    lockStateKnown = false
    desktopLocked = true
    suppressGuide()
  }

  function recordLockStatus(raw, exitCode) {
    var parsed = Model.parseLockStatus(raw, exitCode)
    if (!parsed.ok) {
      setDiagnostic("lockQueryFailures", 1)
      setLockStateUnknown()
      return false
    }
    lockStateKnown = true
    desktopLocked = parsed.locked
    if (desktopLocked) suppressGuide()
    else evaluatePendingGuide()
    return true
  }

  function requestLockStatus(forGuide) {
    if (lockStatusProcess.running) {
      if (forGuide === true) lockStatusRefreshPending = true
      return false
    }
    lockStatusTimeoutTimer.restart()
    lockStatusProcess.running = true
    return true
  }

  function requestLayerStatus() {
    if (layerStatusProcess.running) {
      layerRefreshPending = true
      return false
    }
    layerStatusDebounceTimer.restart()
    return true
  }

  function handlePolkitLayerEvent(name, data) {
    if (!Model.isPolkitLayerEvent(name, data)) return false
    layerEventRevision += 1
    if (name === "openlayer") {
      credentialPromptStateKnown = true
      credentialPromptActive = true
    } else {
      // Keep the guide hidden until a fresh inventory confirms that every
      // Omarchy Polkit surface has closed, including on multi-monitor setups.
      credentialPromptStateKnown = false
      credentialPromptActive = true
    }
    suppressGuide()
    requestLayerStatus()
    return true
  }

  function recordLayerStatus(raw, exitCode) {
    if (layerRequestRevision !== layerEventRevision) {
      requestLayerStatus()
      return false
    }
    var parsed = Model.parseLayerStatus(raw, exitCode)
    if (!parsed.ok) {
      credentialPromptStateKnown = false
      credentialPromptActive = true
      setDiagnostic("layerQueryFailures", 1)
      suppressGuide()
      return false
    }
    credentialPromptStateKnown = true
    credentialPromptActive = parsed.active
    if (credentialPromptActive) suppressGuide()
    else evaluatePendingGuide()
    return true
  }

  function applyIntegrationResult(raw, exitCode) {
    if (exitCode !== 0) {
      integrationState = "error"
      integrationStateKnown = false
      setDiagnostic("integrationFailures", 1)
      return false
    }
    var parsed
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {
      integrationState = "error"
      integrationStateKnown = false
      setDiagnostic("integrationFailures", 1)
      return false
    }
    integrationDetails = parsed
    if (parsed.managedBlockState === "present") {
      integrationState = "enabled"
      integrationStateKnown = true
      if (deferredBridgeReloadSourceHash !== "") {
        var deferredHash = deferredBridgeReloadSourceHash
        deferredBridgeReloadSourceHash = ""
        requestCatalogBridgeReload(deferredHash)
      }
    }
    else if (parsed.managedBlockState === "absent") {
      integrationState = (integrationState === "enabled" || integrationState === "disconnected")
        ? "disconnected" : "disabled"
      integrationStateKnown = true
      deferredBridgeReloadSourceHash = ""
      pendingBridgeReloadSourceHash = ""
      clearGuide()
    } else {
      integrationState = "error"
      integrationStateKnown = false
    }
    return integrationState !== "error"
  }

  function applyManualSnippet(raw, exitCode) {
    if (exitCode !== 0) return false
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && parsed.ok === true && typeof parsed.snippet === "string") {
        manualSnippet = parsed.snippet
        return true
      }
    } catch (e) {}
    return false
  }

  function inspectIntegration() {
    if (integrationInspectProcess.running || controllerPath === "") return false
    integrationInspectProcess.command = [controllerPath, "inspect"]
    integrationInspectProcess.running = true
    return true
  }

  function mutateIntegration(action, expectedHash) {
    var hash = String(expectedHash || "")
    if (!hash || integrationMutationProcess.running || controllerPath === "") return false
    integrationState = "enabling"
    integrationStateKnown = false
    integrationMutationAction = action
    integrationMutationProcess.command = [controllerPath, action, "--expected-hash", hash]
    integrationMutationProcess.running = true
    return true
  }

  function enableIntegration(expectedHash) { return mutateIntegration("enable", expectedHash) }
  function disableIntegration(expectedHash) { return mutateIntegration("disable", expectedHash) }

  function recordFullscreenResult(raw, exitCode) {
    var next = {}
    for (var key in sessionDiagnostics) next[key] = sessionDiagnostics[key]
    next.fullscreenQueryCount = Number(next.fullscreenQueryCount || 0) + 1
    sessionDiagnostics = next
    if (exitCode !== 0) {
      setDiagnostic("fullscreenQueryFailures", 1)
      return false
    }
    var parsed = Model.parseActiveWindow(raw)
    if (!parsed.ok) {
      setDiagnostic("fullscreenQueryFailures", 1)
      return false
    }
    activeWindowFullscreen = parsed.fullscreen
    return true
  }

  property bool fullscreenQueryPending: false

  function requestFullscreenRefresh() {
    fullscreenQueryPending = true
    fullscreenQueryTimer.restart()
  }

  function handleRawEvent(event) {
    if (!event) return
    var name = String(event.name || "")
    var data = String(event.data || "")
    if (handlePolkitLayerEvent(name, data)) return
    if (name === "custom") {
      var payload = protocolPayload(event)
      if (payload !== "") handleProtocolEvent(payload)
      return
    }
    if (Model.isCatalogChangeEvent(name)) catalogChangeTimer.restart()
    if (Model.isFullscreenEvent(name)) requestFullscreenRefresh()
  }

  Timer {
    id: catalogChangeTimer
    interval: 350
    repeat: false
    onTriggered: root.regenerateCatalog()
  }

  property bool catalogRegenerationPending: false
  property string generatorOutput: ""

  function scheduleBridgeReloadForChangedCatalog(sourceHash) {
    var hash = String(sourceHash || "")
    if (hash === "") return false
    if (integrationState === "enabled") return requestCatalogBridgeReload(hash)
    if (!integrationStateKnown || integrationState === "enabling") {
      deferredBridgeReloadSourceHash = hash
      return true
    }
    deferredBridgeReloadSourceHash = ""
    return false
  }

  function requestCatalogBridgeReload(sourceHash) {
    var generation = { ok: true, sourceHash: String(sourceHash || ""), changed: true }
    if (integrationState !== "enabled") return false
    if (catalogBridgeReloadProcess.running) {
      if (generation.sourceHash === activeBridgeReloadSourceHash) {
        pendingBridgeReloadSourceHash = ""
        return false
      }
      pendingBridgeReloadSourceHash = generation.sourceHash
      return true
    }
    if (!Model.shouldReloadCatalogBridge(
          generation,
          integrationState,
          lastBridgeReloadSourceHash,
          activeBridgeReloadSourceHash,
          pendingBridgeReloadSourceHash)) return false
    activeBridgeReloadSourceHash = generation.sourceHash
    catalogBridgeReloadProcess.command = ["hyprctl", "reload"]
    catalogBridgeReloadProcess.running = true
    return true
  }

  function completeCatalogPublication(loaded) {
    var generation = pendingCatalogGeneration
    pendingCatalogGeneration = null
    catalogPublicationPending = false
    if (loaded && generation) {
      if (integrationState === "enabled" && catalogBridgeReloadProcess.running) {
        pendingBridgeReloadSourceHash = Model.pendingBridgeReloadAfterCatalog(
              generation.sourceHash,
              activeBridgeReloadSourceHash)
      } else if (generation.changed) {
        scheduleBridgeReloadForChangedCatalog(generation.sourceHash)
      }
    }
    if (catalogRegenerationPending) {
      catalogRegenerationPending = false
      catalogChangeTimer.restart()
    }
  }

  function regenerateCatalog() {
    if (catalogGenerationProcess.running || catalogPublicationPending) {
      catalogRegenerationPending = true
      return false
    }
    if (generatorPath === "") return false
    catalogRegenerationPending = false
    catalogGenerationProcess.command = ["python3", generatorPath, "--output-dir", stateDir]
    catalogGenerationProcess.running = true
    return true
  }

  FileView {
    id: catalogFile
    path: root.stateDir + "/catalog.json"
    watchChanges: false
    onLoaded: {
      var publicationPending = root.catalogPublicationPending
      var loaded = root.loadCatalog(text())
      if (publicationPending) root.completeCatalogPublication(loaded)
    }
    onLoadFailed: {
      root.clearHintHistory()
      root.catalog = null
      root.catalogState = "error"
      root.activeHintIds = []
      root.setDiagnostic("catalogLoadFailures", 1)
      if (root.catalogPublicationPending) root.completeCatalogPublication(false)
    }
  }

  Process {
    id: catalogGenerationProcess
    running: false
    stdout: StdioCollector { id: generatorStdout; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.generatorOutput = String(generatorStdout.text || "")
      var generated = Model.parseCatalogGeneration(root.generatorOutput, exitCode)
      if (!generated.ok) {
        root.catalogState = "error"
        root.setDiagnostic("catalogLoadFailures", 1)
        if (root.catalogRegenerationPending) {
          root.catalogRegenerationPending = false
          catalogChangeTimer.restart()
        }
        return
      }
      root.pendingCatalogGeneration = generated
      root.catalogPublicationPending = true
      catalogFile.reload()
    }
  }

  Process {
    id: catalogBridgeReloadProcess
    running: false
    onExited: function(exitCode, exitStatus) {
      var completedHash = root.activeBridgeReloadSourceHash
      root.activeBridgeReloadSourceHash = ""
      if (exitCode === 0) root.lastBridgeReloadSourceHash = completedHash
      else root.setDiagnostic("integrationFailures", 1)

      if (root.pendingBridgeReloadSourceHash !== "") {
        var pendingHash = root.pendingBridgeReloadSourceHash
        root.pendingBridgeReloadSourceHash = ""
        Qt.callLater(function() { root.requestCatalogBridgeReload(pendingHash) })
      }
    }
  }

  Process {
    id: integrationInspectProcess
    running: false
    stdout: StdioCollector { id: integrationInspectStdout; waitForEnd: true }
    onExited: root.applyIntegrationResult(integrationInspectStdout.text, exitCode)
  }

  Process {
    id: manualSnippetProcess
    running: false
    stdout: StdioCollector { id: manualSnippetStdout; waitForEnd: true }
    onExited: root.applyManualSnippet(manualSnippetStdout.text, exitCode)
  }

  property string integrationMutationAction: ""
  Process {
    id: integrationMutationProcess
    running: false
    stdout: StdioCollector { id: integrationMutationStdout; waitForEnd: true }
    onExited: {
      var parsed = null
      try { parsed = JSON.parse(String(integrationMutationStdout.text || "")) } catch (e) {}
      if (exitCode !== 0 || !parsed || parsed.ok !== true) {
        root.integrationState = "error"
        root.integrationStateKnown = false
        root.setDiagnostic("integrationFailures", 1)
      } else {
        root.integrationDetails = parsed
        Qt.callLater(root.inspectIntegration)
      }
    }
  }

  Timer {
    id: integrationInspectTimer
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.inspectIntegration()
  }

  Timer {
    id: fullscreenQueryTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (!root.fullscreenQueryPending || fullscreenQueryProcess.running) return
      root.fullscreenQueryPending = false
      fullscreenQueryProcess.running = true
    }
  }

  Process {
    id: fullscreenQueryProcess
    command: ["hyprctl", "-j", "activewindow"]
    running: false
    stdout: StdioCollector { id: fullscreenStdout; waitForEnd: true }
    onExited: {
      root.recordFullscreenResult(fullscreenStdout.text, exitCode)
      if (root.fullscreenQueryPending) fullscreenQueryTimer.restart()
    }
  }

  Timer {
    id: lockStatusTimeoutTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!lockStatusProcess.running) return
      root.lockStatusTimedOut = true
      root.setDiagnostic("lockQueryFailures", 1)
      root.setLockStateUnknown()
      lockStatusProcess.signal(9)
    }
  }

  Timer {
    id: lockStatusRetryTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if (!root.lockStateKnown && !lockStatusProcess.running)
        root.requestLockStatus(false)
    }
  }

  Timer {
    id: visibleLockRefreshTimer
    interval: 100
    repeat: true
    running: root.guideVisible
    onTriggered: root.requestLockStatus(false)
  }

  Process {
    id: lockStatusProcess
    command: ["omarchy-shell", "lock", "isLocked"]
    running: false
    stdout: StdioCollector { id: lockStatusStdout; waitForEnd: true }
    onExited: {
      lockStatusTimeoutTimer.stop()
      if (root.lockStatusTimedOut) {
        root.lockStatusTimedOut = false
        if (root.lockStatusRefreshPending) {
          root.lockStatusRefreshPending = false
          Qt.callLater(function() { root.requestLockStatus(false) })
        }
        return
      }
      if (root.lockStatusRefreshPending) {
        root.lockStatusRefreshPending = false
        Qt.callLater(function() { root.requestLockStatus(false) })
        return
      }
      root.recordLockStatus(lockStatusStdout.text, exitCode)
    }
  }

  Timer {
    id: layerStatusDebounceTimer
    interval: 40
    repeat: false
    onTriggered: {
      if (layerStatusProcess.running) {
        root.layerRefreshPending = true
        return
      }
      root.layerRefreshPending = false
      root.layerRequestRevision = root.layerEventRevision
      root.layerStatusTimedOut = false
      layerStatusTimeoutTimer.restart()
      layerStatusProcess.running = true
    }
  }

  Timer {
    id: layerStatusRetryTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if ((!root.credentialPromptStateKnown || root.credentialPromptActive)
          && !layerStatusProcess.running)
        root.requestLayerStatus()
    }
  }

  Timer {
    id: layerStatusTimeoutTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!layerStatusProcess.running) return
      root.layerStatusTimedOut = true
      root.credentialPromptStateKnown = false
      root.credentialPromptActive = true
      root.setDiagnostic("layerQueryFailures", 1)
      root.suppressGuide()
      layerStatusProcess.signal(9)
    }
  }

  Process {
    id: layerStatusProcess
    command: ["hyprctl", "-j", "layers"]
    running: false
    stdout: StdioCollector { id: layerStatusStdout; waitForEnd: true }
    onExited: {
      layerStatusTimeoutTimer.stop()
      if (root.layerStatusTimedOut) {
        root.layerStatusTimedOut = false
        if (root.layerRefreshPending) {
          root.layerRefreshPending = false
          Qt.callLater(function() { root.requestLayerStatus() })
        }
        return
      }
      if (root.layerRequestRevision !== root.layerEventRevision) {
        root.layerRefreshPending = false
        Qt.callLater(function() { root.requestLayerStatus() })
        return
      }
      root.recordLayerStatus(layerStatusStdout.text, exitCode)
      if (root.layerRefreshPending) {
        root.layerRefreshPending = false
        Qt.callLater(function() { root.requestLayerStatus() })
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleRawEvent(event) }
  }

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onBarConfigChanged() { root.syncSettings() }
  }

  IpcHandler {
    target: "chordlight-feasibility"
    function diagnostics(): string { return root.diagnosticsJson() }
    function reset(): string { root.resetDiagnostics(); return "ok" }
  }

  Component.onCompleted: Qt.callLater(function() {
    root.syncSettings()
    root.inspectIntegration()
    manualSnippetProcess.command = [root.controllerPath, "manual-snippet"]
    manualSnippetProcess.running = true
    root.regenerateCatalog()
    root.requestFullscreenRefresh()
    root.requestLockStatus(false)
    root.requestLayerStatus()
  })

  onShellChanged: Qt.callLater(function() {
    root.syncSettings()
  })

  SuperGuide {
    service: root
  }
}
