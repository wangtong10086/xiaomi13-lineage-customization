# Xiaomi 13 LineageOS customization

Small, reviewable customizations used after moving a Xiaomi 13 (`fuxi`) from HyperOS-derived behavior to LineageOS/Android 16.

## Included

- `health/`: a bounded boot-time permission guard for the Qualcomm battery input-suspend node.
- `launcher/`: export, plan, and apply a flat MIUI Launcher layout while keeping related apps adjacent and sorting by usage.
- `magisk/`: reproducible Magisk module sources for narrowly scoped Xiaomi TSM/OMAPI compatibility fixes.
- `root/`: read-only state collection plus version-locked, backup-first MIUI Weather and Gallery/MiuiCore mount-visibility repairs.
- `push/`: reproducible XMSF systemization, bounded GMS/FCM recovery, and fail-closed per-app XMSF registration workflows without private-data restores.
- `settings/`: export Android settings/IME state and apply a reviewed allowlist to one explicit device.
- `wallet/`: source-controlled Xiaomi Wallet two-stage signature/runtime compatibility scripts and recovery notes.
- `docs/`: upgrade and rollback guidance.

The repository intentionally excludes launcher databases, package inventories, real deny-list entries, LSPosed databases, wallet data, and device logs. Keep those as local inputs under an ignored `work/` directory.

All mutation scripts create a backup first and require explicit target parameters. Layout import scripts additionally require an explicit input file; review generated layouts before applying them.

MIUI Weather must remain outside the Magisk denylist on the current build because it consumes framework files supplied by the `MiuiCore` Magisk overlay. See `docs/miui-weather-overlay-visibility.md` before syncing root-hiding configuration.

MIUI Gallery has the same mount-visibility constraint for MIUI framework and MiCloud classes. Keep every `com.miui.gallery` process outside the denylist and see `docs/miui-gallery-overlay-visibility.md` before syncing root-hiding configuration.

Proprietary Xiaomi APKs are never committed. Magisk module builders require the matching APK as an explicit local input and verify its SHA-256 before packaging it.
