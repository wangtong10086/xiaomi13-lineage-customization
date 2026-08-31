# WeChat push without a resident WeChat process

## Supported configuration

This runbook is intentionally locked to:

- Xiaomi 13 (`fuxi`) on the reviewed Android 16 build;
- WeChat 8.0.77 Xiaomi-market build (`versionCode=3160`) or the captured Google Play 8.0.72 split set (`versionCode=3085`);
- Thanox 8.6-prc (`versionCode=3354368`);
- an established Google Play services FCM transport and the bounded FCM connectivity guard.

The preferred handling layer is native FCM. Thanox delegation is a fallback only. Never enable two notification handlers intentionally, and never use `force-stop`, package freezing, Firebase component disabling, or `pm clear` as process-management tools. A real force-stop makes the package ineligible for background delivery until the user opens it again.

## Safe deployment order

1. Run `push/Audit-WeChatPush.ps1` and confirm a non-stopped package, granted notification permission, enabled Firebase receiver/service, a registration entry, `auto_init` enabled or default, an established `mtalk` socket, and GMS idle whitelist/guard health.
2. Run `push/Repair-WeChatPush.ps1 -Mode NativeFcmGuarded` without `-Apply` and review the proposed changes.
3. Build the ignored Thanox Binder helper and apply `NativeFcmGuarded`. Retain the root-only phone backup, or select `-BackupTarget WindowsDpapi` when an external APK/certificate archive is required; never copy either private archive into the repository.
4. Install the metadata-only transport, delayed delivery-reclaim, and post-use-reclaim Profile rules, then audit and apply `push/Install-WeChatProcessReclaimer.ps1`. This root worker is currently locked to WeChat `3085` and Thanox `3354368` and backs up `service.d` on the phone before writing.
5. Confirm Thanox delegation and the extra background restriction are off, start blocking and smart standby are on, the active layer is `NativeFcmGuarded`, and the root reclaimer has one running process with a matching local/device hash. Thanox background cleanup is not a valid reclamation test because it performs a real force-stop and sets `stopped=true`.
6. Close WeChat. If a process remains during preparation, use only `am kill com.tencent.mm`; confirm `stopped=false` afterward.
7. Send numbered real messages from a different account. A token, socket, process start, mock notification, or foreground refresh is not delivery proof.

Do not use the Play build migration path unless native FCM repeatedly misses while registration and the GMS transport remain healthy. The normal in-place path still requires a matching signer and a target version code no lower than the installed build. The reviewed root-only downgrade exception is described below; it requires a validated phone-local data archive, an immediate rollback APK, `pm uninstall -k`, and a root install session with the downgrade flag. Never use ordinary uninstall, `pm clear`, package-setting edits, or a third-party APK source.

## Acceptance matrix

Voice and video calls are out of scope. For every row, WeChat must be absent before the send and `stopped=false`. All three numbered messages must arrive without duplicates; notification click must enter the correct conversation. On an active network the target is 60 seconds. During Doze, allow up to five minutes. Three minutes after handling, all WeChat processes must be absent again.

| Trial | Network/state | Message IDs | Arrival | Duplicate | Correct conversation | Processes absent after 3 min |
|---|---|---|---|---|---|---|
| 1 | Wi-Fi, screen on | WF-01..03 | Pending | Pending | Pending | Pending |
| 2 | Mobile data, screen on | MD-01..03 | Pending | Pending | Pending | Pending |
| 3 | Screen off 15 min / Doze | DZ-01..03 | Pending | Pending | Pending | Pending |
| 4 | Wi-Fi/mobile switch | NS-01..03 | Pending | Pending | Pending | Pending |
| 5 | Reboot, WeChat not manually opened | RB-01..03 | Pending | Pending | Pending | Pending |

Rows 1-4 provide the minimum 12 messages. Row 5 separately validates boot behavior. Record only message IDs, send/arrival timestamps, handling layer, duplicate count, click result, and process lifecycle. Do not record sender, conversation name, message body, FCM token, or registration ID.

## Staged test evidence (2026-08-31)

