#!/system/bin/sh

# Root-side executor for privacy-safe Thanox reclaim requests. It reads only
# fixed epoch/package/outcome lines and never reads FCM payload, notifications,
# tokens, contacts, or WeChat private storage.

BB=/data/adb/magisk/busybox
STATE_DIR=/data/adb/wechat-process-reclaimer
PID_FILE="$STATE_DIR/worker.pid"
WORKER_LOG="$STATE_DIR/reclaim.log"
PACKAGE=com.tencent.mm

mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"

if [ -s "$PID_FILE" ]; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi
fi

echo $$ > "$PID_FILE"
chmod 0600 "$PID_FILE"

cleanup() {
  current=$(cat "$PID_FILE" 2>/dev/null)
  [ "$current" = "$$" ] && rm -f "$PID_FILE"
}

trap cleanup EXIT
trap 'exit 0' INT TERM

latest_request_epoch() {
  file=$1
  "$BB" awk '
    /^epoch_ms=[0-9]+ package=com\.tencent\.mm outcome=am_kill_(ok|failed)$/ {
      split($1, part, "="); latest=part[2]
    }
    END { if (latest != "") print latest; else print 0 }
  ' "$file" 2>/dev/null
}

process_source() {
  source_name=$1
  request_file=$2
  cursor_file="$STATE_DIR/$source_name.cursor"

  if [ ! -f "$cursor_file" ]; then
    latest_request_epoch "$request_file" > "$cursor_file"
    chmod 0600 "$cursor_file"
    return
  fi

  last=$(cat "$cursor_file" 2>/dev/null)
  case "$last" in
    ''|*[!0-9]*) last=0 ;;
  esac

  "$BB" awk -v last="$last" '
    /^epoch_ms=[0-9]+ package=com\.tencent\.mm outcome=am_kill_(ok|failed)$/ {
      split($1, part, "="); if (part[2] > last) print part[2]
    }
  ' "$request_file" 2>/dev/null | while IFS= read -r request_epoch; do
    [ -n "$request_epoch" ] || continue
    # Avoid mksh's 32-bit arithmetic overflow when converting epoch seconds.
    now=$("$BB" date +%s%3N)

    if dumpsys activity activities 2>/dev/null |
        grep -m 1 'topResumedActivity=.* u0 com\.tencent\.mm/' >/dev/null; then
      outcome=skipped_race_foreground
    else
      am kill "$PACKAGE" >/dev/null 2>&1
      command_code=$?
      sleep 2
      process_count=$(ps -A -o NAME 2>/dev/null |
        grep -c '^com\.tencent\.mm\(:[^[:space:]]*\)\?$')
      stopped_line=$(dumpsys package "$PACKAGE" 2>/dev/null |
        grep -m 1 '^ *User 0:')
      if echo "$stopped_line" | grep -q 'stopped=true'; then
        outcome=stopped_violation
      elif [ "$command_code" -ne 0 ]; then
        outcome=command_failed
      elif [ "$process_count" -eq 0 ]; then
        outcome=zero
      else
        outcome=remaining
      fi
    fi

    echo "epoch_ms=$now source=$source_name request_epoch_ms=$request_epoch outcome=$outcome" >> "$WORKER_LOG"
    chmod 0600 "$WORKER_LOG"
    echo "$request_epoch" > "$cursor_file"
    chmod 0600 "$cursor_file"
  done
}

while true; do
  profile_io=$(find /data/system -maxdepth 2 -type d -name profile_user_io 2>/dev/null |
    head -n 1)
  if [ -n "$profile_io" ]; then
    process_source fcm "$profile_io/wechat_fcm_reclaim.log"
    process_source post_use "$profile_io/wechat_post_use_reclaim.log"
    process_source smoke "$profile_io/wechat_reclaim_smoke.log"
  fi
  sleep 2
done
