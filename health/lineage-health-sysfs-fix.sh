#!/system/bin/sh

# The kernel can recreate/reset this sysfs node after post-fs-data. Keep a
# short-lived background guard through the complete Android boot window so the
# LineageOS health service always sees the source-equivalent permissions.
(
    path=/sys/class/qcom-battery/input_suspend
    i=0
    while [ "$i" -lt 180 ]; do
        if [ -e "$path" ]; then
            chown 1000:1000 "$path" 2>/dev/null
            chmod 0660 "$path" 2>/dev/null
        fi
        i=$((i + 1))
        sleep 1
    done
) </dev/null >/dev/null 2>&1 &
