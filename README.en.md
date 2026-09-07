# openwrt-fibocom-l860gl

One-shot installer for the **Fibocom L860-GL** (Intel XMM7560) modem on **OpenWrt 25 (apk)**: XMM drivers, a ready-to-use network interface, and the [4IceG](https://github.com/4IceG) panels — `3ginfo-lite`, `sms-tool-js`, `modemband` — in a single run on a clean system.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue) ![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · **English**

---

This is a field-tested fork of
[lastik9/openwrt-fibocom-l860gl](https://github.com/lastik9/openwrt-fibocom-l860gl).
It fixes the UCI PDP option, distinguishes SIM/contact failures from APN
failures, defaults to the operator-provided APN, and restores XMM after a USB
power-cycle. See the [English field notes](docs/TROUBLESHOOTING.en.md) or the
[full Russian report](docs/TROUBLESHOOTING.ru.md).

One-shot installer that brings up a **Fibocom L860-GL** (Intel XMM7560) modem on **OpenWrt 25 (apk)**: XMM drivers, a ready-to-use network interface, and the [4IceG](https://github.com/4IceG) panels (`3ginfo-lite`, `sms-tool-js`, `modemband`). A companion uninstaller reverts everything cleanly.

### Why

The L860-GL is an M.2 modem based on Intel's XMM7560. Unlike Qualcomm modems (qmi/mbim) it uses the **XMM** proto, and its AT port is `cdc-acm` (`/dev/ttyACM*`), not `option`/`ttyUSB*`. Getting it up on OpenWrt and reading telemetry needs a specific package set and the right port/interface binding. The script does all of that and configures the 4IceG panels against the detected port, avoiding the usual pitfalls (see "Known issues").

### What the script does

1. Prompts for the **APN** and whether to install **Russian** panel translations. Pressing Enter at both prompts accepts the defaults: the operator-provided APN and Russian translations.
2. Adds the [132lan](https://openwrt.132lan.ru) modem feed and installs the XMM stack: `luci-proto-xmm`, `xmm-modem`, `kmod-usb-acm`, `kmod-usb-net-cdc-ncm`, `kmod-usb-serial-option`, etc., plus `sms-tool`.
3. Adds the [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk repo and key (idempotent, alongside the 132lan feed).
4. Installs `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ RU locales if chosen).
5. **Auto-detects the AT port** with `AT+CGMM` and checks SIM state with `AT+CPIN?`.
6. Creates the **`LTE_Fibocom_860`** interface using the XMM handler's actual `pdp` UCI option and adds it to the `wan` firewall zone.
7. Points the panels at the detected port: 3ginfo (`device` + `network`), modemband (`set_port` + `iface`), sms-tool (5 ports), and sets the SMS prefix to `7`.
8. Installs reliable USB re-attach handling and the `l860-healthcheck` command.
9. Reboots the router (10-second countdown, cancel with `Ctrl+C`).

### Requirements

- OpenWrt **25.x** with the **apk** package manager (opkg builds are not supported).
- A **Fibocom L860-GL** (Intel XMM7560), plugged in and enumerated (`/dev/ttyACM*` present).
- **Internet on the router** at install time (via another uplink or the modem already up) — packages and keys are downloaded.
- **SSH** access and root.

### Install

Run **on the router** (over SSH):

```
wget -O install-fibocom-l860gl.sh https://raw.githubusercontent.com/Plasmoid77/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

After reboot, open **LuCI → Network → Interfaces** (`LTE_Fibocom_860` should show Carrier/RX/TX) and **LuCI → Modem(s)** (Ctrl+F5 for signal, operator, band).

Settings live in variables at the top of the script: interface name, firewall zone, default APN, PDP type, PIN, SMS prefix — tweak them in one place.

### Uninstall

```
wget -O uninstall-fibocom-l860gl.sh https://raw.githubusercontent.com/Plasmoid77/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

The uninstaller removes the interface and its firewall membership, deletes the packages (panels, `luci-proto-xmm`, `sms-tool` and their deps), cleans the panel configs and the added feeds/key, then reboots. Safe to re-run.

### Known issues

- **`add.sh` / `apk update` fails with `Failed to send request: Operation not permitted`, or the 4IceG panels didn't install (`error 8` / `unexpected end of file` / `UNTRUSTED signature`)** — a **transparent proxy** on the router (Clash / [ssclash](https://github.com/lastik9/openwrt-ssclash) / Mihomo) is to blame. It often routes the `openwrt.132lan.ru` feed into a REJECT rule (hence `Operation not permitted`) and breaks the GitHub redirect. **Do NOT stop the proxy** — in whitelist mode that leaves the router with no internet. Since this version the script detects a running Clash/Mihomo and routes its own downloads through its local proxy `http://127.0.0.1:7890` (env `http_proxy`/`https_proxy`, like openwrt-ssclash), and the 4IceG key/feed URLs are now direct (`raw.githubusercontent.com`, no 302 redirect). Usually nothing to do. If the proxy port differs, pass it at launch:

  ```
  CLASH_PROXY=http://127.0.0.1:7890 sh install-fibocom-l860gl.sh
  ```

  If the feed is still unreachable, allow the domain in your Mihomo config and reload the core:

  ```
  rules:
    - DOMAIN-SUFFIX,132lan.ru,DIRECT   # or PROXY in whitelist mode
  ```

  A leftover feed line (from an ancient version) is cleaned like this:

  ```
  sed -i '\#4IceG/Modem-extras-apk#d' /etc/apk/repositories.d/customfeeds.list && apk update
  ```

- **`wget` saved the file as `index.html`** — behind a proxy busybox `wget` loses the name from the URL. Always download with an explicit name: `wget -O install-fibocom-l860gl.sh <URL>`.
- **`Failed add repository modem_kmod!`** from the 132lan `add.sh` was harmless in the tested setup: the main `modemfeed` was added and matching `kmod-*` packages were available from the official OpenWrt feed. Verify that the following `xmm-modem` and `luci-proto-xmm` installation succeeds.
- **`Carrier: Absent` after install** — do not assume APN first. Run `l860-healthcheck` and verify USB, `CPIN: READY`, LTE registration, PDP context, `wwan0 LOWER_UP`, and ping in that order. `SIM NOT INSERTED` is a physical SIM/contact fault.
- **Ordinary SIMs from different carriers** — leave APN empty. Beeline, MegaFon and T2 supplied their correct Default APN during field tests.
- **No reconnect after modem USB power-cycle** — this fork installs `99-l860-autostart` to serialise composite-device events and avoid overlapping XMM teardown/setup.
- **3ginfo shows no data** — verify the AT port (`ls -l /dev/ttyACM*`, then `sms_tool -d /dev/ttyACM0 at ATI`). If the working port differs, update `device` in 3ginfo.
- **Band locking** via modemband or `AT+XACT` — careful: locking a band that isn't present where you are will prevent registration. Undo with `AT+XACT=2,,,0` (allow all LTE bands). LTE band numbers in `AT+XACT` are offset by +100 (B3 → 103, B7 → 107, B20 → 120).
- **LTE is connected but the traffic does not use it** — happens when a second uplink
  is still configured: a temporary Wi-Fi station (`wifi-iface` in `sta` mode), for
  instance, used to bootstrap the modem installation on a router with no wired
  internet. `LTE_Fibocom_860` is `up`, `l860-healthcheck` returns 0, and the default
  route belongs to the other interface. Both interfaces publish a default route and
  neither has a `metric`, so with equal priority whichever came up last wins. Check
  with:

    ```
    ip route show default
    ip route get 1.1.1.1
    ```

    Fix it with a metric on the **second** uplink. LTE becomes primary and the other
    link stays as an automatic fallback for when the cellular network drops:

    ```
    uci set network.<other_uplink>.metric=100
    uci commit network
    /etc/init.d/network reload
    ```

    If LTE still has no default route afterwards, re-run its setup:

    ```
    ifup LTE_Fibocom_860
    ```

    The interface goes down and comes back in about 15 seconds — the `xmm` protocol
    reattaches over AT commands, which is expected.
- **Editing the scripts on Windows?** Save with **LF (Unix)** line endings. A CRLF in `#!/bin/sh` breaks execution on the router. The repo's `.gitattributes` guards against this.

### Diagnostics

```
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

OpenWrt 25.12.5 (mediatek/filogic, `aarch64_cortex-a53`), Fibocom L860-GL-16, ordinary Beeline, MegaFon and T2 SIMs, including a physical modem-adapter power-cycle.

### Acknowledgments

This project is only an installer. The heavy lifting is done by **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — modem monitoring panel
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT commands
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — LTE band control
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk package repository

Thanks also to [132lan](https://openwrt.132lan.ru) for the modem feed with the XMM drivers. The "update behind whitelists" trick (routing router traffic through Mihomo) comes from [openwrt-ssclash](https://github.com/lastik9/openwrt-ssclash).

Installed components are the property of their authors and distributed under their own licenses. The MIT license covers only this installer's code.

### License

[MIT](LICENSE) © 2026 lastik9
