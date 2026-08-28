#!/system/bin/sh

ui_print "- Installing hash-pinned XMSF system app"

APK="$MODPATH/system/priv-app/Xmsf/Xmsf.apk"
PERMS="$MODPATH/system/etc/permissions/privapp-permissions-com.xiaomi.xmsf.xml"

[ -f "$APK" ] || abort "Missing XMSF APK"
[ -f "$PERMS" ] || abort "Missing XMSF privileged-permission allowlist"

set_perm_recursive "$MODPATH/system/priv-app/Xmsf" 0 0 0755 0644
set_perm "$PERMS" 0 0 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/config.conf" 0 0 0644
