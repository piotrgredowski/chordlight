# Security and privacy

Chordlight is an Omarchy shell plugin. Omarchy plugins are not sandboxed, so
installing one grants its QML, JavaScript, Lua, and helper scripts the normal
capabilities of the current user session. Review this repository and its
updates before installing them.

## What Chordlight reads

- The resolved Hyprland Lua configuration, only to inspect and safely manage
  Chordlight's existing managed bridge block.
- `hyprctl binds` and the current XKB keymap, only to generate a display
  catalog and match allowlist.
- The public `omarchy-shell lock isLocked` result, which is parsed as exactly
  `true` or `false` and is never queried for authentication details.
- Hyprland layer inventory and layer lifecycle events, filtered to the exact
  `omarchy-polkit` namespace so the guide can stay hidden during Omarchy's
  credential dialog.
- Active-window fullscreen state and plugin lifecycle state.
- The generated `catalog.json` and `bridge-catalog.lua` files described below.

## What Chordlight writes

Only after the user reviews the exact diff and clicks the enable/disable action,
the controller may atomically edit the resolved Hyprland configuration target.
It writes local operational files in:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omakeez/
```

The leaf state directory is user-owned with mode `0700`; generated files use
mode `0600`. Catalog generation repairs legacy user-owned state directories
that were created with broader permissions and rejects symlinked or
foreign-owned output directories. Controller mutations reject a symlink at
the final `omakeez` directory, including a dangling symlink, and reject
foreign-owned or group/world-accessible state directories before changing
them. Symlinks in parent directories are allowed, so a relocated
`XDG_STATE_HOME` remains supported.

| File or directory | Purpose |
|---|---|
| `catalog.json` | Registered shortcut descriptions, modifier/key metadata, and opaque SHA-256 IDs. |
| `bridge-catalog.lua` | Compact local allowlist for the Hyprland bridge. |
| `bridge-control.lock` | Advisory lock that prevents concurrent bridge edits. |
| `backups/` | Protected rollback copy and metadata, created only for a configuration mutation. |

The catalog generator uses dispatcher arguments only while deriving opaque IDs.
It does not write those arguments into the catalog, bridge lookup, or protocol.

## Keyboard boundary

The small [bridge source](../bridge.lua) is the code linked from the Chordlight
setup panel. Its comments describe each boundary in place.

Hyprland invokes its callback for keyboard transitions. The bridge reads a
numeric code and press/release state, retains an in-memory mask for `SUPER`,
`SHIFT`, `CTRL`, and `ALT`, and checks exact allowlisted tuples. It emits guide
lifecycle names, modifier masks, and opaque IDs for configured matches. For a
guide-eligible match, it keeps only the matched ID in memory until that
physical key is released so the outline can disappear. Unmatched codes are
discarded immediately; the bridge has no history buffer, counter, timestamp
log, or typed-character storage.

The bridge does not use `/dev/input`, evdev, sockets, subprocesses, root,
`sudo`, `pkexec`, a package manager, or network APIs. Its one local catalog
load can retry after asynchronous catalog generation; after that, normal input
matching is in-memory. The only external URL in the plugin is the user-clicked
browser link to the public bridge source.

The shell service checks lock state through the public `lock isLocked` IPC
method only. It does not access the private lock or Polkit service objects. A
missing, timed-out, malformed, or failed lock/layer query keeps the guide
hidden. Hyprland's `openlayer`/`closelayer` events are matched against the exact
`omarchy-polkit` namespace; the service reads a fresh layer inventory after
startup and layer transitions to account for multiple monitors.

Chordlight does **not** persist typed text, passwords, raw key sequences,
keybinding-use history, commands, dispatcher arguments, window titles,
application identifiers, or telemetry.

After a registered shortcut key is released, the shell service may retain its
opaque binding ID in memory for at most 1.5 seconds so the guide can display
the catalog description. New guide input, suppression, or timeout clears it;
the ID and description are never written to a history or statistics file.

## Configuration safety

The controller accepts only a user-owned, writable, regular target with one
hard link, inside the user home or a user-owned Git root. It preserves a safe
symlink's target rather than replacing the symlink itself. Before replacement,
it checks the inspected content hash, creates a `0700` rollback directory with
`0600` contents, validates Lua syntax, reloads Hyprland, checks
`hyprctl configerrors`, and rolls back on a failed live mutation.

No elevated privileges are offered. If any check fails, automatic setup stops
and the panel provides a manual snippet instead.

## Auditing a live installation

1. Review [bridge.lua](../bridge.lua),
   [generate-catalog](../scripts/generate-catalog), and
   [bridge-control](../scripts/bridge-control).
2. Inspect the Chordlight state directory listed above; it should contain only the
   operational files described in this document.
3. Open the panel's **Review exact change** link before enabling.
4. Confirm the resolved Hyprland file contains exactly one guarded block:

   ```lua
   -- >>> Omakeez managed bridge >>>
   pcall(dofile, "…/io.github.cyprusad.omakeez/bridge.lua")
   -- <<< Omakeez managed bridge <<<
   ```

Use the installed plugin's controller for a live audit. A checkout embeds a
different bridge path and will correctly refuse to manage an installed block.

## Reporting a vulnerability

Do not include passwords, private configuration, or state files in a public
issue. For sensitive reports, use GitHub Security Advisories:
<https://github.com/zaremb/chordlight/security/advisories/new>. For ordinary
bugs, open a [GitHub issue](https://github.com/zaremb/chordlight/issues).
