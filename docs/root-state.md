# Root and framework state

`root/collect-root-state.sh` is a read-only audit. Run it from a root shell and store its output outside Git.

`root/export-framework-policy.sh <output-directory>` creates private TSV snapshots of the current Magisk settings/module flags and LSPosed/Vector module/scope tables. It uses mode `0700/0600`; copy the output to an ignored local backup, not into Git.

The reusable configuration boundary is:

- Magisk settings and module enable/disable state;
- module versions and their declared configuration files;
- LSPosed/Vector module enablement and package scopes;
- explicit local policy for apps that should never receive root access.

Do not publish or blindly restore `magisk.db`, framework databases, app-private data, device attestation material, or package-specific policy lists. Database schemas and UIDs change across installations. Reapply policy declaratively, confirm that every scoped package exists, and validate ordinary app functionality after each change.

This repository records compatibility state; it does not promise any third-party integrity or attestation verdict.
