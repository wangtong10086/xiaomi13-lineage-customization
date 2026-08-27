# Upgrade checklist

After an Android/LineageOS or MIUI Launcher update:

1. Boot once without changing launcher or root databases.
2. Confirm `sys.boot_completed=1`, SELinux enforcing, and no new crash-loop.
3. Re-run `root/collect-root-state.sh` and compare only structural state; do not commit its output.
4. Verify that the health sysfs path still exists and that the Android health service owns the node after boot.
5. Export a fresh launcher inventory. Database schema, table names, and intent formats may change between launcher versions.
6. Regenerate the layout rather than replaying old numeric row IDs blindly.
7. Apply framework modules one at a time and keep package scopes minimal.

If a launcher update changes `launcher4x6.db` or the `favorites` columns, stop and update the exporter/applier before making writes.
