# openwrt-fibocom-l860gl

One-shot installer for the **Fibocom L860-GL** (Intel XMM7560) modem on **OpenWrt 25 (apk)**: XMM drivers, a ready-to-use network interface, and the [4IceG](https://github.com/4IceG) panels — `3ginfo-lite`, `sms-tool-js`, `modemband` — in a single run on a clean system.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · **English** · [中文](README.zh.md)

---

One-shot installer that brings up a **Fibocom L860-GL** (Intel XMM7560) modem on **OpenWrt 25 (apk)**: XMM drivers, a ready-to-use network interface, and the [4IceG](https://github.com/4IceG) panels (`3ginfo-lite`, `sms-tool-js`, `modemband`). A companion uninstaller reverts everything cleanly.

### Why

The L860-GL is an M.2 modem based on Intel's XMM7560. Unlike Qualcomm modems (qmi/mbim) it uses the **XMM** proto, and its AT port is `cdc-acm` (`/dev/ttyACM*`), not `option`/`ttyUSB*`. Getting it up on OpenWrt and reading telemetry needs a specific package set and the right port/interface binding. The script does all of that and configures the 4IceG panels against the detected port, avoiding the usual pitfalls (see "Known issues").

### What the script does

1. Prompts for the **APN** (default `internet`) and whether to install **Russian** panel translations (`[Y/n]`).
2. Adds the [132lan](https://openwrt.132lan.ru) modem feed and installs the XMM stack: `luci-proto-xmm`, `xmm-modem`, `kmod-usb-acm`, `kmod-usb-net-cdc-ncm`, `kmod-usb-serial-option`, etc., plus `sms-tool`.
3. Adds the [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk repo and key (idempotent, alongside the 132lan feed).
4. Installs `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ RU locales if chosen).
5. **Auto-detects the AT port**: probes `ttyACM0..3` with `ATI` and picks the one identifying as Fibocom/L860 (falls back to `/dev/ttyACM0`).
6. Creates the **`LTE_Fibocom_860`** interface (proto `xmm`, the detected port, the entered APN, `pdptype`) and adds it to the `wan` firewall zone.
7. Points the panels at the detected port: 3ginfo (`device` + `network`), modemband (`set_port` + `iface`), sms-tool (5 ports), and sets the SMS prefix to `7`.
8. Reboots the router (10-second countdown, cancel with `Ctrl+C`).

### Requirements

- OpenWrt **25.x** with the **apk** package manager (opkg builds are not supported).
- A **Fibocom L860-GL** (Intel XMM7560), plugged in and enumerated (`/dev/ttyACM*` present).
- **Internet on the router** at install time (via another uplink or the modem already up) — packages and keys are downloaded.
- **SSH** access and root.

### Install

Run **on the router** (over SSH):

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

After reboot, open **LuCI → Network → Interfaces** (`LTE_Fibocom_860` should show Carrier/RX/TX) and **LuCI → Modem(s)** (Ctrl+F5 for signal, operator, band).

Settings live in variables at the top of the script: interface name, firewall zone, default APN, PDP type, PIN, SMS prefix — tweak them in one place.

### Uninstall

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

The uninstaller removes the interface and its firewall membership, deletes the packages (panels, `luci-proto-xmm`, `sms-tool` and their deps), cleans the panel configs and the added feeds/key, then reboots. Safe to re-run.

### Known issues

- **`Failed add repository modem_kmod!`** during the 132lan `add.sh` — harmless. The needed drivers (`xmm-modem`, `kmod-*`) come from the official OpenWrt feeds; install is unaffected.
- **`Carrier: Absent` after install** — almost always a wrong **APN**. It's carrier-specific: the script defaults to `internet`, but some plans differ. Fix the APN on the interface and `Save & Apply`.
- **3ginfo shows no data** — verify the AT port (`ls -l /dev/ttyACM*`, then `sms_tool -d /dev/ttyACM0 at ATI`). If the working port differs, update `device` in 3ginfo.
- **Band locking** via modemband or `AT+XACT` — careful: locking a band that isn't present where you are will prevent registration. Undo with `AT+XACT=2,,,0` (allow all LTE bands). LTE band numbers in `AT+XACT` are offset by +100 (B3 → 103, B7 → 107, B20 → 120).
- **Editing the scripts on Windows?** Save with **LF (Unix)** line endings. A CRLF in `#!/bin/sh` breaks execution on the router. The repo's `.gitattributes` guards against this.

### Diagnostics

```sh
ls -l /dev/ttyACM*                                   # modem ports
sms_tool -d /dev/ttyACM0 at 'ATI'                    # modem reply
sms_tool -d /dev/ttyACM0 at 'AT+CSQ'                 # signal (xx,yy)
sms_tool -d /dev/ttyACM0 at 'AT+COPS?'               # operator
sms_tool -d /dev/ttyACM0 at 'AT+CGDCONT?'            # configured APN
uci show network.LTE_Fibocom_860                     # interface config
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_Fibocom_860 | grep -i up                # interface up?
logread | grep -i xmm                                # XMM proto log
```

### Tested on

OpenWrt 25.12.x (mediatek/filogic, `aarch64_cortex-a53`), Fibocom L860-GL-16 modem, Yota carrier.

### Acknowledgments

This project is only an installer. The heavy lifting is done by **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — modem monitoring panel
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT commands
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — LTE band control
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk package repository

Thanks also to [132lan](https://openwrt.132lan.ru) for the modem feed with the XMM drivers.

Installed components are the property of their authors and distributed under their own licenses. The MIT license covers only this installer's code.

### License

[MIT](LICENSE) © 2026 lastik9
