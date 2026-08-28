# XMSF and FCM push repair

This directory contains two separate, reversible fixes:

- `xmsf-systemizer` installs the official, hash-pinned MiPushFramework XMSF APK as a system priv-app. Its one-shot boot service keeps XMSF and a short explicit target list eligible for background delivery. The proprietary APK is supplied only at build time and is never committed.
- `fcm-connectivity-guard` replaces the earlier broad package scanner and ABX editor with bounded GMS connection observation and recovery. It never clears app data or edits `package-restrictions.xml`.

Build the modules into an ignored `work/` directory. The builders use sorted entries and fixed ZIP timestamps, so identical source files and APK input produce identical archives:

```powershell
./Build-XmsfSystemizer.ps1 -XmsfApk ./work/arm64-v8a_normal_xmsf_v0.6.1_release.apk -OutputZip ./work/xmsf-systemizer.zip
./Build-FcmConnectivityGuard.ps1 -OutputZip ./work/fcm-connectivity-guard.zip
```

Before installation, back up XMSF CE/DE data, the Vector module database, existing FCM scripts, and v2rayNG MMKV state outside this repository. When replacing an XMSF APK signed by a different certificate, keep the backup but perform a clean XMSF install and allow applications to register normally; do not inject the old registration database.

The MiPush Xposed module must use only its APK-declared default scopes plus reviewed target apps that need registration camouflage. Do not restore or copy the complete Vector database between systems.

Edit `xmsf-systemizer/config.conf` before building when the target list differs. Do not use a broad package scan: every entry receives an active standby bucket and background app-ops at boot, so the list has both privacy and battery implications. XMSF itself is also added to the device-idle allowlist; target applications are not.

The FCM guard checks every 15 seconds while Android is awake, first requests a soft reconnect, and rate-limits a persistent-process restart to once per 30 minutes. It intentionally does not hold a wakelock. Logs contain only connection state and recovery results.

An established `mtalk` socket proves transport health, not that an application will display every message. For Gmail, distinguish these cases without reading message content:

1. confirm a successful `gmail-ls` sync after the test send;
2. confirm the numbered marker is present in the inbox;
3. inspect both Android notification channels and Gmail's per-account **Email notifications** policy.

If the message is present but no notification was posted, changing Gmail from **High priority only** to **All** is a notification-policy choice, not an FCM repair. Record that user-visible choice separately. Do not clear Gmail or Play services data to troubleshoot it.

Likewise, XMSF registration is not proven by a running process alone. Require a non-empty target-app registration, an established XMSF 5222 socket, and a numbered test delivered while the target process is absent and its package is not force-stopped. Relaunching the target application invalidates that delivery trial because it can fetch through its own foreground channel.

Use `collect-push-state.sh` as root after every boot. Keep raw logs, XMSF databases, APKs, v2rayNG configuration, push payloads, account identifiers, and tokens private.
