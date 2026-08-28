#!/system/bin/sh
set -eu

SRC=/data/adb/xiaomi-mipay-fix/base-original.apk
EXPECTED=2215d6e1c52d8376efb7f12dba59d3a7f96386f3607270d4410f2759c6536fc5
LOG=/data/local/tmp/mipay-boot-original.log

{
  echo "=== $(date '+%F %T') ==="
  [ -f "$SRC" ] || { echo "missing $SRC"; exit 0; }
  actual=$(sha256sum "$SRC" | awk '{print $1}')
  [ "$actual" = "$EXPECTED" ] || { echo "official APK hash mismatch: $actual"; exit 0; }
  found=0
  for apk in /data/app/*/com.mipay.wallet-*/base.apk; do
    [ -f "$apk" ] || continue
    found=1
    cp -f "$SRC" "$apk"
    chown system:system "$apk"
    chmod 0644 "$apk"
    restorecon "$apk" 2>/dev/null || true
    echo "restored official apk: $apk"
    sha256sum "$apk"
  done
  [ "$found" = 1 ] || echo 'package path unavailable; reinstall the official APK through PackageManager'
} >> "$LOG" 2>&1