| Message ID | Sent | Handler/configuration | Preconditions | Result |
|---|---:|---|---|---|
| `THANOX-01` | 13:59 | Thanox delegate, no extra background restriction | Invalid: WeChat AlarmReceiver started three processes at 13:58:20 | Excluded from acceptance |
| `THANOX-02` | 14:05 | Thanox delegate with staged background restriction, Doze | Processes absent; `stopped=false`; mtalk established | No delegate/Firebase/process/notification event within five minutes or during 60 seconds after wake |
| `THANOX-03` | 14:13 | Same delegate configuration, screen awake | Processes absent; `stopped=false`; mtalk established | No delegate/Firebase/process/notification event within the active-network 60-second target |
| `PLAY-NATIVE-PRE` | 15:05 | Play 8.0.72, native FCM, smart standby | No message sent; lifecycle-only preflight after first launch | `am kill` was followed by `CoreService` and `MainProcessIPCService` starts; two processes remained after 180 seconds, so no native delivery trial was admitted |
| `PLAY-THANOX-01` | 15:12 | Play 8.0.72, Thanox delegate, no extra background restriction | Processes absent before send; `stopped=false` | Excluded: WeChat processes started 11 seconds after send, then manual Thanox background cleanup force-stopped the package at 15:12:39; no handler/notification event was proven |
| `PLAY-THANOX-02` | 15:22 | Play 8.0.72, Thanox delegate with staged background restriction | Processes absent and `stopped=false` for a 180-second preflight; mtalk established | No handler or notification event was proven; excluded after the registration-layer defect was isolated |
| `REBIND-FCM-01` | 16:07 | Repaired registration; Thanox delegate with staged background restriction | Processes absent; `stopped=false`; native scene 216 had succeeded | FCM transport arrived at 16:08:00.999 and Thanox started WeChat; no native message callback, as expected under delegation; WeChat remained running after three minutes |
| `NATIVE-POSTBIND-01` | 16:13 | Repaired registration; native FCM; smart standby | Processes absent for 30 seconds; `stopped=false`; Thanox delegate and extra background restriction disabled | FCM arrived at 16:13:28.483; WeChat native callback entered at 16:13:28.958 and completed 11 ms later; exactly one notification opened the correct conversation; post-click reclamation tracked separately |
| `NATIVE-RECLAIM-01` | 16:30 | Repaired native FCM plus guarded non-stopping reclaimer | Processes absent; `stopped=false`; notification not opened during the first grace period | Native callback completed; first 150-second reclaim removed all processes with `stopped=false`; a second FCM transport then arrived for the single sent message but did not duplicate the notification, and its own delayed reclaim again reached zero processes after the notification was opened and the app left foreground |
| `THANOX-NOSTART-01` | 16:51 | Delegate enabled, start-on-push disabled, start blocking initially disabled | Processes absent; `stopped=false` | FCM still started the native Firebase receiver and callback. After start blocking was enabled, tapping this already-created notification launched `ChattingUI` but WeChat bounced back to `LauncherUI`; the user observed only the generic WeChat screen. Mixed configuration, excluded from acceptance |
| `THANOX-BLOCKED-01` | 17:08 | Diagnostic notify-only mode: delegate enabled, start-on-push disabled, start blocking enabled | Processes absent; `stopped=false` | FCM arrived at 17:08:07.859 and still started the native callback at 17:08:08.364. Only one WeChat notification and no Thanox proxy notification existed. The 150-second reclaimer reached zero processes with `stopped=false` at 17:10:37.872; a subsequent cold click entered the correct conversation |
| `NATIVE-GUARDED-01` | 17:21 | Native FCM, delegate disabled, start blocking and guarded reclaimers enabled | Processes absent for 30 seconds; `stopped=false` | FCM arrived at 17:21:52.672; native callback completed at 17:21:53.367; exactly one WeChat notification and no Thanox proxy notification. Delivery reclaim ran at 17:24:22.695 and reached zero processes with `stopped=false`; the user confirmed that the cold click entered the correct conversation. After returning home Smart Standby reached zero before the post-use guard at 17:28:01.827. A silent callback after GMS reconnect at 17:29:08 posted no notification, but exposed that the Profile-only kill path did not reliably remove service-state PIDs; the root executor described below now closes that gap. |

