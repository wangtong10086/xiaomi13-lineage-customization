#!/system/bin/sh
set -eu

DB=${1:-/data/user_de/0/com.miui.home/databases/launcher4x6.db}
[ -r "$DB" ] || { echo "launcher database not readable: $DB" >&2; exit 1; }

echo 'FAVORITES'
sqlite3 -separator '|' "$DB" \
  "SELECT _id,title,container,screen,cellX,cellY,itemType,intent FROM favorites ORDER BY container,screen,cellY,cellX,_id;"
echo 'SCHEMA'
sqlite3 "$DB" ".schema favorites"
echo 'INTEGRITY'
sqlite3 "$DB" 'PRAGMA integrity_check;'
echo 'USAGE'
dumpsys usagestats 2>/dev/null || true
