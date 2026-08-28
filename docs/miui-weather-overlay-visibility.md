# MIUI Weather overlay visibility

## Symptom

`com.miui.weather2` opens slowly and then exits on the customized Android 16 ROM. Its process log contains:

```text
java.lang.NoClassDefFoundError: miui.os.Build
```

The package declares the optional `com.miui.system` shared library, while the required MIUI implementation files are supplied at runtime by the `MiuiCore` Magisk module.

## Root cause

Do not add MIUI Weather or its `:pushservice` process to the Magisk denylist on this build. The root-hiding stack gives denylisted processes an isolated mount namespace. That namespace cannot see the system-path overlays supplied by `MiuiCore`, so Weather loses `miui.os.Build` during `WeatherApplication.onCreate()`.

This is a mount-visibility conflict, not corrupt Weather data. Clearing application data, reinstalling the same APK, or changing location permissions does not repair it.

## Audited repair

The repair script is read-only unless `-Apply` is supplied. It is locked to the reviewed Weather `versionCode=13500601`, verifies root, the enabled `MiuiCore` module, and both required overlay files, then reports all matching denylist entries:

```powershell
.\root\Repair-MiuiWeatherOverlayVisibility.ps1 `
  -Serial '<adb-serial>' `
  -AdbPath '<path-to-adb.exe>'
```

Apply only after reviewing that output:

```powershell
.\root\Repair-MiuiWeatherOverlayVisibility.ps1 `
  -Serial '<adb-serial>' `
  -AdbPath '<path-to-adb.exe>' `
  -Apply
```

Before changing anything, the script stores every exact Weather denylist entry under ignored `work/weather-overlay/`. It removes only those entries, cold-starts Weather, checks that the process stays alive, and rejects MIUI framework class-loading crashes. A failed validation restores the original entries.

## Tradeoff and rollback

Weather remains outside root hiding so that it can see the MIUI framework overlay. It receives no root grant. Re-adding either of these entries rolls back the visibility fix and is expected to restore the crash while `MiuiCore` remains a Magisk overlay:

```text
com.miui.weather2|com.miui.weather2
com.miui.weather2|com.miui.weather2:pushservice
```

After a Weather, ROM, Magisk, or `MiuiCore` upgrade, run audit mode again. A version mismatch intentionally fails closed until the new combination is reviewed.
