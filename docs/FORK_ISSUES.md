# Fork audit backlog

Recorded 2026-10-12 after a static security and compatibility review by Luna
at maximum reasoning effort. Audited upstream commit:
`49ff48898f98c764ae8b051b1285953d24b36673`.

Target host: Omarchy `4.0.0.alpha`, Hyprland `0.56.2-2`, Quickshell `0.3.1-1`.
All four findings are open. Fix and validate these before enabling the plugin
on this host. This file records findings; it does not implement fixes.

## 1. Authentication suppression cannot use the installed shell API

- **Priority:** High; blocks running unchanged on the target host.
- **Location:** `Service.qml`, `refreshSuppressionServices()`;
  `GuideModel.js`, guide suppression logic.
- **Finding:** The service requests `omarchy.lock` and `omarchy.polkit` through
  `shell.serviceFor()`. The installed shell scopes that API to the requesting
  plugin's own service and intentionally keeps authentication services private.
  Both requests return null, so Omakeez treats lock and Polkit prompt state as
  false. Its claimed suppression during authentication is unavailable.
- **Impact:** Hints may appear during credential prompts. The overlay does not
  take keyboard focus; this finding is not evidence of credential collection.
- **Required work:** Use a supported privacy-preserving suppression mechanism,
  with conservative behavior when suppression state is unavailable. Do not
  bypass the shell's authentication isolation or expose credential objects.
- **Acceptance:** Verify actual host API behavior and live lock/Polkit
  suppression, including startup and state transitions, while ordinary
  shortcuts continue working.

## 2. Saved guide settings are read through an unavailable property

- **Priority:** Medium; blocks correct operation on the target host.
- **Location:** `Service.qml`, `settingsEntry()`, `syncSettings()`, and
  `persistSettings()`.
- **Finding:** Omakeez reads `shell.shellConfig`, but the installed
  `PluginShellApi.qml` exposes `barConfig` and `idleConfig`, not `shellConfig`.
  Saved options therefore fall back to defaults. Saving one option can replace
  the widget entry without preserving other existing Omakeez settings.
- **Required work:** Read settings through the supported plugin API and subscribe
  to its actual change notifications. Preserve unrelated options when saving.
- **Acceptance:** Prepopulate several non-default options, change one, and
  verify all others survive a service restart and config reload.

## 3. The enabled Lua bridge can retain a stale catalog

- **Priority:** Medium.
- **Location:** `bridge.lua`, `load_catalog()` / `refresh_catalog()` and keyboard
  callback; `Service.qml`, catalog regeneration after configuration/layout events.
- **Finding:** The bridge holds an in-memory catalog snapshot. It reloads while
  disabled or when its Lua file is re-evaluated, but service-side regeneration
  does not refresh an already-enabled bridge. Depending on reload ordering, the
  display catalog and bridge matching table can disagree.
- **Impact:** New shortcuts may not highlight; removed bindings can remain in
  the bridge lookup. Keyboard layout changes can also leave matching stale.
- **Required work:** Coordinate catalog publication and bridge refresh without
  duplicate event subscriptions or reading files on every ordinary key event.
- **Acceptance:** Add, remove, and change bindings and keyboard layouts while
  enabled; verify matching updates without restarting the desktop, and malformed
  catalogs fail safely.

## 4. Controller follows symlinked state-directory paths

- **Priority:** Low; hardening/documentation mismatch.
- **Location:** `scripts/bridge-control`, `prepare_state_dir()` and its callers;
  `docs/SECURITY.md`.
- **Finding:** The controller uses `exists()`, `stat()`, and `chmod()` on the
  state-directory path without rejecting a symlink at that boundary. It can
  follow the link and operate on its target, contrary to the documented state
  path safety guarantee.
- **Impact:** Same-user state redirection and permission changes. The review did
  not establish a privilege escalation.
- **Required work:** Reject unsafe symlinked state paths before mutation and
  align controller checks with the catalog generator's protections. Keep
  documentation precise about the enforced boundary.
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
- QML tests and release linting remain unverified because `qmltestrunner` and
  `qmllint` were unavailable. No live overlay or enable/disable test was run.

No plugin was installed or enabled, and no desktop configuration was modified
during the audit. No network client, privilege escalation, or hidden credential
collection was found in the reviewed runtime code; this is a bounded review,
not a security certification.

## Follow-on feature

After the above fixes and live validation, investigate a compact overlay showing
the three most-used reachable shortcuts, filtered as modifiers are added, with
remaining keys and descriptions. Usage ranking is a future feature and is not
implemented by the audited upstream code.
