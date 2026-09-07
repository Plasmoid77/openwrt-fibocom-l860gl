# Changelog

## Unreleased

### Documented

- a second uplink left on the router — typically the temporary Wi-Fi station used
  to bootstrap the installation — keeps the default route away from LTE, because
  both interfaces publish one and neither carries a `metric`. Give the secondary
  link a worse metric so LTE stays primary and the other remains an automatic
  fallback; `ifup LTE_Fibocom_860` re-installs the route if it is still missing.

### Changed

- make automatic APN and Russian translations explicit Enter-key defaults in
  the interactive installer;
- accept `auto` and `automatic` as aliases for the operator-provided APN.

## 1.1.0 — 2026-09-03 — Plasmoid77 field fixes

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

### End-to-end verification

- repeated the one-shot installer over an existing configured installation;
- completed a full OpenWrt reboot with automatic T2 registration and Default APN;
- power-cycled only the external modem adapter and observed USB removal,
  composite-device re-enumeration, XMM retry and automatic recovery;
- confirmed `wwan0` as `UP,LOWER_UP` and stable IPv4 connectivity with no packet
  loss after recovery.
