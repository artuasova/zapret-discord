# Changelog

## v1.2.0 - 2026-11-03

Update and voice verification release (no installer - zip + install.bat stays).

### Added
- `tools/check-update.ps1`: compares local `VERSION` with the latest GitHub release (exit 0 = update, 1 = current,
  2 = check failed). Tray menu item "Проверить обновления" opens the release page when a new version exists.
- `tools/voice-test.ps1`: live voice verification (voice ports in service config, Discord UDP endpoints,
  recent RTC_CONNECTED evidence). Exit codes: 0 ok, 1 broken, 2 not testable.
- `blockcheck.ps1 -Voice`: after picking a strategy, validates live voice and falls back to the next
  working strategy if voice is broken.
- Start Menu shortcuts are not shipped; the zip/tray remains the entry point.

### Changed
- `install.bat` and `uninstall.bat` support `/quiet` (useful for automation).

## v1.1.0 - 2026-11-03

Self-healing release: bypass now recovers itself when Discord breaks or the DPI updates.

### Added
- `tools/watchdog.ps1` + scheduled task `zapret-discord-watchdog` (every 5 minutes, SYSTEM):
  health-checks `discord.com/api`, tries a service restart after 2 failures, and after 3 failures runs
  auto-blockcheck to pick a new working strategy.
- Auto-recovery guards: VPN/tunnel detection (does not test or switch strategy while a tunnel is the default
  route), 60-minute cooldown between auto-switches, single-instance lock.
- `tools/tray.ps1` + logon task `zapret-discord-tray`: tray icon with status, turn bypass on/off,
  manual check, blockcheck, diagnostics, open logs.
- `tools/collect-diagnostics.ps1`: one-click diagnostics zip (system info, service state, routes, curl results,
  logs) for bug reports.
- `tools/install-tasks.ps1` / `tools/remove-tasks.ps1`: register/remove both scheduled tasks.
- `VERSION` file, blockcheck history (`tools/logs/strategies-history.jsonl`) and `last-strategy.json`.
- Blockcheck now has `-Auto` and `-Force` modes, exit codes (0 applied, 2 VPN active, 3 already running, 4 no strategy).

### Changed
- Logs now live in `tools/logs/`.
- `install.bat` installs the scheduled tasks and prints the installed version.
- `uninstall.bat` removes the scheduled tasks first.
- CI release package includes all tools.

## v1.0.0 - 2026-11-03

Initial public release: Discord-only local DPI bypass for Windows.

- TLS ClientHello desync (`fake,multidisorder` + `md5sig`, port 443 and Cloudflare media ports).
- Discord voice/media: L7 `discord,stun` on UDP `50000-50099`, `19294-19344`, media WS on port `2096`.
- Windows service with autostart and crash recovery, installer/uninstaller, presets, blockcheck, verify tool.
