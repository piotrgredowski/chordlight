# Chordlight branding

The GitHub fork is [`zaremb/chordlight`](https://github.com/zaremb/chordlight).
Its product name is **Chordlight** and its tagline is **“A little light for
every shortcut.”** The fork keeps its Git history.

This first branding pass changes the repository name and user-facing copy. It
keeps the existing Omarchy plugin ID, settings key, bridge protocol, managed
config marker, and `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omakeez/`
state path so current installations and their local data continue to work.

A later full internal rename is planned. That work must account for installed
plugin continuity and migration of existing settings, bridge blocks, and local
state before changing these identifiers.
