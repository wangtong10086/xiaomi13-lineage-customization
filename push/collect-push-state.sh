#!/system/bin/sh

echo "boot=$(getprop sys.boot_completed) device=$(getprop ro.product.device) android=$(getprop ro.build.version.release) selinux=$(getenforce)"

for pkg in com.xiaomi.xmsf io.github.magisk317.mipush com.ss.android.lark com.google.android.gms com.google.android.gm com.tencent.mm github.tornaco.android.thanos com.v2ray.ang; do
  if cmd package path "$pkg" >/dev/null 2>&1; then
    version=$(dumpsys package "$pkg" 2>/dev/null | sed -n 's/^[[:space:]]*versionName=//p' | head -n 1)
    user=$(dumpsys package "$pkg" 2>/dev/null | grep 'User 0:' | head -n 1)
    echo "$pkg version=$version $user"
  else
    echo "$pkg missing"
  fi
done

echo "wechat_fcm_redacted:"
appid=/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.appid.xml
messaging=/data/user/0/com.tencent.mm/shared_prefs/com.google.firebase.messaging.xml
[ -s "$appid" ] && echo "registration_file=present" || echo "registration_file=absent"
grep -q 'name="|T|' "$appid" 2>/dev/null && echo "registration_entry=present" || echo "registration_entry=absent"
if grep -Eq 'name="(auto_init|firebase_messaging_auto_init_enabled)"[^>]*(value="false"|>false<)' "$appid" "$messaging" 2>/dev/null; then
  echo "auto_init=explicit_false"
else
  echo "auto_init=enabled_or_default"
fi
dumpsys package com.tencent.mm 2>/dev/null | grep 'User 0:' | head -n 1
wechat_pids=$(pidof com.tencent.mm 2>/dev/null)
[ -n "$wechat_pids" ] && echo "process=running count=$(echo "$wechat_pids" | wc -w)" || echo "process=absent"
echo "standby_bucket=$(am get-standby-bucket com.tencent.mm 2>/dev/null | tr -d '\r\n')"

echo "wechat_transport:"
socket_count=$(ss -tnp 2>/dev/null | grep ':5228' | grep -c ESTAB)
echo "mtalk_established_count=$socket_count"
dumpsys deviceidle whitelist 2>/dev/null | grep -q 'com.google.android.gms' && echo "gms_idle_whitelist=present" || echo "gms_idle_whitelist=absent"

echo "wechat_thanox_policy:"
thanox_data=$(find /data/system -maxdepth 6 -type f -name thanos.xml 2>/dev/null | head -n 1)
if [ -n "$thanox_data" ]; then
  thanox_dir=$(dirname "$thanox_data")
  grep -q 'channel_enabled_com.tencent.mm" value="true"' "$thanox_data" && echo "handler=thanox_delegate" || echo "handler=native_fcm"
  grep -q '<string>com.tencent.mm</string>' "$thanox_dir/start_blocking_pkgs.xml" 2>/dev/null && echo "start_blocked=true" || echo "start_blocked=false"
  grep -q '<string>com.tencent.mm</string>' "$thanox_dir/bg_restrict_pkgs.xml" 2>/dev/null && echo "background_restricted=true" || echo "background_restricted=false"
  grep -q '<string>com.tencent.mm</string>' "$thanox_dir/smart_stand_by_pkgs.xml" 2>/dev/null && echo "smart_standby=true" || echo "smart_standby=false"
else
  echo "thanox_policy=unavailable"
fi

echo "xmsf_flags:"
dumpsys package com.xiaomi.xmsf 2>/dev/null | grep -E 'pkgFlags=|privateFlags=' | head -n 4

echo "mipush_vector:"
sqlite3 -header -column /data/adb/lspd/config/modules_config.db \
  "select m.mid,m.module_pkg_name,m.enabled,s.app_pkg_name,s.user_id from modules m left join scope s on s.mid=m.mid where m.module_pkg_name='io.github.magisk317.mipush' order by s.user_id,s.app_pkg_name;" 2>/dev/null || true

echo "lark_mipush_bridge_vector:"
sqlite3 -header -column /data/adb/lspd/config/modules_config.db \
  "select m.mid,m.module_pkg_name,m.enabled,s.app_pkg_name,s.user_id from modules m left join scope s on s.mid=m.mid where m.module_pkg_name='com.codex.larkmipushtokenbridge' order by s.user_id,s.app_pkg_name;" 2>/dev/null || true

echo "lark_xmsf_registration_and_recent_events:"
sqlite3 -header -column /data/user/0/com.xiaomi.xmsf/databases/db \
  "select pkg,blocked,registered_type,app_name from REGISTERED_APPLICATION where pkg='com.ss.android.lark'; select id,type,date,result,length(payload) as payload_bytes from EVENT where pkg='com.ss.android.lark' order by id desc limit 12;" 2>/dev/null || true

echo "reviewed_target_xmsf_registration:"
sqlite3 -header -column /data/user/0/com.xiaomi.xmsf/databases/db \
  "select pkg,blocked,registered_type from REGISTERED_APPLICATION where pkg in ('com.anjuke.android.app','com.lietou.mishu','com.ss.android.ugc.aweme','com.MobileTicket','cn.gov.tax.its','com.chinamworld.main','com.eg.android.AlipayGphone') order by pkg; select e.id,e.pkg,e.type,e.date,e.result from EVENT e join (select pkg,max(id) as id from EVENT where pkg in ('com.anjuke.android.app','com.lietou.mishu','com.ss.android.ugc.aweme','com.MobileTicket','cn.gov.tax.its','com.chinamworld.main','com.eg.android.AlipayGphone') group by pkg) latest on latest.id=e.id order by e.pkg;" 2>/dev/null || true

echo "xmsf_policy:"
tail -n 20 /data/adb/xmsf-systemizer/policy.log 2>/dev/null || echo not-run

echo "fcm_guard:"
if [ -r /data/adb/fcm-connectivity-guard/health.pid ]; then
  guard_pid=$(sed -n '1p' /data/adb/fcm-connectivity-guard/health.pid)
  [ -d "/proc/$guard_pid" ] && echo "running pid=$guard_pid" || echo "stale pid=$guard_pid"
else
  echo not-running
fi
tail -n 20 /data/adb/fcm-connectivity-guard/health.log 2>/dev/null || true

echo "legacy_fcm_scripts:"
for script in /data/adb/service.d/90-fcm-boot-fix.sh /data/adb/post-fs-data.d/10-fcm-clear-stopped-abx.sh; do
  [ -e "$script" ] && echo "$script=active" || echo "$script=absent"
done
