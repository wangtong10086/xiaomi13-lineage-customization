#!/system/bin/sh

PATH=/system/bin:/system/xbin:/vendor/bin:/product/bin:/apex/com.android.runtime/bin:/sbin

MODDIR=${0%/*}
STATE_DIR=/data/adb/xmsf-systemizer
LOG="$STATE_DIR/policy.log"
COMMAND_TIMEOUT_SEC=10
TARGET_PACKAGES="com.ss.android.lark"
[ -r "$MODDIR/config.conf" ] && . "$MODDIR/config.conf"

run_quiet() {
  timeout "$COMMAND_TIMEOUT_SEC" "$@" >/dev/null 2>&1
}

package_installed() {
  run_quiet cmd package path "$1"
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

wait_for_boot() {
  waited=0
  while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$waited" -lt 300 ]; do
    sleep 5
    waited=$((waited + 5))
  done
  log "boot_completed=$(getprop sys.boot_completed) waited=${waited}s"
}

apply_background_policy() {
  pkg=$1
  package_installed "$pkg" || {
    log "package=$pkg status=missing"
    return 0
  }

  run_quiet pm unsuspend "$pkg"
  run_quiet am set-standby-bucket "$pkg" active
  for op in POST_NOTIFICATION RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND WAKE_LOCK START_FOREGROUND; do
    run_quiet cmd appops set --user 0 "$pkg" "$op" allow
  done
  run_quiet pm grant "$pkg" android.permission.POST_NOTIFICATIONS
  log "package=$pkg status=policy-checked"
}

main() {
  umask 077
  mkdir -p "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  wait_for_boot

  apply_background_policy com.xiaomi.xmsf
  run_quiet cmd deviceidle whitelist +com.xiaomi.xmsf

  for pkg in $TARGET_PACKAGES; do
    [ "$pkg" = com.xiaomi.xmsf ] || apply_background_policy "$pkg"
  done
}

main "$@"
