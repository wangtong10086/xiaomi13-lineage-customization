#!/system/bin/sh

# Emits only timestamps, fixed event labels, and the active handling layer.
# Raw log messages, notification text, sender/conversation names, tokens, and
# registration IDs are never printed.

THANOX_DATA=$(find /data/system -maxdepth 6 -type f -name thanos.xml 2>/dev/null | head -n 1)
if [ -n "$THANOX_DATA" ] && grep -q 'channel_enabled_com.tencent.mm" value="true"' "$THANOX_DATA"; then
  ACTIVE_LAYER=thanox_delegate
elif [ -n "$THANOX_DATA" ] && grep -q '<string>com.tencent.mm</string>' "${THANOX_DATA%/*}/start_blocking_pkgs.xml" 2>/dev/null; then
  ACTIVE_LAYER=native_fcm_guarded
else
  ACTIVE_LAYER=native_fcm
fi

echo "collection_epoch=$(date +%s) active_handler=$ACTIVE_LAYER"

PROFILE_IO=$(find /data/system -maxdepth 2 -type d -name profile_user_io 2>/dev/null | head -n 1)
if [ -n "$PROFILE_IO" ] && [ -f "$PROFILE_IO/wechat_fcm_transport.log" ]; then
  awk '/^epoch_ms=[0-9]+ package=com\.tencent\.mm$/ {
    print "event_epoch_ms=" substr($1, 10) " event=fcm_transport_arrived layer=thanox_profile"
  }' "$PROFILE_IO/wechat_fcm_transport.log"
fi

if [ -n "$PROFILE_IO" ] && [ -f "$PROFILE_IO/wechat_fcm_reclaim.log" ]; then
  awk '/^epoch_ms=[0-9]+ package=com\.tencent\.mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$/ {
    print "event_epoch_ms=" substr($1, 10) " event=fcm_process_reclaim " $3 " layer=thanox_profile"
  }' "$PROFILE_IO/wechat_fcm_reclaim.log"
fi

if [ -n "$PROFILE_IO" ] && [ -f "$PROFILE_IO/wechat_post_use_reclaim.log" ]; then
  awk '/^epoch_ms=[0-9]+ package=com\.tencent\.mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$/ {
    print "event_epoch_ms=" substr($1, 10) " event=post_use_process_reclaim " $3 " layer=thanox_profile"
  }' "$PROFILE_IO/wechat_post_use_reclaim.log"
fi

ROOT_RECLAIMER_LOG=/data/adb/wechat-process-reclaimer/reclaim.log
if [ -f "$ROOT_RECLAIMER_LOG" ]; then
  awk '/^epoch_ms=[0-9]+ source=(fcm|post_use|smoke) request_epoch_ms=[0-9]+ outcome=(zero|remaining|command_failed|stopped_violation|skipped_race_foreground)$/ && length($1) == 22 && length($3) == 30 {
    print "event_epoch_ms=" substr($1, 10) " event=root_process_reclaim " $2 " " $3 " " $4 " layer=root_service_d"
  }' "$ROOT_RECLAIMER_LOG"
fi

# Vector/LSPosed lines are reduced to the module's fixed timestamp, event and
# outcome fields. Snapshot details and all unrelated raw log text are omitted.
grep -h 'WechatFcmTokenBridge:' /data/adb/lspd/log/*.log /data/adb/lspd/log/modules_*.log 2>/dev/null | awk '
  {
    epoch=""; event=""; outcome=""
    if (match($0, /epoch_ms=[0-9]+/)) epoch=substr($0, RSTART + 9, RLENGTH - 9)
    if (match($0, /event=[a-z0-9_]+/)) event=substr($0, RSTART + 6, RLENGTH - 6)
    if (match($0, /outcome=[a-z0-9_]+/)) outcome=substr($0, RSTART + 8, RLENGTH - 8)
    if (epoch != "" && outcome != "" &&
        (event == "guard" || event == "hooks" ||
         event == "scene216_result" || event == "fcm_message_callback")) {
      key=epoch "|" event "|" outcome
      if (!seen[key]++) print "event_epoch_ms=" epoch " event=" event " outcome=" outcome " layer=wechat_native"
    }
  }
'

logcat -d -v epoch 2>/dev/null | awk '
  function emit(event, layer) {
    stamp=$1
    if (stamp ~ /^[0-9]+\.[0-9]+$/) {
      key=stamp "|" event "|" layer
      if (!seen[key]++) print "event_epoch=" stamp " event=" event " layer=" layer
    }
  }
  /WCFirebaseMessagingService/ { emit("firebase_service", "native_fcm"); next }
  /FirebaseInstanceIdReceiver/ { emit("firebase_receiver", "native_fcm"); next }
  /PushDelegate|push.message.delegate/ && /com.tencent.mm|WeChat/ { emit("delegate_dispatch", "thanox_delegate"); next }
  /Start proc/ && /com.tencent.mm/ { emit("wechat_process_started", "android"); next }
  /Killing.*com.tencent.mm|Process com.tencent.mm.*died/ { emit("wechat_process_stopped", "android"); next }
  /NotificationService/ && /pkg=com.tencent.mm/ { emit("notification_posted", "native_fcm"); next }
  /NotificationService/ && /pkg=github.tornaco.android.thanos/ && /WeChat|com.tencent.mm/ { emit("notification_posted", "thanox_delegate"); next }
'
