# Xiaomi Wallet runtime compatibility

The validated `com.mipay.wallet` build uses a two-stage compatibility chain:

1. `11-mipay-restore-original.sh` restores the official, vendor-signed APK before PackageManager scans `/data/app`.
2. `92-mipay-apply-runtime-fix.sh` waits for boot completion and replaces the APK with the Android 16 compatibility build used at runtime.

Validated APK identities for Wallet `6.110.0.5679.2731`:

| Role | APK SHA-256 | Signing certificate SHA-256 |
| --- | --- | --- |
| Official scan-time APK | `2215d6e1c52d8376efb7f12dba59d3a7f96386f3607270d4410f2759c6536fc5` | `c9009d01ebf9f5d0302bc71b2fe9aa9a47a432bba17308a3111b75d7b2149025` |
| Runtime compatibility APK | `93aa0342511d57a9f785a2585a29555a60b31634b9ed2d9b725fdcb36dbc497a` | `5e645e27fe93cc2c0e8fca507cce0b99479bd94cca89b54568c294fb77ef357d` |

The APKs are proprietary local inputs and are not committed. Place them under `/data/adb/xiaomi-mipay-fix/` with mode `0600` or stricter, then install the two scripts under Magisk's `post-fs-data.d` and `service.d` directories.

If PackageManager has already removed the `/data/app/.../com.mipay.wallet-...` directory, neither script can safely recreate its package registration. Reinstall the official APK with `adb install --no-streaming -r`, verify that CE/DE data inodes are unchanged, and then run the service script or reboot. Never install the runtime-patched APK through PackageManager because its signing certificate intentionally differs.
