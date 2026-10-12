# Fork audit backlog

Recorded 2026-10-12 after a static security and compatibility review by Luna
at maximum reasoning effort. Audited upstream commit:
`49ff48898f98c764ae8b051b1285953d24b36673`.

Target host: Omarchy `4.0.0.alpha`, Hyprland `0.56.2-2`, Quickshell `0.3.1-1`.
Findings 1–3 still have acceptance gates before enabling the plugin on this
host. Finding 4 is fixed in the fork and covered by automated fixtures. This
file tracks findings and acceptance; implementation lives in the plugin
runtime and supporting files.

## 1. Authentication suppression cannot use the installed shell API

- **Priority:** High; blocks running unchanged on the target host.
- **Status:** Implementation added to the fork; live lock/Polkit acceptance is
  still required before closing this finding.
- **Location:** `Service.qml`, lock and layer suppression state;
  `GuideModel.js`, guide suppression logic.
- **Finding:** The service requests `omarchy.lock` and `omarchy.polkit` through
  `shell.serviceFor()`. The installed shell scopes that API to the requesting
  plugin's own service and intentionally keeps authentication services private.
  Both requests return null, so Omakeez treats lock and Polkit prompt state as
  false. Its claimed suppression during authentication is unavailable.
- **Impact:** Hints may appear during credential prompts. The overlay does not
  take keyboard focus; this finding is not evidence of credential collection.
- **Implementation:** Omakeez now reads only the public lock `isLocked`
  boolean, observes Hyprland layer events for the exact `omarchy-polkit`
  namespace, and checks current layer inventory. Unknown, stale, malformed, or
  failed status is treated as suppressed. A fresh lock check gates every new
  guide press; active guides are rechecked while visible.
- **Remaining work:** Complete automated and live acceptance checks. Do not
  bypass the shell's authentication isolation or expose credential objects.
- **Acceptance:** Verify actual host API behavior and live lock/Polkit
  suppression, including startup and state transitions, while ordinary
  shortcuts continue working.

## 2. Saved guide settings are read through an unavailable property

- **Priority:** Medium; blocks correct operation on the target host.
- **Status:** Implementation added; automated tests pass. Target-shell
  persistence/reload acceptance remains to be completed.
- **Location:** `Service.qml`, `settingsEntry()`, `syncSettings()`, and
  `persistSettings()`.
- **Finding:** Omakeez reads `shell.shellConfig`, but the installed
  `PluginShellApi.qml` exposes `barConfig` and `idleConfig`, not `shellConfig`.
  Saved options therefore fall back to defaults. Saving one option can replace
  the widget entry without preserving other existing Omakeez settings.
- **Implementation:** Read from the supported `barConfig` API, sync on its
  change signal, and preserve every existing entry field when saving one value.
- **Remaining work:** Complete target-shell persistence and reload acceptance.
- **Acceptance:** Prepopulate several non-default options, change one, and
  verify all others survive a service restart and config reload.

## 3. The enabled Lua bridge can retain a stale catalog

- **Priority:** Medium.
- **Status:** Implementation added; automated tests cover catalog repair,
  bridge refresh, fail-closed behavior, and reload-loop guards. Live
  binding/layout changes remain to be verified in Hyprland.
- **Location:** `bridge.lua`, `load_catalog()` and keyboard callback;
  `Service.qml`, catalog regeneration after configuration/layout events.
- **Finding:** The bridge holds an in-memory catalog snapshot. It reloads while
  disabled or when its Lua file is re-evaluated, but service-side regeneration
  does not refresh an already-enabled bridge. Depending on reload ordering, the
  display catalog and bridge matching table can disagree.
- **Impact:** New shortcuts may not highlight; removed bindings can remain in
  the bridge lookup. Keyboard layout changes can also leave matching stale.
- **Required work:** Coordinate catalog publication and bridge refresh without
  duplicate event subscriptions or reading files on every ordinary key event.
- **Implementation:** Publish the Lua bridge table before `catalog.json` and
  treat successful generation plus catalog validation as the publication
  boundary. Repair missing or damaged artifacts, reload Hyprland once for each
  changed catalog while integration is enabled, and coalesce changes during a
  reload. A missing or malformed catalog leaves the bridge inert until config
  evaluation retries it; keyboard callbacks perform no file I/O.
- **Acceptance:** Add, remove, and change bindings and keyboard layouts while
  enabled; verify matching updates without restarting the desktop, and malformed
  catalogs fail safely.

## 4. Controller follows symlinked state-directory paths

- **Priority:** Low; hardening/documentation mismatch.
- **Status:** Fixed in the fork; automated rejection and parent-symlink fixtures
  pass.
- **Location:** `scripts/bridge-control`, `prepare_state_dir()` and its callers;
  `docs/SECURITY.md`.
- **Finding:** The controller uses `exists()`, `stat()`, and `chmod()` on the
  state-directory path without rejecting a symlink at that boundary. It can
  follow the link and operate on its target, contrary to the documented state
  path safety guarantee.
- **Impact:** Same-user state redirection and permission changes. The review did
  not establish a privilege escalation.
- **Implementation:** Mutations reject a symlink at the final state-directory
  component, validate the opened directory's type, owner, and permissions, and
  anchor lock and backup operations to that directory descriptor. Parent-path
  symlinks remain supported.
- **Acceptance:** Temporary fixtures cover directory symlinks, dangling links,
  foreign ownership, and unsafe permissions; rejected paths must leave targets
  and their permissions unchanged.

## Validation already performed

- Passed fixture suites: bridge, catalog, hardening, inspector, manifest smoke,
  onboarding, and patcher.
- Live read-only catalog generation succeeded with 231 bindings; temporary
  output used directory mode `0700` and file mode `0600`.
- Simulated bridge matrix passed for 269 matches. It did not execute callbacks
  inside the running Hyprland compositor.
- Read-only inspection found the real Hyprland configuration safe to patch,
  with no existing Omakeez managed block. No patch was applied.
- Since the original audit, `PATH=/usr/lib/qt6/bin:$PATH tests/shell/run all`
  passed, including service/guide QML tests and release-gate static checks.
  `qmllint` returned success but reported unresolved Omarchy/Quickshell imports
  and component types in this environment.
- State-directory hardening fixtures pass for symlinked and dangling leaves,
  foreign ownership, unsafe permissions, unchanged rejected targets, and
  symlinked parent paths.
- Live lock/Polkit transitions remain unverified: `omarchy-shell lock isLocked`
  reported that the shell was not running, and `hyprctl -j layers` could not
  connect to Hyprland. No live overlay or enable/disable test was run.

No plugin was installed or enabled, and no desktop configuration was modified
during the audit. No network client, privilege escalation, or hidden credential
collection was found in the reviewed runtime code; this is a bounded review,
not a security certification.

## Follow-on feature

After the above fixes and live validation, investigate a compact overlay showing
the three most-used reachable shortcuts, filtered as modifiers are added, with
remaining keys and descriptions. Usage ranking is a future feature and is not
implemented by the audited upstream code.
