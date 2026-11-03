# NOTICE / Third-party components

This repository ships prebuilt Windows binaries unmodified, taken from the official
[bol-van/zapret-win-bundle](https://github.com/bol-van/zapret-win-bundle) and
[bol-van/zapret](https://github.com/bol-van/zapret) releases.

| File | Project | License |
|---|---|---|
| `bin/winws.exe` | zapret (bol-van) | MIT |
| `bin/WinDivert.dll`, `bin/WinDivert64.sys` | WinDivert | LGPL-3.0 |
| `bin/cygwin1.dll` | Cygwin | GPL-2.0+ (see https://cygwin.com/licensing.html) |

zapret source: https://github.com/bol-van/zapret
WinDivert source: https://github.com/basil00/WinDivert
Cygwin source: https://cygwin.com

Configuration files, host lists, installer scripts and documentation in this repository
are provided as-is under MIT.

If you redistribute this package, keep this NOTICE file and the licenses of the
components above. If you build from source instead, replace `bin/` contents with your
own builds.
