#!/system/bin/sh
set -eu

PKG=com.mipay.wallet
PATCHED=/data/adb/xiaomi-mipay-fix/base-patched.apk
EXPECTED=93aa0342511d57a9f785a2585a29555a60b31634b9ed2d9b725fdcb36dbc497a
LOG=/data/local/tmp/mipay-runtime-patch.log

{
  echo "=== $(date '+%F %T') ==="
  i=0
  while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
  done
  sleep 5
  [ -f "$PATCHED" ] || { echo "missing $PATCHED"; exit 0; }
  patched_hash=$(sha256sum "$PATCHED" | awk '{print $1}')
  [ "$patched_hash" = "$EXPECTED" ] || { echo "patched APK hash mismatch: $patched_hash"; exit 0; }
  apk=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
  [ -f "$apk" ] || { echo 'package path unavailable'; exit 0; }
  current_hash=$(sha256sum "$apk" | awk '{print $1}')
  echo "apk=$apk current=$current_hash patched=$patched_hash"
  if [ "$current_hash" != "$patched_hash" ]; then
    am force-stop "$PKG" 2>/dev/null || true
    cp -f "$PATCHED" "$apk"
    chown system:system "$apk"
    chmod 0644 "$apk"
    restorecon "$apk" 2>/dev/null || true
    pm compile --reset "$PKG" >/dev/null 2>&1 || true
    echo 'runtime apk patched'
  else
    echo 'runtime apk already patched'
  fi
  pm grant "$PKG" android.permission.READ_SMS 2>/dev/null || true
  pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
  cmd appops set "$PKG" READ_SMS allow 2>/dev/null || true
  cmd package unstop --user 0 "$PKG" >/dev/null 2>&1 || true
} >> "$LOG" 2>&1
