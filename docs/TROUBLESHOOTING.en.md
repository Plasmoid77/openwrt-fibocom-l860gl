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
