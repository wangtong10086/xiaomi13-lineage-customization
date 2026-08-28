#!/system/bin/sh
set -eu

DB=${DB:-/data/user_de/0/com.miui.home/databases/launcher4x6.db}
PACKAGE=${1:-}
COMPONENT=${2:-}
TITLE=${3:-}
SCREEN=${4:-}
CELL_X=${5:-}
CELL_Y=${6:-}

usage() {
  echo 'usage: ensure-launcher-shortcut.sh PACKAGE COMPONENT TITLE SCREEN CELL_X CELL_Y' >&2
  exit 2
}

[ -n "$PACKAGE" ] && [ -n "$COMPONENT" ] && [ -n "$TITLE" ] || usage
case "$PACKAGE" in *[!A-Za-z0-9._]*|'') usage ;; esac
case "$COMPONENT" in "$PACKAGE"/*) ;; *) echo 'component must belong to package' >&2; exit 1 ;; esac
case "$SCREEN:$CELL_X:$CELL_Y" in *[!0-9:]*) usage ;; esac
[ -r "$DB" ] || { echo "launcher database not readable: $DB" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo 'sqlite3 is required' >&2; exit 1; }

resolved=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$PACKAGE" 2>/dev/null | tail -n 1)
[ "$resolved" = "$COMPONENT" ] || { echo "launcher component mismatch: resolved=$resolved expected=$COMPONENT" >&2; exit 1; }

occupied=$(sqlite3 "$DB" "SELECT COUNT(*) FROM favorites WHERE container=-100 AND screen=$SCREEN AND cellX=$CELL_X AND cellY=$CELL_Y AND itemType=0 AND intent NOT LIKE '%component=$COMPONENT;%';")
[ "$occupied" = 0 ] || { echo "destination cell is occupied: $SCREEN/$CELL_X/$CELL_Y" >&2; exit 1; }

title_hex=$(printf '%s' "$TITLE" | od -An -tx1 | tr -d ' \n')
intent="#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;launchFlags=0x10200000;component=$COMPONENT;end"
intent_hex=$(printf '%s' "$intent" | od -An -tx1 | tr -d ' \n')
backup=${DB}.before-shortcut.$(date +%Y%m%d-%H%M%S)
sqlite3 "$DB" ".backup '$backup'"
chmod 0600 "$backup"

existing=$(sqlite3 "$DB" "SELECT COUNT(*) FROM favorites WHERE itemType=0 AND intent LIKE '%component=$COMPONENT;%';")
case "$existing" in
  0)
    sqlite3 "$DB" "BEGIN IMMEDIATE;
      INSERT INTO favorites (_id,title,intent,container,screen,cellX,cellY,spanX,spanY,itemType,appWidgetId,isShortcut,iconType,displayMode,launchCount,sortMode,itemFlags,profileId,originWidgetId)
      VALUES ((SELECT COALESCE(MAX(_id),0)+1 FROM favorites),CAST(X'$title_hex' AS TEXT),CAST(X'$intent_hex' AS TEXT),-100,$SCREEN,$CELL_X,$CELL_Y,1,1,0,-1,0,0,0,'0',0,0,0,-1);
      COMMIT;"
    ;;
  1)
    sqlite3 "$DB" "BEGIN IMMEDIATE;
      UPDATE favorites SET title=CAST(X'$title_hex' AS TEXT),container=-100,screen=$SCREEN,cellX=$CELL_X,cellY=$CELL_Y
      WHERE itemType=0 AND intent LIKE '%component=$COMPONENT;%';
      COMMIT;"
    ;;
  *) echo "component has multiple launcher rows: $existing" >&2; exit 1 ;;
esac

integrity=$(sqlite3 "$DB" 'PRAGMA integrity_check;')
[ "$integrity" = ok ] || { echo "database integrity failed: $integrity" >&2; exit 1; }
duplicates=$(sqlite3 "$DB" "SELECT COUNT(*) FROM (SELECT screen,cellX,cellY,COUNT(*) c FROM favorites WHERE container=-100 AND itemType=0 GROUP BY screen,cellX,cellY HAVING c>1);")
[ "$duplicates" = 0 ] || { echo "duplicate desktop cells after apply: $duplicates" >&2; exit 1; }

restorecon -RF "$(dirname "$DB")" 2>/dev/null || true
am force-stop com.miui.home
am start --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null
echo "backup=$backup"
echo 'integrity=ok'