The early delegated failures showed no FCM downlink reaching either notification handler; they did not show a notification-rendering or process-reclamation failure. The tested build reported `installer=com.xiaomi.market`, which motivated the bounded Play-build experiment below. Later rows supersede that transport diagnosis after registration repair.

The read-only Google Play preflight exposed only **Open** and **Uninstall**, with Play listing version `8.0.72`; the installed Xiaomi-market build was `8.0.77` (`versionCode=3160`). A root-only feasibility APK proved that this device accepts a same-signer downgrade when the install session is owned by root.

Before touching WeChat, CE, DE, external app data, and the legacy `tencent/MicroMsg` directory were archived on the phone to the root-only `/data/adb/wechat-backups` directory. The 13,454,991,987-byte zstd archive passed `zstd -t`, a complete tar listing, and SHA-256 verification. The current 8.0.77 APK was copied and hash-checked in the same directory and staged separately for immediate rollback. The phone-local archive relies on the device's file-based encryption and root-only mode `0600`; it must not be copied into Git.

`pm uninstall -k --versionCode 3160 com.tencent.mm` then removed only the installed code. CE inode `219514`, DE inode `219517`, external-data inode `718014`, and UID `10190` remained unchanged, while the retained package record continued to report version code 3160. Google Play downloaded its official split set but Android rejected the Play-owned downgrade, as expected. A bounded root watcher retained the completed installer-session files before cleanup.

The captured base reported `com.tencent.mm`, version `8.0.72`, version code `3085`, target SDK 35. The base and all four configuration splits passed `apksigner` verification with the same Tencent signer SHA-256 as 8.0.77. Root then installed the explicit five-file set with `pm install -r -d -i com.android.vending`; package installation succeeded, the installer became Google Play, all installed APK hashes matched the captured files, all data inodes and UID remained unchanged, and `stopped=false`. A cold launch reached `com.tencent.mm/.ui.LauncherUI` without a main-process fatal exception, demonstrating that the retained account data could be opened. This is a device-specific, root-only recovery path rather than an Android-supported downgrade guarantee; keep the 8.0.77 rollback APK and full phone-local archive until push acceptance and user-visible account checks are complete.

The first post-migration native lifecycle preflight failed the no-resident requirement before any message was sent: after `am kill`, Android event logs showed WeChat restarting `CoreService` and then `MainProcessIPCService`, with both processes still present after three minutes. The active candidate was therefore moved to Thanox delegation without the extra background restriction. In that state a new `am kill` left zero WeChat processes at both five and 30 seconds with `stopped=false`.

`PLAY-THANOX-01` was invalidated by a manual Thanox background cleanup after the observer noticed WeChat processes. Android exit history recorded `USER REQUESTED / FORCE STOP`, and the package changed to `stopped=true`. Recovery required opening WeChat once, allowing its first synchronization to settle, returning home, and using ordinary `am kill`; a second `am kill` left the package non-stopped with no processes. The staged Thanox background restriction was then enabled without invoking cleanup. The resulting candidate held `process_count=0` and `stopped=false` at baseline and every 30-second sample through 180 seconds. Its audit showed delegation/content/start-app/skip-if-running enabled, start blocking disabled, background restriction enabled, Firebase components and registration intact, and one established GMS `mtalk` socket.

## Bottom-up registration repair

The Play build initialized Firebase successfully and contained a current FCM token. WeChat's own stored `fcm_curr_reg_token` was also present and equal, Google Play services reported availability code `0`, and the account was logged in. Runtime tracing then showed repeated entry into WeChat's token-registration method without any native scene 216 dispatch. Static control-flow review identified the equal-token early return in that method; the existing token therefore prevented WeChat from refreshing its Tencent-side FCM binding after the retained-data Play downgrade.

