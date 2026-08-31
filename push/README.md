# XMSF and FCM push repair

This directory contains two separate, reversible transport fixes:

- `xmsf-systemizer` installs the official, hash-pinned MiPushFramework XMSF APK as a system priv-app. Its one-shot boot service keeps XMSF and a short explicit target list eligible for background delivery. The proprietary APK is supplied only at build time and is never committed.
- `fcm-connectivity-guard` replaces the earlier broad package scanner and ABX editor with bounded GMS connection observation and recovery. It never clears app data or edits `package-restrictions.xml`.

Build the modules into an ignored `work/` directory. The builders use sorted entries and fixed ZIP timestamps, so identical source files and APK input produce identical archives:

```powershell
./Build-XmsfSystemizer.ps1 -XmsfApk ./work/arm64-v8a_normal_xmsf_v0.6.1_release.apk -OutputZip ./work/xmsf-systemizer.zip
./Build-FcmConnectivityGuard.ps1 -OutputZip ./work/fcm-connectivity-guard.zip
```

Before installation, back up XMSF CE/DE data, the Vector module database, existing FCM scripts, and v2rayNG MMKV state outside this repository. When replacing an XMSF APK signed by a different certificate, keep the backup but perform a clean XMSF install and allow applications to register normally; do not inject the old registration database.

The MiPush Xposed module must use only its APK-declared default scopes plus reviewed target apps that need registration camouflage. Do not restore or copy the complete Vector database between systems.

`Register-XmsfTarget.ps1` provides the general bounded audit. `Repair-XmsfAppRegistration.ps1` provides the exact-version compatibility workflow: it is read-only unless `-Apply` is supplied, accepts exactly one package per invocation, removes every exact target-package denylist entry only for the process lifetime, and restores compatibility scope, denylist, markers, and stopped state in `finally`. It never prints credentials or registration IDs and never writes XMSF tables directly:

```powershell
./Register-XmsfTarget.ps1 -Serial '<adb-serial>' -Package 'com.eg.android.AlipayGphone' -AdbPath '<path-to-adb>'
./Register-XmsfTarget.ps1 -Serial '<adb-serial>' -Package 'com.eg.android.AlipayGphone' -AdbPath '<path-to-adb>' -Apply
./Repair-XmsfAppRegistration.ps1 -Serial '<adb-serial>' -Package 'com.eg.android.AlipayGphone' -Action Verify -AdbPath '<path-to-adb>'
./Repair-XmsfAppRegistration.ps1 -Serial '<adb-serial>' -Package 'com.anjuke.android.app' -Action Register -AdbPath '<path-to-adb>' -Apply
```

Success requires all three registration facts: a non-empty app regId, a new XMSF event with `type=21/result=0`, and `REGISTERED_APPLICATION.registered_type=1`. A `type=2` event alone is only a dispatched attempt. See the Android 16 compatibility matrix in the `xiaomi13-lsposed-compat` repository before expanding scope or adding an app-specific hook.

`Register-XmsfViaVector.ps1` is a diagnostic reproducer for Vector 0.6.1's dynamic third-party dispatch limitation, not the preferred repair path. A Vector module-load line does not prove that `FakeDevice` or force-register hooks ran. If an application does not expose its own SDK and credential source, fail closed; never insert XMSF rows or borrow another package's SDK/credentials.

Some applications also require a vendor token to be bound to their own server after XMSF registration. Feishu 7.75.15 is one observed case: a non-empty XMSF registration ID was present, but the external MiPush module did not execute Feishu's `registerSenderSuccessAndUploadToken(...)` callback because its legacy ByteDance network hook no longer attached. Use the separately reviewed `lark-mipush-token-bridge` module from the `xiaomi13-lsposed-compat` repository for this exact version boundary. Scope it only to `com.ss.android.lark`; do not generalize the callback to other applications.

Edit `xmsf-systemizer/config.conf` before building when the target list differs. Do not use a broad package scan: every entry receives an active standby bucket and background app-ops at boot, so the list has both privacy and battery implications. XMSF itself is also added to the device-idle allowlist; target applications are not.

The FCM guard checks every 15 seconds while Android is awake, first requests a soft reconnect, and rate-limits a persistent-process restart to once per 30 minutes. It intentionally does not hold a wakelock. Logs contain only connection state and recovery results.

An established `mtalk` socket proves transport health, not that an application will display every message. For Gmail, distinguish these cases without reading message content:

