# Chordlight identity

The fork is published as
[`zaremb/chordlight`](https://github.com/zaremb/chordlight), with the product
name **Chordlight** and tagline **“A little light for every shortcut.”** It
keeps the upstream Git history while using independent runtime identities:

- Omarchy plugin ID: `io.github.zaremb.chordlight`
- Hyprland event protocol: `chordlight:v1:`
- Managed config markers: `Chordlight managed bridge`
- Layer-shell namespace: `chordlight-guide`
- IPC target: `chordlight-feasibility`
- Runtime state: `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/chordlight/`

Chordlight is a separate plugin, not a renamed marketplace update of Omakeez.
It does not read, import, or delete Omakeez settings or runtime state. To switch,
disable the visual guide in the old Omakeez panel first, remove that plugin,
then install this repository directly. The old state is left untouched; its
backups may still be useful for restoring a previous Hyprland config.
