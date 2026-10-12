# Privacy-first guide coverage

Status: compact chord hint implemented on the fork.

## Current boundary

Chordlight provides a transient outlined key hint for the four Hyprland modifier
roots `SUPER`, `SHIFT`, `CTRL`, and `ALT`. After the configured delay, a held
modifier appears only if it prefixes a registered, guide-eligible shortcut.
Holding the matching shortcut key extends the hint to the complete chord; its
release shows its registered description beside the chord for up to 1.5
seconds. The service retains only the opaque binding ID in memory for that
brief display; suppression or a new guide sequence clears it. Each root can be
turned on or off without changing any underlying shortcut.

The bridge receives Hyprland keyboard transitions but reduces them immediately
to allowlisted modifier/code/phase/submap tuples. It emits only guide state,
modifier masks, and opaque IDs for guide-eligible matches. It holds a matched
ID only until its physical key is released; unmatched keys are discarded and
never leave Hyprland. See [SECURITY.md](SECURITY.md) and the in-source comments
in [bridge.lua](../bridge.lua) for the complete boundary.

## Data minimization

The release stores no activity history and has no policy file:

- no raw key logs, typed text, passwords, or command arguments;
- no per-binding counts, timestamps, or any other usage history;
- no activity-data files or unused full-screen browser; and
- no network telemetry.

Only the regenerated catalog/bridge lookup and controller safety files remain.
They describe registered shortcuts and config transactions; they do not record
how the user uses their keyboard.

## Future direction

Application-local providers—for example documented Tmux or Herdr bindings—may
be added later as read-only reference sources. They must never enter the
Hyprland bridge match table, observe raw application keystrokes, or add
activity tracking. Any future per-binding selection policy requires a separate
privacy review and explicit user consent.