1. confirm a successful `gmail-ls` sync after the test send;
2. confirm the numbered marker is present in the inbox;
3. inspect both Android notification channels and Gmail's per-account **Email notifications** policy.

If the message is present but no notification was posted, changing Gmail from **High priority only** to **All** is a notification-policy choice, not an FCM repair. Record that user-visible choice separately. Do not clear Gmail or Play services data to troubleshoot it.

Likewise, XMSF registration is not proven by a running process alone. Require a non-empty target-app registration, any required application-server token-binding callback, an established XMSF 5222 socket, and a numbered test delivered while the target process is absent and its package is not force-stopped. Relaunching the target application invalidates that delivery trial because it can fetch through its own foreground channel.

Use `collect-push-state.sh` as root after every boot. Keep raw logs, XMSF databases, APKs, v2rayNG configuration, push payloads, account identifiers, and tokens private.

## WeChat native FCM and Thanox delegate

`Audit-WeChatPush.ps1` performs a redacted, read-only audit of the verified WeChat 8.0.77 Xiaomi-market build or 8.0.72 Google Play build, GMS transport, and Thanox policy. It reports only registration presence, component and permission state, process lifecycle, socket count, and handling-layer booleans. It never prints FCM tokens, notification text, contacts, senders, conversations, or message bodies.

`Repair-WeChatPush.ps1` is version-locked to the reviewed WeChat builds (`versionCode=3160` or Play `versionCode=3085`) and Thanox `versionCode=3354368`. Without `-Apply` it only prints the proposed changes and runs the audit. With `-Apply` it:

1. verifies the locked app versions and creates a root-only, mode-`0600` phone-local archive of the FCM and Thanox private configuration plus bounded rule/start-record state;
2. optionally, with `-BackupTarget WindowsDpapi`, also pulls all installed APK splits and certificate digests and protects the private archive with Windows DPAPI CurrentUser;
3. updates live Thanox state through its v8.6 Binder API;
4. verifies postconditions and confirms the Wallet/Integrity/keybox static configuration digest did not change;
5. restores the exact pre-change Thanox state automatically if a postcondition fails.

Build the ignored Binder helper with local JDK and Android build tools, then audit or apply one handling layer:

```powershell
./Build-ThanoxWechatPushCli.ps1 -JavaPath '<java.exe>' -JavacPath '<javac.exe>' -JarPath '<jar.exe>' -D8JarPath '<d8.jar>' -AndroidJarPath '<android.jar>'
./Audit-WeChatPush.ps1 -Serial '<adb-serial>' -AdbPath '<adb.exe>'
./Repair-WeChatPush.ps1 -Mode NativeFcm -Serial '<adb-serial>' -AdbPath '<adb.exe>'
./Repair-WeChatPush.ps1 -Mode NativeFcm -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Repair-WeChatPush.ps1 -Mode NativeFcmGuarded -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Repair-WeChatPush.ps1 -Mode NativeFcm -BackupTarget WindowsDpapi -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Repair-WeChatPush.ps1 -Mode ThanoxDelegate -EnableBackgroundRestriction -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
```

For bottom-up delivery evidence, build and install the separate metadata-only Thanox Profile helper:

```powershell
./Build-ThanoxWechatFcmTelemetryCli.ps1 -JavaPath '<java.exe>' -JavacPath '<javac.exe>' -JarPath '<jar.exe>' -D8JarPath '<d8.jar>' -AndroidJarPath '<android.jar>'
./Install-ThanoxWechatFcmTelemetry.ps1 -Serial '<adb-serial>' -AdbPath '<adb.exe>'
./Install-ThanoxWechatFcmTelemetry.ps1 -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Install-ThanoxWechatFcmTelemetry.ps1 -EnableReclamation -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Install-ThanoxWechatFcmTelemetry.ps1 -EnablePostUseReclamation -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Install-ThanoxWechatFcmTelemetry.ps1 -UpgradeReclaimers -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
./Install-WeChatProcessReclaimer.ps1 -Serial '<adb-serial>' -AdbPath '<adb.exe>'
./Install-WeChatProcessReclaimer.ps1 -Serial '<adb-serial>' -AdbPath '<adb.exe>' -Apply
```

The installer is locked to Thanox 8.6, backs up the Thanox Profile database on the phone, and adds the rule through the reviewed Binder interface instead of editing SQLite. The rule matches only `fcmPushMessageArrived` for `com.tencent.mm` and appends only receive epoch plus the fixed package name. It does not record payload, token, sender, conversation, or notification contents.

