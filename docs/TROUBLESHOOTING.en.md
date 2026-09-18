# L860-GL-16 on OpenWrt 25: field notes

This document summarises failures reproduced with a Fibocom L860-GL-16 on
OpenWrt 25.12.5 and the fixes included in this fork. The detailed, command-by-
command report is available in [Russian](TROUBLESHOOTING.ru.md).

## Important findings

- `Carrier: Absent` is not automatically an APN problem. Check USB, SIM,
  registration, PDP context and NCM carrier in that order.
- `AT+CPIN?` returning `SIM NOT INSERTED` is a physical SIM/contact problem.
  Power the adapter off and reseat the SIM; changing APN cannot help.
- The tested XMM handler reads UCI option `pdp`, not `pdptype`.
- `/dev/ttyACMx` is documentation notation, not a valid device path.
- An empty APN lets the LTE network select the subscription's Default APN.
  This was verified with ordinary Beeline, MegaFon and T2 SIMs.
- The L860 composite USB device can race the package-provided XMM hotplug
  handler. `files/99-l860-autostart` serialises re-attach and starts one clean
  XMM session without rebooting the router.

## IPv6 / dual-stack (`pdp='IPV4V6'`)

Verified 2026-09-18 on L860-GL-16 (firmware `18601.5001.00.01.16.48`),
OpenWrt 25.12.5, MegaFon SIM (`apn='internet'`).

- The XMM handler carries data on PDP context `profile` (CID 1) and, with
  `pdp='IPV4V6'`, starts a dhcpv6 sub-interface `LTE_Fibocom_860_6` that takes
  a /64 from the modem's RA. The attach context (CID 0) cannot be deleted
  (`AT+CGDCONT=0` → `operation not allowed`) and cannot carry data
  (`AT+CGDATA="M-RAW_IP",0` → `operation not supported`); `profile='0'` ends
  in `NO-CARRIER`.
- MegaFon grants IPv4v6 to that second PDN only about half of the time
  (6 of 12 consecutive activations on a quiet AT port; independent of the
  attach context being IPv4 or IPv4v6). An IPv4-only grant shows as a single
  `AT+CGCONTRDP=1` line and an empty or `::` prefix on the sub-interface.
  When granted, the prefix appears within ~50 s of `ifup` and IPv6 traffic
  starts flowing another ~45–60 s later.
- This fork installs `files/99-l860-dualstack` into `/etc/hotplug.d/iface/`.
  With `pdp` `IPV4V6` or `IPV6` it waits up to 75 s for the prefix after each
  `ifup` and re-runs `ifup` when it is missing, at most 5 times in a row; one
  re-activation is usually enough (~2 min to full dual-stack, also after a
  reboot). Check with `logread -e l860-dualstack`.
- Switch modes any time: `uci set network.LTE_Fibocom_860.pdp='IPV4V6'` (or
  `'IP'`), `uci commit network`, `ifup LTE_Fibocom_860` — or LuCI → Network →
  Interfaces → LTE_Fibocom_860 → Edit → PDP Type. The hook reads `pdp` on
  every `ifup` and does nothing for `IP`. Keep `IP` on a SIM without IPv6:
  requesting IPv4v6 is harmless by itself (the network grants IPv4), but the
  hook cannot tell "operator has no IPv6" from "unlucky grant" and would
  reconnect the PDN up to 5 times on every start.
- MBIM is not an option: the L860-GL exposes MBIM only in PCIe mode (`iosm`);
  the USB composition 8087:095a has no MBIM interface and `AT+GTUSBMODE`,
  `AT+XUSBCFG`, `AT+XUSBCOMP` are not implemented in this firmware.

## Minimal configuration

```text
proto:  xmm
device: /dev/ttyACM0
APN:    empty (operator Default APN)
PDP:    IP
zone:   wan
```

Run the installed non-destructive diagnostic command after setup:

```sh
l860-healthcheck
```

Do not publish complete `AT+CIMI`, `AT+CCID` or `AT+CGSN` output; it contains
subscriber/device identifiers.
