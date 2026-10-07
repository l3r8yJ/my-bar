# my-bar

[![CI](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/l3r8yJ/my-bar/actions/workflows/ci.yml)
[![PDD status](https://www.0pdd.com/svg?name=l3r8yJ/my-bar)](https://www.0pdd.com/p?name=l3r8yJ/my-bar)

A small native C3 status bar for i3: keyboard layout, NetworkManager VPNs, disk
and RAM usage, plus Wi-Fi, volume and the clock from i3status.

## Install

On Arch Linux x86-64, download the `.pkg.tar.zst` package and `SHA256SUMS` from
[Releases](https://github.com/l3r8yJ/my-bar/releases) into the same directory:

```sh
sha256sum --check --ignore-missing SHA256SUMS
sudo pacman -U ./my-bar-bin-*.pkg.tar.zst
```

Alternatively, download the release's `PKGBUILD` into an empty directory,
review it, and run `paru -Bi .`. This installs the prebuilt binary; no AUR account
is needed. The package is not yet listed in the AUR.

## Use

Set the status command in your existing `~/.config/i3/config` bar block:

```i3
bar {
    status_command /usr/bin/my-bar
}
```

For a source installation, use `~/.local/bin/my-bar` instead. In
`~/.config/i3status/config`, set:

```text
general {
    output_format = "i3bar"
    interval = 1
}
```

Keep your existing i3status modules and restart i3 with `i3-msg restart`.
Keyboard status requires an X11 session; VPN status requires NetworkManager.
Run `my-bar --once` to inspect one status frame.

## Build from source

Install the build and check tools on Arch:

```sh
sudo pacman -S --needed base-devel git just jq libx11 systemd-libs dbus i3status curl
git clone https://github.com/l3r8yJ/my-bar.git
cd my-bar
just build
just install
```

The build downloads a pinned C3 compiler and formatter into `.tools/`.

`just build` produces `build/my-bar`. `just install` installs it to
`~/.local/bin/my-bar`.

Use `just check` to run formatting, compiler checks, tests and sanitizers;
`just format` to format the code; and `just clean` to remove build files.