`-EnableReclamation` is a conditional final stage, not a default. Use it only after an isolated native trial proves that WeChat remains running without the notification being opened. It adds a second exact-package rule with a 30-second grace period. The rule first checks that WeChat is not foreground and has no audio focus, then records only a fixed `am_kill_ok`, `am_kill_failed`, or `skipped_active` outcome. This is not a package force-stop; the acceptance check must still verify `stopped=false`. Remove or re-review this rule if Thanox's v8.6 Profile engine changes.

`-EnablePostUseReclamation` adds an independent foreground-switch rule for the case where the user opens WeChat or taps a notification and later leaves the app. It uses Thanox's documented `frontPkgChanged && from == "com.tencent.mm"` fact, waits 30 seconds, and applies the same foreground/audio guard before emitting the same bounded request outcome. Long external flows launched from WeChat receive the same 30-second grace period; remove this rule if that tradeoff is unacceptable.

`-UpgradeReclaimers` transactionally replaces older rules that used `ActivityManager.killBackgroundProcesses`. Live testing found that API can return without changing PIDs while WeChat is still in a service process state. Thanox's ordinary shell and Shell-SU handlers also failed to remove the tested service-state PIDs, so their success/failure outcome is treated as a request signal rather than final lifecycle proof. The upgrade preserves both rule names, validates both replacement rules before success, and reconstructs the legacy rules automatically if replacement fails.

`Install-WeChatProcessReclaimer.ps1` supplies the reviewed root-side executor for the current Play build. It is read-only by default and version-locked to WeChat `3085` plus Thanox `3354368`. With `-Apply` it creates a root-only phone-local backup of `service.d`, installs one exact script, verifies its hash and single worker PID, and confirms the protected Wallet/Integrity/keybox digest is unchanged. The worker consumes only new, fixed-format `epoch_ms/package/outcome` request lines, initializes cursors without replaying history, rechecks that WeChat did not race back to the foreground, runs only `am kill com.tencent.mm`, and logs only event time, request time, source, and bounded outcome. `Audit-WeChatPush.ps1` reports its hash, single-instance health, and last fixed outcome. A successful terminal result is `LastOutcome=zero` with WeChat `ProcessCount=0` and `Stopped=false`.

The basic native mode disables the Thanox proxy, removes WeChat start blocking and the extra background restriction, and enables per-app and global smart standby. `NativeFcmGuarded` is the device-validated no-residency variant: it still disables the proxy and extra background restriction, but keeps package start blocking on and enables the reviewed stop-service/restart-block Smart Standby flags. On this Thanox/HyperOS build, live trials proved that system FCM delivery and user notification/activity launches remain eligible while later WeChat service restarts are rejected. If the global switch is off, the repair changes it only when the smart-standby package list contains exactly WeChat; otherwise it fails closed. The delegate mode is a fallback only. `ThanoxNotifyOnly` is retained only as a reproducible diagnostic mode: live testing showed that `start-app=false` plus package start blocking still allowed WeChat's Firebase receiver/service to run, so it does not provide a strict zero-process delivery path. No mode calls `force-stop`, `pm clear`, freezes the package, disables Firebase components, edits the WeChat database, or changes Wallet, Play Integrity, keybox, Magisk hiding, or NFC configuration.

Do not use Thanox **background cleanup** during an acceptance trial: it performs a real package force-stop and sets `stopped=true`. If this happens, open WeChat once, allow initial synchronization to settle, return to the launcher, and use ordinary `am kill com.tencent.mm`; repeat `am kill` only if `CoreService` immediately restarts the app, then verify both zero processes and `stopped=false`. If the package was already stopped before `-Apply`, the repair may safely update Thanox policy but reports `RequiresManualLaunch=true`; complete the same recovery before the next delivery trial.

Use `-EnableBackgroundRestriction` only for the second delegate stage after the unrestricted delegate leaves WeChat running beyond three minutes. It enables the policy after the delegate options are complete; it does not invoke background cleanup.

Before each real delivery trial, close WeChat, use only `am kill com.tencent.mm` if a process remains, and confirm `stopped=false`. Send numbered messages from another account. Do not treat helper output, a token, or an `mtalk` socket as delivery proof. Use `collect-wechat-push-events.sh` to emit privacy-safe transport, native callback, and process timestamps. Text, image, file, and group reminders are in scope; voice/video calls are not. Source may be pushed as a clearly identified staged candidate, but do not tag or describe it as release-validated until at least 12 no-duplicate trials pass and the final configuration has run for 24 hours without a miss.
