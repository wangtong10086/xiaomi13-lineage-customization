#!/system/bin/sh

LOG=/data/local/tmp/xiaomi-tsm-omapi-policy.log
RULE='allow priv_app secure_element_service service_manager find'

{
  echo "=== $(date '+%F %T') ==="
  if magiskpolicy --live "$RULE"; then
    echo 'OMAPI service lookup rule applied'
  else
    echo 'OMAPI service lookup rule failed'
  fi
} >> "$LOG" 2>&1
