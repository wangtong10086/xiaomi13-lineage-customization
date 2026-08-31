# Contributing

[简体中文](CONTRIBUTING.zh-CN.md)

Contributions should remain narrow, reversible, and reviewable on Xiaomi 13 (`fuxi`).

1. Open an issue for a new device, ROM, application version, or behavior change before broadening an exact-version guard.
2. Separate read-only audit logic from mutation. Mutation must require `-Apply` or an equally explicit action, name one target device, back up affected state, and fail closed on version/hash mismatch.
3. Never use `pm clear`, implicit `force-stop`, unbounded package disabling, or direct writes to an application's private database.
4. Do not commit APKs, ROM images, keyboxes, signing material, wallet/TSM data, account identifiers, FCM/XMSF registration IDs, contacts, message content, private databases, raw logs, serial numbers, or personal package inventories.
5. Use redacted fixtures and `.example` inputs. Document what was tested, the exact public build identifiers, rollback, and unrelated-feature checks.
6. Run the PowerShell parser, JSON validation, shell checks, and relevant deterministic-build tests before submitting a PR.

Changes under `wallet/`, `root/`, and `push/` deserve extra review because a small scope or lifecycle error can affect security or availability.
