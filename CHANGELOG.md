# Changelog

## 0.2.1 — 2026-10-18

- Paused debug tracing while the desktop is locked, an Omarchy Polkit prompt
  is active, or either protection status is unknown. Existing trace files are
  preserved.

## 0.2.0 — 2026-10-17

- Rebranded the Omakeez-derived project as Chordlight with independent plugin,
  protocol, bridge, IPC, layer-shell, and runtime-state identities while
  preserving the upstream Git history and MIT copyright notices.
- Added a configurable, independently fading chord history with adjustable
  history count, duration, transparency, stack spacing, and direction.
- Added panel controls for hint position, description placement, and pill size,
  with settings saved in the Chordlight TOML file.
- Animated chord movement through the history stack and increased the screen
  edge margin for the guide.
- Added local state-transition tracing for debugging guide behavior.
- Registered shortcut descriptions now appear beside completed chords, and
  the active hint uses a compact outlined pill.

## 0.1.2 — 2026-09-03

- Fixed fresh-install setup failing with `unsafe-state-directory` after the
  catalog generator created its output directory with permissions inherited
  from the user's umask.
- The generator now creates or repairs its user-owned state directory as
  `0700`, keeps catalog files at `0600`, and rejects symlinked or foreign-owned
  output directories.

## 0.1.1 — 2026-08-31

- Fixed fresh-install catalog generation hanging when `xkbcli` inherited
  Quickshell's permanently open stdin pipe.
- Added a regression test that models the service pipe boundary and a bounded
  timeout for non-interactive catalog discovery commands.

## 0.1.0 — 2026-08-30

- Added a local visual guide for registered `SUPER`, `SHIFT`, `CTRL`, and
  `ALT` keyboard shortcuts on the focused monitor.
- Added configurable guide roots, hold delay, fullscreen behavior, hover
  expansion, keyboard-friendly guide interaction, and focused-monitor routing.
- Added consent-led Hyprland integration with exact diff preview, safe
  symlink/Git target handling, atomic replacement, rollback, and a manual
  fallback.
- Added lock-screen and Omarchy Polkit-dialog guide suppression.
- Added security-oriented bridge comments, privacy documentation, hardening,
  release-gate checks, and troubleshooting guidance.
- Kept the release focused on the visual guide: Omakeez does not store
  shortcut-use history or ship an unused full-screen browser.

Known limitations:

- The guide identifies configured binding candidates; it does not prove a
  later Hyprland dispatcher completed successfully.
- App-owned credential prompts such as 1Password are outside the Omarchy
  lock/Polkit suppression boundary. Typed content is never stored or emitted.
