# Xiaomi Wallet and NFC validation

For the validated Xiaomi 13 (`fuxi`) Android 16 build, treat these as independent layers:

- `com.mipay.wallet` supplies the visible Xiaomi Wallet launcher and finance UI.
- `com.miui.tsmclient` manages card UI, account authorization, and eSE operations.
- Android NFC and Secure Element services provide routing and OMAPI.
- Card applets and keys live in the device secure element and are not restored by copying application data.

The observed Android 16 denial was:

```text
priv_app -> secure_element_service:service_manager find
```

The accompanying Magisk module adds only that lookup. On the validated Magisk 30.7 fork it also reapplies the same idempotent rule from `post-fs-data.sh`, because the fork did not merge a newly installed module policy file into live policy. Do not add broad `property_socket` or property-service writes without a directly causal denial.

## Do not restore door-card private data

Copying `com.miui.tsmclient` or `com.mipay.wallet` private data can reproduce card names and artwork without provisioning the corresponding applet and key on the destination eSE. This creates a ghost card: it appears selectable, but a physical reader rejects it. Deleting it through the UI can fail with Xiaomi TSM error `1010022`:

```text
未找到应用密钥，请联系小米客服
```

That error is not proof of an NFC-radio failure. If CPLC access, OMAPI, and the Secure Element service are healthy, it means the local card record and destination eSE state do not match.

## Recover a destination with ghost cards

Keep the source phone and its working cards unchanged. The following operation intentionally discards only the destination TSM state, so take a private backup outside Git first and use an explicit serial for every command.

1. Try the Xiaomi Wallet delete/migrate UI first.
2. If deletion returns `1010022`, stop Wallet and TSM, back up their destination CE/DE directories, and verify the backup hash.
3. Clear `com.miui.tsmclient` on the destination. Do not clear the source.
4. Remove the stale TSM-owned secure settings shown below. Preserve unrelated NFC preferences, Wallet shortcuts, and power-button settings.
5. Open the vendor-signed Xiaomi Wallet/TSM client and add or migrate each card through the supported UI. Do not restore the old TSM database afterward.

```powershell
$adb = 'adb'
$target = '<target-serial>'

& $adb -s $target shell pm clear com.miui.tsmclient

$keys = @(
    'TSM_CARD_ACTIVATE_RECORD',
    'issued_card_count',
    'keep_activated_card_aids',
    'key_bank_card_in_ese',
    'key_trans_card_in_ese'
)

foreach ($key in $keys) {
    & $adb -s $target shell settings delete secure $key
}
```

The successful recovery path on the validated device was: discard the invalid destination copy, add the door card again through Xiaomi Wallet, let TSM create the destination-specific eSE key, and pass a physical-reader test.

## Validation

After each change verify:

- SELinux remains Enforcing.
- `dumpsys nfc` reports `mState=on`.
- `dumpsys secure_element` reports `eSE1 mIsConnected:true`.
- Xiaomi TSM can read CPLC without an error.
- No new OMAPI denial, AVC, or fatal exception appears.
- `TSM_CARD_ACTIVATE_RECORD` is newly created by TSM rather than restored from the source.
- The selected card is physically accepted by its real reader.

An app screen, successful CPLC query, or healthy NFC service is not sufficient evidence by itself. Keep the source device/card unchanged until the destination passes the physical test.
