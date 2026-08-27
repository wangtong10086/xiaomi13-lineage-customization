#!/system/bin/sh

echo "boot=$(getprop sys.boot_completed) android=$(getprop ro.build.version.release) selinux=$(getenforce)"
echo "magisk=$(magisk -V 2>/dev/null || echo unavailable)"

module_count=$(find /data/adb/modules -mindepth 1 -maxdepth 1 -type d | wc -l)
disabled_count=$(find /data/adb/modules -mindepth 2 -maxdepth 2 -name disable -type f | wc -l)
echo "modules=$module_count disabled=$disabled_count"
echo "disabled_modules:"
for marker in /data/adb/modules/*/disable; do
  [ -f "$marker" ] && basename "$(dirname "$marker")"
done | sort

echo "magisk_settings:"
sqlite3 /data/adb/magisk.db "select key||'='||value from settings where key in ('zygisk','denylist','su_biometric') order by key;" 2>/dev/null || true

echo "vector_db:"
sqlite3 /data/adb/lspd/config/modules_config.db "select 'integrity='||(select integrity_check from pragma_integrity_check); select 'enabled='||count(*) from modules where enabled=1; select 'scope_rows='||count(*) from scope; select module_pkg_name from modules where enabled=1 order by module_pkg_name;" 2>/dev/null || true

echo "processes:"
for pattern in TrickyStore vectord tailscaled sshd com.miui.home; do
  if ps -A -o PID,NAME,ARGS 2>/dev/null | grep -F "$pattern" | grep -v grep >/dev/null; then
    echo "$pattern=running"
  else
    echo "$pattern=not-running"
  fi
done

echo "home_role:"
cmd role get-role-holders --user 0 android.app.role.HOME 2>/dev/null || true

echo "ssh_port22:"
ss -lnt 2>/dev/null | grep -E '[:.]22[[:space:]]' | sed -n '1p' || echo not-listening

echo "startup_logs:"
for log in \
  /data/local/tmp/fcm-clear-stopped-abx.log \
  /data/local/tmp/fcm-boot-fix.log \
  /data/local/tmp/esepower-fix.log \
  /data/local/tmp/xiaomi-wallet-min-perms.log \
  /data/local/tmp/xiaomi-account-enable-login.log \
  /data/local/tmp/xiaomi-tsm-auth-ph-cache.log \
  /data/local/tmp/termux-ssh-login.log \
  /data/local/tmp/termux-services.log; do
  if [ -f "$log" ]; then
    echo "$(basename "$log")=present,size=$(wc -c < "$log")"
  else
    echo "$(basename "$log")=missing"
  fi
done

echo "recent_crashes=$(logcat -b crash -d 2>/dev/null | wc -l)"
