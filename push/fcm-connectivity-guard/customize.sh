#!/system/bin/sh

ui_print "- Installing bounded FCM connectivity guard"
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/config.conf" 0 0 0644
