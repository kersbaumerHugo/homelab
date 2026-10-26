# OPNsense encrypted configuration backup via API (HA01/Voice PE)

## Purpose and constraints

Before implementing a NAT writer, obtain an off-repo **recoverable backup** of
OPNsense configuration. This script uses HTTPS with certificate validation and
the service user's netrc credentials; it does not require SSH or disable TLS.
It never writes plaintext XML to disk (the API payload exists in process memory).

Backup endpoint: `GET /api/core/backup/download/this` (configuration history).
See https://docs.opnsense.org/development/api/core/core.html . Access requires
permission to read configuration history/backup, which may require separate ACL
privileges from firewall read-only permissions. Do not grant administrator-wide
privileges automatically; review the minimum grant in your installed OPNsense.

**Known compatibility issue:** some OPNsense releases have returned malformed
XML from this endpoint. The script fails closed if the XML cannot be parsed;
a successful HTTP response is not sufficient proof of a usable backup.

## Preflight (does not write a backup)

Run from dev01 (not from GitHub Actions):

```bash
make opnsense-backup-check
```

The script expects:

- `~/.config/homelab/opnsense/api.netrc` (mode 0600), machine `OPNsense.internal`;
- `~/.config/homelab/opnsense/opnsense.crt`, whose SHA-256 fingerprint was
  independently verified against the OPNsense administration interface;
- OPNsense at `192.168.10.1` with certificate SAN `DNS:OPNsense.internal`.

The command downloads XML into RAM only, verifies the expected root element,
and discards the body. It prints no credentials or XML contents.

## Generate encrypted snapshot

Install age from Debian's package repository if needed. Create an `age` identity
and store its **private** key securely, ideally off-host. Do not commit it or
send it in chat. Obtain its **public** recipient from the `age-keygen` output.

```bash
export AGE_RECIPIENT='age1...actual-public-key...'
make opnsense-backup
unset AGE_RECIPIENT
```

Encrypted backups go by default to `~/.local/state/homelab/opnsense/` (outside
Git). Each is generated atomically. The script does **not** create an age
private key, and does not by itself prove future restoreability.

## Required before enabling NAT writes

- Confirm that the encrypted file decrypts with the private identity on a
  trusted host (`age -d -i /secure/path/identity.txt -o /dev/null FILE.age`).
- Verify the decrypted file can be parsed as valid OPNsense XML, ideally on an
  isolated recovery machine. Do not expose the decrypted contents in logs.
- Keep an off-host encrypted copy and document a tested recovery procedure.
- Audit associated filter rules, outbound NAT mode, and firewall API write ACLs.
- Add fail-closed changes: plan, explicit approve, snapshot, set_rule/add_rule,
  apply, post-check, and a demonstrated rollback/recovery path. An automated
  `apply` must not be enabled while these safeguards remain unverified.
