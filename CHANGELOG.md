# Changelog

## Unreleased — Plasmoid77 field fixes

Based on upstream commit `8a3f895` from
[`lastik9/openwrt-fibocom-l860gl`](https://github.com/lastik9/openwrt-fibocom-l860gl).

### Fixed

- write `pdp` instead of the ignored `pdptype` UCI option;
- use the operator Default APN when the APN prompt is left empty;
- identify L860-GL-16 with `AT+CGMM` and report `AT+CPIN?` state;
- avoid presenting `Carrier: Absent` as primarily an APN failure;
- replace the literal `/dev/ttyACMx` instruction with a health-check command;
- recover automatically after a physical modem-adapter USB power-cycle;
- remove installed hotplug/diagnostic helpers during uninstall.

### Added

- `files/99-l860-autostart`, with duplicate-event suppression and orderly XMM
  teardown/setup;
- `l860-healthcheck`, which avoids printing IMSI, ICCID and IMEI;
- a detailed Russian troubleshooting report and an English summary;
- field verification with ordinary Beeline, MegaFon and T2 SIMs.
