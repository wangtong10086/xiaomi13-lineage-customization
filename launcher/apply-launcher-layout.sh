#!/system/bin/sh
set -eu

DB=${DB:-/data/user_de/0/com.miui.home/databases/launcher4x6.db}
PLAN=${1:-/data/local/tmp/launcher-layout.tsv}
WORK=/data/local/tmp/launcher-layout-apply.$$
SQL=$WORK.sql
BACKUP=${DB}.before-layout.$(date +%Y%m%d-%H%M%S)

[ -r "$DB" ] || { echo "launcher database not readable: $DB" >&2; exit 1; }
[ -r "$PLAN" ] || { echo "layout plan not readable: $PLAN" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo 'sqlite3 is required' >&2; exit 1; }

tail -n +2 "$PLAN" | awk -F '\t' '
  NF < 6 { exit 2 }
  $1 !~ /^[0-9]+$/ || $2 !~ /^[A-Za-z0-9._]+$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ { exit 3 }
  { key=$4 ":" $5 ":" $6; if (seen[key]++) exit 4; if (ids[$1]++) exit 5 }
' || { echo 'layout plan failed syntax or collision validation' >&2; exit 1; }

sqlite3 "$DB" ".backup '$BACKUP'"
chmod 0600 "$BACKUP"
echo 'BEGIN IMMEDIATE;' > "$SQL"

tail -n +2 "$PLAN" | while IFS="$(printf '\t')" read -r id package _title screen x y rest; do
  count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM favorites WHERE _id=$id AND itemType=0 AND intent LIKE '%component=$package/%';")
  [ "$count" = 1 ] || { echo "plan row does not uniquely match id=$id package=$package" >&2; exit 1; }
  printf 'UPDATE favorites SET container=-100,screen=%s,cellX=%s,cellY=%s WHERE _id=%s AND itemType=0;\n' "$screen" "$x" "$y" "$id" >> "$SQL"
done
echo 'COMMIT;' >> "$SQL"

am force-stop com.miui.home
sqlite3 "$DB" < "$SQL"
restorecon -RF "$(dirname "$DB")" 2>/dev/null || true

integrity=$(sqlite3 "$DB" 'PRAGMA integrity_check;')
[ "$integrity" = ok ] || { echo "database integrity failed: $integrity" >&2; exit 1; }
duplicates=$(sqlite3 "$DB" "SELECT COUNT(*) FROM (SELECT screen,cellX,cellY,COUNT(*) AS c FROM favorites WHERE container=-100 AND itemType=0 GROUP BY screen,cellX,cellY HAVING c>1);")
[ "$duplicates" = 0 ] || { echo "duplicate desktop cells after apply: $duplicates" >&2; exit 1; }

rm -f "$SQL"
am start --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null
echo "backup=$BACKUP"
echo 'integrity=ok'
