# Android settings and IME state

`export-android-settings.sh` captures the three Android settings namespaces plus enabled/default input-method state. Its output can contain account-related or device-specific values, so keep it under ignored `work/` storage.

Do not replay a full `settings list` dump. Build a small TSV allowlist containing only reviewed keys:

```text
namespace  key  value
secure     example_key  example_value
```

Apply it to one explicit, authorized adb device:

```powershell
./Apply-AndroidSettings.ps1 -Serial '<explicit-serial>' -SettingsTsv ./work/settings-reviewed.tsv
```

The host script captures every existing value before writing and emits a rollback TSV. Empty values are represented with the sentinel `__DELETE__`; use that value in an input row to delete a setting.

Settings keys and permissions change across Android versions. Apply small groups, reboot, and validate IME selection, launcher behavior, lock screen, passkeys, and accessibility before continuing.
