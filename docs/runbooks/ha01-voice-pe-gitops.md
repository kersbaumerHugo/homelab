# HA01 + Voice PE: reproducing the temporary split-network setup

Status: **Observed working end-to-end 2026-10-09; GitOps migration pending.**

This runbook accompanies `network/voice-pe.yml`. It deliberately does **not**
claim the NAT objects, their UUIDs, filter rule association or interface flags
have been read from the live firewall. The manifest captures the intended
configuration based on successful troubleshooting, not an exported firewall state.

## Topology and verified behavior

- Nokia Wi-Fi/upstream subnet: `192.168.1.0/24`; Nokia gateway `192.168.1.254`.
- OPNsense WAN `192.168.1.79`, LAN `192.168.10.1`.
- Home Assistant OS on Proxmox VMID 104, `192.168.10.50`, HTTP port 80.
- Voice PE on Nokia Wi-Fi `192.168.1.93`, ESPHome TCP port 6053.
- Phone at `192.168.1.87` reached `http://192.168.1.79:18080` through WAN DNAT.
- HA advertised internal/local URL in UI was changed to `http://192.168.1.79:18080`.
- Initial Voice PE audio test failed because the **HA Core FFmpeg proxy**
  itself timed out connecting to `192.168.1.79:18080`.
- Hairpin NAT was adjusted; Voice PE subsequently answered a spoken time query.
  This proves an end-to-end voice interaction, not complete disaster recovery.

**Risk:** Nokia DHCP may change `192.168.1.79`, `.87` or `.93`. Without upstream
reservations or another stable access strategy, this transitional topology
is not durable. HTTP is unencrypted on the trusted Nokia Wi-Fi; no upstream
port-forward, DMZ or UPnP should expose it to the public internet.

## Review and validate from dev01

```sh
sudo apt-get install -y python3-yaml  # Debian 13, only if PyYAML is absent
python3 scripts/verify-voice-pe.py validate
python3 scripts/verify-voice-pe.py probe
python3 -m unittest discover -s tests -p test_voice_pe.py
```

Probe results depend on the network namespace running the script. A successful
`dev01` probe does **not** prove hairpin connectivity from HA Core.

To verify the real HA Core -> OPNsense WAN path, in **VM104 Proxmox console**
enter `login`, then run:

```sh
docker exec homeassistant python3 -c 'import socket; s=socket.create_connection(("192.168.10.50",80),timeout=5); print("HA direct OK"); s.close()'
docker exec homeassistant python3 -c 'import socket; s=socket.create_connection(("192.168.1.79",18080),timeout=5); print("HA hairpin OK"); s.close()'
```

Do not use the browser as proof: it runs from a different source IP.

## Capture the *actual* OPNsense state before API adoption

1. Make an encrypted backup of `/conf/config.xml` first (contains secrets).
   With a configured SSH key and a permitted account capable of reading it:

   ```sh
   export OPNSENSE_SSH_HOST=root@192.168.10.1
   export AGE_RECIPIENT='age1...your-own-public-recipient...'
   ./scripts/backup-opnsense-encrypted.sh
   ```

   The age **private identity**, API tokens and raw `config.xml` must never be
   committed. The encrypted snapshot is stored outside the repository by default.
   Keep a second off-host copy and periodically test decryption/recovery.

2. Read live PF NAT rules without changing the firewall, if SSH is available:

   ```sh
   ssh root@192.168.10.1 'pfctl -s nat | grep -E "18080|192[.]168[.]10[.]50"'
   ```

   Audit **Destination NAT, Source NAT, filter rules, SNAT mode** and whether WAN
   blocks private networks. Record exact fields and order from the firewall.

3. Optional read-only MVC API inventory. Create a dedicated least-privilege API
   user/key once, configured with a trusted certificate; place credentials in
   environment variables, not Git or CLI flags:

   ```sh
   export OPNSENSE_URL=https://192.168.10.1
   export OPNSENSE_CA_BUNDLE=/path/to/trusted-opnsense-ca.pem
   export OPNSENSE_API_KEY='...'
   export OPNSENSE_API_SECRET='...'
   python3 scripts/verify-voice-pe.py api-inventory
   ```

   The `api-inventory` command is read-only and prints descriptions/UUIDs, not
   full settings. **Important:** legacy/GUI NAT rules can be invisible to the
   separate MVC Firewall Automation API. An empty result does *not* mean no
   actual NAT rule exists; never auto-create duplicates based only on this scan.

## Future idempotent apply (not yet enabled)

After reconciling the live configuration, adopt the exact DNAT/SNAT/filter
rules into a version-pinned OPNsense API/Ansible module or provider. Verify
compatibility with the running OPNsense version. Use stable IDs, plan/diff,
manual approval for firewall changes, a savepoint/rollback window, apply,
network acceptance tests, and drift detection. Never let CI on a public PR
access a live firewall. Do not use raw `pfctl` to persist rules.

The `migration-pending` guard is intentional: `verify-voice-pe.py` has no
`apply` command. That is safer than an unverified apply script which could
lock out the admin or duplicate working rules. When API adoption is proven,
replace this guard with an actual plan/apply/reconcile implementation.

## Home Assistant recovery and voice setup

Home Assistant's Whisper, Piper, Wyoming, ESPHome config entries, Voice PE
association and voice pipeline are not completely represented by a plain
`configuration.yaml` file. Preserve a **full Home Assistant backup** (including
add-ons and encryption key) or restore the Proxmox VM104 backup from
`hdd-backup`. A VM boot-only restore test does not prove full integration
recovery. Document application versions and verify after restoring.

Recommended checks after disaster recovery:

- HA reachable at `192.168.10.50` and URL shown above is reachable from the
  HA Core container and Voice PE.
- Wyoming integrations connected; Whisper Portuguese STT and Piper PT-BR TTS
  available in Assist pipeline.
- ESPHome sees Voice PE on port `6053`.
- Voice PE hears a wake word and successfully answers a spoken time query.
- Recheck Nokia DHCP addresses, OPNsense firewall rules, and WAN private subnet
  behavior. Remove unnecessary temporary cell-phone access rules when done.

References:
- https://docs.opnsense.org/manual/how-tos/nat_reflection.html
- https://docs.opnsense.org/development/api/core/firewall.html
- https://developers.home-assistant.io/docs/config_entries_index/
- https://www.home-assistant.io/common-tasks/os/#backups
