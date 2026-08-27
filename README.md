# Xiaomi 13 LineageOS customization

Small, reviewable customizations used after moving a Xiaomi 13 (`fuxi`) from HyperOS-derived behavior to LineageOS/Android 16.

## Included

- `health/`: a bounded boot-time permission guard for the Qualcomm battery input-suspend node.
- `launcher/`: export, plan, and apply a flat MIUI Launcher layout while keeping related apps adjacent and sorting by usage.
- `root/`: read-only state collection for Magisk, enabled modules, LSPosed/Vector scope rows, SELinux, and startup health.
- `docs/`: upgrade and rollback guidance.

The repository intentionally excludes launcher databases, package inventories, real deny-list entries, LSPosed databases, wallet data, and device logs. Keep those as local inputs under an ignored `work/` directory.

All mutation scripts create a backup first and require an explicit input file. Review generated layouts before applying them.