The exact-version `wechat-fcm-token-bridge` module in the companion `xiaomi13-lsposed-compat` repository was scoped only to `com.tencent.mm/0` and guarded by version code `3085` plus the Tencent signing certificate. An expiring, random-nonce one-shot marker made the stored token appear empty only on the calling thread while invoking WeChat's original registration method with the current token. WeChat dispatched its own `/cgi-bin/micromsg-bin/androidfcmreg` scene 216 and returned `errType=0, errCode=0` at 16:06:30.996. The control marker was removed, and the registered-token age reset, without deleting the Firebase instance ID or writing WeChat storage directly.

The next delegated test produced a privacy-safe Thanox `fcmPushMessageArrived` event, proving that the repaired binding restored downlink transport. The isolated native test then produced both the same transport fact and a completed `WCFirebaseMessagingService` callback. This distinguishes three separate facts that earlier tests had conflated: an established GMS socket, Tencent registration, and actual application callback delivery.

The transport trace is implemented as one exact-package Thanox Profile rule through Thanox's reviewed v8.6 Binder API. It appends only `epoch_ms` and the fixed package name under Thanox's private profile I/O directory. It never stores the payload, notification contents, token, sender, conversation, or message text. The LSPosed trace similarly emits only fixed lifecycle labels, booleans, and key count.

Live Binder inspection initially showed why enabling only the package's Thanox smart-standby bit was insufficient: the installation had only the global "set inactive" behavior enabled, while stop-service and block-service-restart were disabled. A bounded WeChat-only experiment then enabled stop-service and block-service-restart, kept unbind-service disabled, and kept visible-app bypass enabled. After a real foreground-to-background transition, Smart Standby removed most subprocesses and eventually the remaining main/push pair, but it had previously left that pair alive for more than four minutes when no fresh transition occurred.

The first guarded candidate added a separate exact-package Profile rule after native delivery. Every WeChat FCM transport schedules a 150-second action. At execution time it acts only if WeChat is not foreground and has no audio focus, then writes a fixed outcome. The first implementation used Thanox's `killBackgroundProcesses("com.tencent.mm")`; it removed cached processes during the initial trial without setting `stopped`, and a second transport wake for one visible notification was also reclaimed. Later service-state PIDs demonstrated that this API was not deterministic, so those initial results are historical evidence rather than the final executor design.

A third exact-package Profile rule covers user-initiated use rather than delivery. Thanox documents `frontPkgChanged == true && from == "com.tencent.mm"` as the fact emitted when WeChat goes to the background. The rule waits 150 seconds and applies the same foreground/audio guard before writing its fixed request outcome. Its first controlled trial left WeChat at 17:04:02, recorded `attempted` at 17:06:32.189, and retained `stopped=false`; Smart Standby had already removed the processes shortly before the delayed guard ran. A later trial with package start blocking disabled showed why that control is also necessary: the rule ran at 17:16:05.849, but `CoreService` recreated the main and push processes.

The initial reclaimers called Thanox's `killBackgroundProcesses`, which succeeded for cached processes but was not deterministic for WeChat service-state processes. After the GMS reconnect callback, the FCM rule logged `attempted` at 17:31:37.608 while the same main and push PIDs remained. Controlled trials of Thanox's ordinary `sh.exe` and root-capable `su.exe` handlers likewise left the tested main, push, and app-brand PIDs alive; `su.exe` returned a fixed `am_kill_failed` outcome. The Profile rules therefore remain responsible for timing and the foreground/audio guard, but their `am_kill_ok` or `am_kill_failed` line is treated only as a bounded request signal.

