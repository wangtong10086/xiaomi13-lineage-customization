# MIUI Gallery overlay visibility

## Symptom and evidence

MIUI Gallery `com.miui.gallery` exits immediately while opening its home page. On the reviewed `versionCode=403690`, the fatal path is:

```text
FATAL EXCEPTION: preview-pool-0
java.lang.NoClassDefFoundError: miui.util.FeatureParser
at com.miui.gallery.domain.DeviceTools.hasConfig(...)
```

The same isolated launch can also miss MIUI Cloud runtime classes during application initialization.

## Root cause

Gallery declares `com.miui.rom`, `com.miui.system`, and `micloud-sdk`. On this customized ROM, their implementation files are supplied through the `MiuiCore` Magisk overlay, including:

```text
/system/framework/miui-framework.jar
/system/app/miuisystem/miuisystem.apk
/system/framework/micloud-sdk-miui-combined.jar
```

Putting any Gallery process in the Magisk denylist makes the root-hiding stack isolate its mount namespace. The app then loses required MIUI classes and crashes. This is not Gallery database or photo corruption; do not clear Gallery data as a repair.

## Audited repair

Audit mode is read-only and fails closed unless the installed Gallery version matches the reviewed build:

```powershell
.\root\Repair-MiuiGalleryOverlayVisibility.ps1 `
  -Serial '<adb-serial>' `
  -AdbPath '<path-to-adb.exe>'
```

Apply after reviewing the reported matching denylist entries:

```powershell
.\root\Repair-MiuiGalleryOverlayVisibility.ps1 `
  -Serial '<adb-serial>' `
  -AdbPath '<path-to-adb.exe>' `
  -Apply
```

The script verifies root, the enabled `MiuiCore` module, and all three runtime files. It backs up every exact `com.miui.gallery|...` entry under ignored `work/gallery-overlay/`, removes only those entries, cold-starts the home page, and verifies process survival with no fatal or MIUI class-loading error. Failed validation restores any removed entries.

Gallery stays outside root hiding but receives no root grant. Re-adding its main, editor, remote, customization, or widget-provider processes to the denylist is expected to restore the crash while these framework files remain Magisk overlays. Re-run audit mode after Gallery, ROM, Magisk, or `MiuiCore` upgrades.
