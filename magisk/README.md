# Xiaomi TSM priv-app and OMAPI fix

`xiaomi-tsm-privapp-fix` systemizes the Xiaomi TSM client, grants its reviewed privileged permissions, and supplies the single observed SELinux service lookup needed for OMAPI on this Android 16 build.

Build with an external Xiaomi TSM APK:

```powershell
./Build-XiaomiTsmPrivappFix.ps1 -TsmApk ./work/MiuiTsmClient.apk -OutputZip ./work/xiaomi-tsm-privapp-fix-v2.zip
```

The APK is proprietary and intentionally absent from Git. The builder rejects an unexpected APK hash. Install the resulting archive only after backing up the current module and verify after reboot that SELinux remains enforcing and that no `secure_element_service` denial is emitted when opening Xiaomi cards.

The rule is deliberately limited to finding one service:

```text
allow priv_app secure_element_service:service_manager find
```

The rule is supplied both as `sepolicy.rule` and by an idempotent `post-fs-data.sh` call to `magiskpolicy --live`. The latter is required by the validated Magisk 30.7 fork, which enumerates module policy files but does not merge this newly added rule during boot. The post-fs script records success or failure in `/data/local/tmp/xiaomi-tsm-omapi-policy.log`.

This module does not grant general property-service writes and does not copy secure-element applets or keys.
