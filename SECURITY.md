# Security policy / 安全政策

## Reporting / 报告方式

Use GitHub private vulnerability reporting for unsafe device mutation, privilege-boundary issues, unintended package scope, or accidental sensitive-data exposure. Do not open a public issue with a working exploit or private artifact.

如发现不安全设备写入、权限边界问题、错误包作用域或敏感数据暴露，请使用 GitHub 私密漏洞报告。不要在公开 Issue 中附上可用利用方式或私有工件。

Provide the affected commit, public device/ROM/app version, minimal reproduction, impact, and sanitized diagnostics. Never send keyboxes, private/signing keys, credentials, wallet data, FCM/XMSF tokens or registration IDs, message content, contacts, serial numbers, or raw application databases.

请提供受影响提交、公开的设备/ROM/应用版本、最小复现、影响与脱敏诊断。切勿发送 keybox、私钥/签名密钥、凭据、钱包数据、FCM/XMSF token 或注册 ID、消息正文、联系人、序列号或原始应用数据库。

## Supported versions / 支持范围

Only the latest `main` revision is maintained. Individual scripts may intentionally support a narrower exact version; their own guards and documentation are authoritative.

仅维护最新 `main`。单个脚本可能有意只支持更窄的精确版本，其内置守卫与对应文档具有优先效力。
