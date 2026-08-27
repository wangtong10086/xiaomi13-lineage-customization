# Flat launcher layout

The workflow keeps applications directly on desktop pages—no category folders—while placing related apps next to each other and sorting each group by usage.

## Capture

Run the exporter in a rooted device shell:

```sh
sh export-launcher-inventory.sh > /sdcard/launcher-inventory.txt
```

Convert the relevant rows to a local TSV with these columns:

```text
id  title  package  usage_seconds  launches
```

Create a category TSV with `package`, `group`, and `page`. Group order is the first appearance in the category file.

## Plan

```powershell
./New-LauncherLayout.ps1 -InventoryTsv ./work/inventory.tsv -CategoriesTsv ./work/categories.tsv -OutputTsv ./work/launcher-layout.tsv
```

Review the TSV. Push it to `/data/local/tmp/launcher-layout.tsv`, then run `apply-launcher-layout.sh` in a root shell. The applier validates IDs, packages, coordinate collisions, and database integrity, and creates a timestamped database backup before changing anything.

Numeric launcher IDs are installation-specific. Always regenerate a plan after restoring apps or updating the launcher.
