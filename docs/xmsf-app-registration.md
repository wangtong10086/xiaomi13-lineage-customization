# Per-app XMSF registration repair

`push/Repair-XmsfAppRegistration.ps1` separates four states that must not be conflated:

1. an application dispatched a registration attempt;
2. XMSF returned a successful registration result;
3. the application persisted a non-empty RegID and ran its own token-binding callback;
4. a real message arrived while the application process was absent and `stopped=false`.

The script has a fixed seven-package, exact-version allowlist. `Audit` and `Verify` are read-only. `Register` and `Reregister` require `-Apply`, a single explicit serial, root, the signed compatibility module, and an external backup directory.

For every reviewed profile the workflow:

- backs up the XMSF database, target MiPush preferences when present, component overrides, compatibility scope, and every exact target-package Magisk denylist entry;
- temporarily removes those denylist entries and adds only the selected package to compatibility scope;
- requests the app-owned SDK action without logging credentials, RegID, or payloads;
- removes the marker and temporary app scope, restores the denylist, and clears the stopped bit in `finally`.

The Alipay profile additionally enables only `XiaoMiMsgReceiver`, `PushMessageHandler`, and `MessageHandleService` and requires its native token-binding callback. The Anjuke profile uses credentials that already exist in Anjuke's private preferences. The Douyin profile may read the matching public compatibility profile from the separately installed Vector 0.6.1 APK through a validated root-created symlink; the value is never printed or stored in this repository.

Current reviewed results on Android 16 are:

| Package | Result |
| --- | --- |
| Alipay 212210 | registered; later XMSF-to-app downlink verified |
| Anjuke 322403 | registered; delivery test pending |
| Douyin 400201 | not registered; installed/runtime SDK absent |
| 12306 280 | not registered; app-owned credential unavailable |
| Liepin 13081 | not registered; SDK unavailable |
| Tax 20303 | not registered; app-owned credential unavailable |
| CCB 2351 | not registered; app-owned credential unavailable |

`push/Register-XmsfViaVector.ps1` preserves the earlier direct-Vector experiment as a diagnostic reproducer. Vector 0.6.1 can be loaded into a dynamically scoped third-party process without dispatching its app hooks because its current-process resolver covers fixed system targets and the package callback may already have passed. Do not treat a module-load line as registration.

The XMSF database backup is evidence and emergency recovery material, not a routine restore mechanism. Do not edit or replay registration/event rows, transplant another application's SDK, or reuse another package's credentials. A force-stopped application cannot receive pushes; use `am kill`, confirm `stopped=false`, and send a numbered real business message for delivery acceptance.
