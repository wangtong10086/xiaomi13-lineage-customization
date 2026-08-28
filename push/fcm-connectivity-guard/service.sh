#!/system/bin/sh

PATH=/system/bin:/system/xbin:/vendor/bin:/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/sbin

MODDIR=${0%/*}
STATE_DIR=/data/adb/fcm-connectivity-guard
LOG="$STATE_DIR/health.log"
PID_FILE="$STATE_DIR/health.pid"
LAST_HARD_FILE="$STATE_DIR/last-hard-recovery"

CHECK_INTERVAL_SEC=15
HARD_RECOVERY_AFTER_SAMPLES=2
HARD_RECOVERY_MIN_INTERVAL_SEC=1800
COMMAND_TIMEOUT_SEC=10
[ -r "$MODDIR/config.conf" ] && . "$MODDIR/config.conf"

rotate_log() {
  [ -f "$LOG" ] || return 0
  size=$(stat -c '%s' "$LOG" 2>/dev/null || echo 0)
  if [ "${size:-0}" -gt 262144 ]; then
    mv -f "$LOG" "$LOG.1"
  fi
}

log() {
  rotate_log
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

run_quiet() {
  timeout "$COMMAND_TIMEOUT_SEC" "$@" >/dev/null 2>&1
}

package_installed() {
  run_quiet cmd package path "$1"
}

acquire_lock() {
  mkdir -p "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  if [ -r "$PID_FILE" ]; then
    old_pid=$(sed -n '1p' "$PID_FILE" 2>/dev/null)
    if [ -n "$old_pid" ] && [ -d "/proc/$old_pid" ]; then
      old_cmd=$(tr '\000' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null)
      case "$old_cmd" in
        *fcm-connectivity-guard*service.sh*) log "already running pid=$old_pid"; exit 0 ;;
      esac
    fi
    rm -f "$PID_FILE"
  fi
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
  trap 'exit 0' HUP INT TERM
}

wait_for_boot() {
  waited=0
  while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$waited" -lt 300 ]; do
    sleep 5
    waited=$((waited + 5))
  done
  log "boot_completed=$(getprop sys.boot_completed) waited=${waited}s"
}

allow_required_background_ops() {
  pkg=$1
  package_installed "$pkg" || return 0
  run_quiet pm unsuspend "$pkg"
  run_quiet am set-standby-bucket "$pkg" active
  for op in POST_NOTIFICATION RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND WAKE_LOCK START_FOREGROUND; do
    run_quiet cmd appops set --user 0 "$pkg" "$op" allow
  done
  run_quiet pm grant "$pkg" android.permission.POST_NOTIFICATIONS
}

prepare_core_packages() {
  for pkg in com.google.android.gms com.google.android.gsf com.android.vending com.google.android.gm; do
    allow_required_background_ops "$pkg"
  done
  if package_installed com.google.android.gms; then
    run_quiet cmd deviceidle whitelist +com.google.android.gms
  fi
  log "core policy checked"
}

network_validated() {
  timeout "$COMMAND_TIMEOUT_SEC" dumpsys connectivity 2>/dev/null | grep -q 'IS_VALIDATED'
}

gms_persistent_pid() {
  pidof com.google.android.gms.persistent 2>/dev/null | awk '{print $1}'
}

gms_socket_kind() {
  gpid=$(gms_persistent_pid)
  [ -n "$gpid" ] && [ -d "/proc/$gpid/fd" ] || return 1
  fallback443=0
  for fd in /proc/$gpid/fd/*; do
    link=$(readlink "$fd" 2>/dev/null) || continue
    case "$link" in
      socket:\[*\]) inode=${link#socket:[}; inode=${inode%]} ;;
      *) continue ;;
    esac
    for table in /proc/net/tcp /proc/net/tcp6; do
      [ -r "$table" ] || continue
      remote=$(awk -v inode="$inode" 'NR > 1 && $4 == "01" && $10 == inode { print toupper($3); exit }' "$table" 2>/dev/null)
      [ -n "$remote" ] || continue
      port=${remote##*:}
      case "$port" in
        146C|146D|146E) echo mtalk; return 0 ;;
        01BB) fallback443=1 ;;
      esac
    done
  done
  if [ "$fallback443" -eq 1 ]; then
    echo fallback443
    return 0
  fi
  return 1
}

soft_reconnect() {
  run_quiet am broadcast --user 0 -a com.google.android.gms.gcm.ACTION_TRIGGER_CONNECT --ez force true -p com.google.android.gms
  run_quiet am startservice --user 0 -n com.google.android.gms/.gcm.GcmService
  log "soft recovery requested"
}

hard_reconnect() {
  now=$(date +%s)
  last=0
  [ -r "$LAST_HARD_FILE" ] && last=$(sed -n '1p' "$LAST_HARD_FILE" 2>/dev/null)
  case "$last" in *[!0-9]*|'') last=0 ;; esac
  elapsed=$((now - last))
  [ "$elapsed" -ge "$HARD_RECOVERY_MIN_INTERVAL_SEC" ] || return 1

  gpid=$(gms_persistent_pid)
  [ -n "$gpid" ] || return 1
  kill -TERM "$gpid" >/dev/null 2>&1 || return 1
  echo "$now" > "$LAST_HARD_FILE"
  log "hard recovery requested for gms persistent pid=$gpid"
  return 0
}

main() {
  umask 077
  acquire_lock
  wait_for_boot
  prepare_core_packages

  missing=0
  last_state=
  while true; do
    if ! network_validated; then
      state=network-unvalidated
      missing=0
    else
      kind=$(gms_socket_kind 2>/dev/null)
      if [ -n "$kind" ]; then
        state="connected-$kind"
        missing=0
      else
        missing=$((missing + 1))
        state="connection-missing-$missing"
        if [ "$missing" -eq 1 ]; then
          soft_reconnect
        elif [ "$missing" -ge "$HARD_RECOVERY_AFTER_SAMPLES" ]; then
          hard_reconnect || true
        fi
      fi
    fi

    if [ "$state" != "$last_state" ]; then
      log "state=$state"
      last_state=$state
    fi
    sleep "$CHECK_INTERVAL_SEC"
  done
}

main "$@"
