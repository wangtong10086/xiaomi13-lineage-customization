#!/system/bin/sh
set -eu

OUT=${1:-}
[ -n "$OUT" ] || { echo "usage: $0 OUTPUT_DIRECTORY" >&2; exit 2; }
case "$OUT" in
  /data/local/tmp/*|/sdcard/*) ;;
  *) echo 'output must be under /data/local/tmp or /sdcard' >&2; exit 1 ;;
esac

umask 077
mkdir -p "$OUT"
chmod 0700 "$OUT" 2>/dev/null || true

MAGISK_DB=/data/adb/magisk.db
VECTOR_DB=/data/adb/lspd/config/modules_config.db

if [ -r "$MAGISK_DB" ]; then
  sqlite3 -header -separator "$(printf '\t')" "$MAGISK_DB" \
    "SELECT key,value FROM settings ORDER BY key;" > "$OUT/magisk-settings.tsv"
else
  : > "$OUT/magisk-settings.tsv"
fi

{
  printf 'module_id\tdisabled\tname\tversion\n'
  for module in /data/adb/modules/*; do
    [ -d "$module" ] || continue
    id=$(basename "$module")
    disabled=0; [ -f "$module/disable" ] && disabled=1
    name=$(sed -n 's/^name=//p' "$module/module.prop" 2>/dev/null | head -n 1 | tr '\t\r\n' '   ')
    version=$(sed -n 's/^version=//p' "$module/module.prop" 2>/dev/null | head -n 1 | tr '\t\r\n' '   ')
    printf '%s\t%s\t%s\t%s\n' "$id" "$disabled" "$name" "$version"
  done
} > "$OUT/magisk-modules.tsv"

if [ -r "$VECTOR_DB" ]; then
  sqlite3 -header -separator "$(printf '\t')" "$VECTOR_DB" \
    "SELECT module_pkg_name,enabled FROM modules ORDER BY module_pkg_name;" > "$OUT/framework-modules.tsv"
  sqlite3 -header -separator "$(printf '\t')" "$VECTOR_DB" \
    "SELECT m.module_pkg_name,s.app_pkg_name,s.user_id FROM scope AS s JOIN modules AS m ON m.mid=s.mid ORDER BY m.module_pkg_name,s.app_pkg_name,s.user_id;" > "$OUT/framework-scopes.tsv"
  sqlite3 "$VECTOR_DB" 'PRAGMA integrity_check;' > "$OUT/framework-integrity.txt"
else
  : > "$OUT/framework-modules.tsv"
  : > "$OUT/framework-scopes.tsv"
  printf 'database-unavailable\n' > "$OUT/framework-integrity.txt"
fi

chmod 0600 "$OUT"/* 2>/dev/null || true
printf 'private policy snapshot written to %s\n' "$OUT"