The final executor is `/data/adb/service.d/96-wechat-process-reclaimer.sh`, installed by the version-locked, backup-first `push/Install-WeChatProcessReclaimer.ps1`. It tails only new fixed-format request lines from the delivery and post-use rules, never replays old entries, rechecks that WeChat did not race back to the foreground, and runs the fixed root command `am kill com.tencent.mm`. It then verifies both process count and `stopped` state and appends only event time, request time, source, and a bounded outcome. A live smoke request removed the existing service-state WeChat processes and produced zero processes with `stopped=false`; after correcting an Android-shell timestamp overflow, a second request recorded `epoch_ms=1788170203794`, `outcome=zero`. The installed/local SHA-256 is `311e06d7e8f1e424fc5aa015996ebc82568238db18a36f1909dc97785f3bcb35`, the protected Wallet/Integrity/keybox digest stayed unchanged, and the retained phone-local backup is `/data/adb/wechat-backups/wechat-process-reclaimer-20260831-175627.tar.gz` with SHA-256 `669ae001c231a0b5617b4dad3ba7c4bd8da9afce7d6f8a0ac0ce741e11f7ee86`.

At 18:10 the delivery and post-use Profile delays were both reduced from 150,000 ms to 30,000 ms at the user's request. The Binder update retained exactly three enabled rules and the same guards and action. Its phone-local rollback archive is `/data/adb/wechat-backups/thanox-wechat-fcm-telemetry-20260831-181013.tar.gz`, SHA-256 `eaefdd83951c92e1ef5b06c37f206e9c85337fa171103ac2ec044bfc2c338486`. The post-update smoke request reported both delays as `30000`, then the root worker recorded `epoch_ms=1788171035934 outcome=zero`; WeChat remained at zero processes with `stopped=false`.

The strict notification-only delegation experiment is not a viable final mode on this device. With delegation enabled, start-on-push disabled, and package start blocking enabled, a fresh FCM still launched WeChat's Firebase receiver and completed its native callback. The only active notification belonged to WeChat, not Thanox. Because arrival-time process creation could not be eliminated, retaining the delegate would add ambiguity without saving a wake. The final staged candidate therefore uses `NativeFcmGuarded`: Thanox delegation and extra background restriction are disabled, package start blocking remains enabled, both guarded 30-second request rules remain active, and the root worker performs the verified process kill. This permits the minimum process wake Android needs to run `FirebaseMessagingService` and allows user notification clicks, while rejecting later service restarts and preserving a correct cold notification deep link.

`NATIVE-GUARDED-01` validated that combination end to end. The GMS `mtalk` count was momentarily zero during the final audit at 17:28:42 while the connectivity guard and persistent GMS process remained healthy; it automatically returned to one established connection by 17:29:07. This transient reconnect did not change WeChat package state or start any WeChat process.

This is a staged candidate, not the release gate. It still needs the full 12-message network/state matrix and 24-hour no-miss/no-duplicate observation. Repeated transport wakes for one visible message must be counted separately from duplicate notifications so a wake/reclaim loop is not hidden.

References: [Firebase background message handling](https://firebase.google.com/docs/cloud-messaging/android/receive-messages), [Firebase Android client setup and token access](https://firebase.google.com/docs/cloud-messaging/android/get-started), and [Thanox Profile documentation](https://tornaco.github.io/Thanox-Docs/en/guide/profile).

## Thanox fallback

Enter fallback only after a numbered native trial produces a genuine miss that is not resolved by the repaired registration, or the guarded native lifecycle fails repeatedly:

- enable WeChat delegation, content display, skip-if-running, and start-on-push;
- keep WeChat out of start blocking;
- remove the extra background restriction for the first delegate trial;
- enable smart standby.

`Repair-WeChatPush.ps1 -Mode ThanoxDelegate -Apply` applies those settings in dependency order and enables the proxy channel last. If WeChat still remains resident after three minutes, use `-Mode ThanoxDelegate -EnableBackgroundRestriction -Apply` as a separate experiment. This enables the policy only after the delegate is complete; it never invokes Thanox background cleanup.

## Evidence and release gate

Use `push/collect-wechat-push-events.sh` for privacy-safe timestamps and inferred handling-layer events. Use `push/collect-push-state.sh` after boot. Raw logs and private backups stay outside Git.

The source may be committed as a staged candidate for review and reproducibility. Do not create a release tag or describe the configuration as validated until the minimum matrix passes and the selected configuration completes 24 hours without a missed or duplicate notification.
