# openwrt-fibocom-l860gl

Установщик модема **Fibocom L860-GL** (Intel XMM7560) на **OpenWrt 25 (apk)**: разворачивает XMM-драйверы, создаёт сетевой интерфейс и ставит панели [4IceG](https://github.com/4IceG) — `3ginfo-lite`, `sms-tool-js`, `modemband` — за один прогон на чистой системе.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

**Русский** · [English](#english) · [中文](#中文)

---

## Русский

Скрипт устанавливает всё, что нужно для работы и мониторинга модема Fibocom L860-GL на OpenWrt 25, и сам создаёт готовый к работе интерфейс. Второй скрипт — деинсталлятор — начисто откатывает изменения (удобно для тестов без перепрошивки).

### Зачем

L860-GL — это M.2-модем на чипе Intel XMM7560. В отличие от Qualcomm-модемов (qmi/mbim) он работает через протокол **XMM**, а его AT-порт — это `cdc-acm` (`/dev/ttyACM*`), а не `option`/`ttyUSB*`. Чтобы поднять его на OpenWrt и снимать телеметрию, нужен строго определённый набор пакетов и правильная привязка портов/интерфейса. Скрипт всё это разворачивает автоматически и настраивает панели 4IceG под нужный порт, обходя типичные грабли (см. «Известные болячки»).

### Что делает скрипт

1. Спрашивает **APN** (по умолчанию `internet`) и хотите ли ставить **русский язык** для панелей (`[Y/n]`).
2. Подключает модемный фид [132lan](https://openwrt.132lan.ru) и ставит XMM-стек: `luci-proto-xmm`, `xmm-modem`, `kmod-usb-acm`, `kmod-usb-net-cdc-ncm`, `kmod-usb-serial-option` и др., плюс `sms-tool`.
3. Подключает apk-репозиторий [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) и его ключ (идемпотентно, рядом с фидом 132lan).
4. Ставит панели `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ русские локали, если выбрано).
5. **Автоопределяет AT-порт**: опрашивает `ttyACM0..3` командой `ATI` и выбирает тот, что отвечает как Fibocom/L860 (с откатом на `/dev/ttyACM0`).
6. Создаёт интерфейс **`LTE_Fibocom_860`** (proto `xmm`, найденный порт, введённый APN, `pdptype`) и добавляет его в firewall-зону `wan`.
7. Настраивает панели под найденный порт: 3ginfo (`device` + `network`), modemband (`set_port` + `iface`), sms-tool (5 портов), и меняет SMS-префикс на `7`.
8. Перезагружает роутер (с 10-секундным отсчётом и возможностью отмены `Ctrl+C`).

### Требования

- OpenWrt **25.x** с пакетным менеджером **apk** (для opkg-сборок скрипт не предназначен).
- Модем **Fibocom L860-GL** (Intel XMM7560), воткнут и определился (порты `/dev/ttyACM*` присутствуют).
- **Интернет на роутере** на момент установки (через другой аплинк или уже поднятый модем) — качаются пакеты и ключи.
- Доступ по **SSH** и права root.

### Установка

Команды выполняются **на роутере** (по SSH):

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

После перезагрузки открой **LuCI → Network → Interfaces** (у `LTE_Fibocom_860` должны появиться Carrier/RX/TX) и **LuCI → Modem(s)** (обнови Ctrl+F5 — сигнал, оператор, бэнд).

Настройки вынесены в переменные в шапке скрипта: имя интерфейса, firewall-зона, APN по умолчанию, тип PDP, PIN, SMS-префикс — при желании правятся в одном месте.

### Удаление

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

Деинсталлятор снимает интерфейс и его запись из firewall, удаляет пакеты (панели, `luci-proto-xmm`, `sms-tool` и их зависимости), чистит конфиги панелей и добавленные фиды/ключ, затем перезагружается. Безопасен к повторному запуску.

### Известные болячки

- **`Failed add repository modem_kmod!`** при работе `add.sh` 132lan — безвредно. Нужные драйверы (`xmm-modem`, `kmod-*`) ставятся из официальных фидов OpenWrt, на установку это не влияет.
- **`Carrier: Absent` после установки** — почти всегда неверный **APN**. Он зависит от оператора: скрипт по умолчанию ставит `internet`, но у части тарифов он другой. Исправь APN в интерфейсе и `Save & Apply`.
- **3ginfo не показывает данные** — проверь AT-порт (`ls -l /dev/ttyACM*`, затем `sms_tool -d /dev/ttyACM0 at ATI`). Если рабочий порт другой — поправь `device` в 3ginfo.
- **Лок бэндов** через modemband или `AT+XACT` — осторожно: если залочить бэнд, которого нет в твоей точке, модем не зарегистрируется. Откат: `AT+XACT=2,,,0` (разрешить все LTE-бэнды). Нумерация LTE-бэндов в `AT+XACT` со сдвигом +100 (B3 → 103, B7 → 107, B20 → 120).
- **Правишь скрипты на Windows?** Сохраняй в переводах строк **LF (Unix)**. CRLF в `#!/bin/sh` ломает запуск на роутере. В репозитории это подстраховано файлом `.gitattributes`.

### Диагностика

```sh
ls -l /dev/ttyACM*                                   # порты модема
sms_tool -d /dev/ttyACM0 at 'ATI'                    # ответ модема
sms_tool -d /dev/ttyACM0 at 'AT+CSQ'                 # сигнал (xx,yy)
sms_tool -d /dev/ttyACM0 at 'AT+COPS?'               # оператор
sms_tool -d /dev/ttyACM0 at 'AT+CGDCONT?'            # настроенный APN
uci show network.LTE_Fibocom_860                     # конфиг интерфейса
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_Fibocom_860 | grep -i up                # поднят ли интерфейс
logread | grep -i xmm                                # лог протокола XMM
```

### Проверено на

OpenWrt 25.12.x (mediatek/filogic, `aarch64_cortex-a53`), модем Fibocom L860-GL-16, оператор Yota.

### Благодарности

Проект — лишь установщик. Основная работа сделана в проектах **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — панель мониторинга модема
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT-команды
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — управление LTE-диапазонами
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk-репозиторий пакетов

Также спасибо [132lan](https://openwrt.132lan.ru) за модемный фид с XMM-драйверами.

Устанавливаемые компоненты — собственность их авторов и распространяются под их лицензиями. Лицензия MIT покрывает только код этого установщика.

### Лицензия

[MIT](LICENSE) © 2026 lastik997

---

## English

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
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

After reboot, open **LuCI → Network → Interfaces** (`LTE_Fibocom_860` should show Carrier/RX/TX) and **LuCI → Modem(s)** (Ctrl+F5 for signal, operator, band).

Settings live in variables at the top of the script: interface name, firewall zone, default APN, PDP type, PIN, SMS prefix — tweak them in one place.

### Uninstall

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
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

[MIT](LICENSE) © 2026 lastik997

---

## 中文

一键安装脚本，在 **OpenWrt 25 (apk)** 上部署 **Fibocom L860-GL**（Intel XMM7560）调制解调器：安装 XMM 驱动、创建可直接使用的网络接口，并安装 [4IceG](https://github.com/4IceG) 面板（`3ginfo-lite`、`sms-tool-js`、`modemband`）。另附卸载脚本，可干净还原全部改动。

### 为什么

L860-GL 是基于 Intel XMM7560 的 M.2 模块。与高通模块（qmi/mbim）不同，它使用 **XMM** 协议，AT 端口为 `cdc-acm`（`/dev/ttyACM*`），而非 `option`/`ttyUSB*`。要在 OpenWrt 上使其工作并读取遥测数据，需要一组特定的软件包以及正确的端口/接口绑定。脚本会自动完成这些操作，并将 4IceG 面板配置到检测到的端口，绕开常见坑（见"已知问题"）。

### 脚本做了什么

1. 询问 **APN**（默认 `internet`）以及是否安装面板的**俄语**翻译（`[Y/n]`）。
2. 添加 [132lan](https://openwrt.132lan.ru) 调制解调器软件源，并安装 XMM 组件：`luci-proto-xmm`、`xmm-modem`、`kmod-usb-acm`、`kmod-usb-net-cdc-ncm`、`kmod-usb-serial-option` 等，以及 `sms-tool`。
3. 添加 [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) 的 apk 软件源与密钥（幂等，与 132lan 源并存）。
4. 安装 `luci-app-3ginfo-lite`、`luci-app-sms-tool-js`、`luci-app-modemband`（如选择，含俄语本地化）。
5. **自动检测 AT 端口**：用 `ATI` 探测 `ttyACM0..3`，选出识别为 Fibocom/L860 的端口（默认回退到 `/dev/ttyACM0`）。
6. 创建 **`LTE_Fibocom_860`** 接口（协议 `xmm`、检测到的端口、输入的 APN、`pdptype`），并加入 `wan` 防火墙区域。
7. 将各面板指向检测到的端口：3ginfo（`device` + `network`）、modemband（`set_port` + `iface`）、sms-tool（5 个端口），并将短信前缀设为 `7`。
8. 重启路由器（10 秒倒计时，可用 `Ctrl+C` 取消）。

### 系统要求

- 使用 **apk** 包管理器的 OpenWrt **25.x**（不支持 opkg 版本）。
- **Fibocom L860-GL**（Intel XMM7560），已插入并被识别（存在 `/dev/ttyACM*`）。
- 安装时路由器**可访问互联网**（通过其他上行或已连通的模块）——需要下载软件包与密钥。
- **SSH** 访问及 root 权限。

### 安装

在**路由器上**（通过 SSH）执行：

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

重启后，打开 **LuCI → Network → Interfaces**（`LTE_Fibocom_860` 应显示 Carrier/RX/TX），以及 **LuCI → Modem(s)**（按 Ctrl+F5 查看信号、运营商、频段）。

设置项位于脚本顶部的变量中：接口名、防火墙区域、默认 APN、PDP 类型、PIN、短信前缀——可在一处修改。

### 卸载

```sh
wget https://raw.githubusercontent.com/lastik997/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

卸载脚本会移除接口及其防火墙归属，删除软件包（面板、`luci-proto-xmm`、`sms-tool` 及其依赖），清理面板配置以及新增的软件源/密钥，然后重启。可安全重复运行。

### 已知问题

- 132lan 的 `add.sh` 运行时出现 **`Failed add repository modem_kmod!`** —— 无害。所需驱动（`xmm-modem`、`kmod-*`）来自官方 OpenWrt 软件源，不影响安装。
- 安装后 **`Carrier: Absent`** —— 几乎都是 **APN** 不对。APN 因运营商而异：脚本默认 `internet`，但部分套餐不同。在接口上修正 APN 并 `Save & Apply`。
- **3ginfo 无数据** —— 检查 AT 端口（`ls -l /dev/ttyACM*`，然后 `sms_tool -d /dev/ttyACM0 at ATI`）。若可用端口不同，请更新 3ginfo 的 `device`。
- 通过 modemband 或 `AT+XACT` **锁频段** —— 谨慎：若锁定本地不存在的频段，模块将无法注册。撤销：`AT+XACT=2,,,0`（允许所有 LTE 频段）。`AT+XACT` 中 LTE 频段编号需 +100（B3 → 103，B7 → 107，B20 → 120）。
- **在 Windows 上编辑脚本？** 请保存为 **LF（Unix）** 换行。`#!/bin/sh` 中的 CRLF 会导致在路由器上无法运行。仓库的 `.gitattributes` 已做防护。

### 诊断

```sh
ls -l /dev/ttyACM*                                   # 模块端口
sms_tool -d /dev/ttyACM0 at 'ATI'                    # 模块应答
sms_tool -d /dev/ttyACM0 at 'AT+CSQ'                 # 信号 (xx,yy)
sms_tool -d /dev/ttyACM0 at 'AT+COPS?'               # 运营商
sms_tool -d /dev/ttyACM0 at 'AT+CGDCONT?'            # 已配置的 APN
uci show network.LTE_Fibocom_860                     # 接口配置
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_Fibocom_860 | grep -i up                # 接口是否已启动
logread | grep -i xmm                                # XMM 协议日志
```

### 测试环境

OpenWrt 25.12.x（mediatek/filogic，`aarch64_cortex-a53`），Fibocom L860-GL-16 模块，Yota 运营商。

### 致谢

本项目只是一个安装器。核心工作由 **[4IceG](https://github.com/4IceG)** 完成：

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) —— 模块监控面板
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) —— 短信 / USSD / AT 命令
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) —— LTE 频段控制
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) —— apk 软件源

同时感谢 [132lan](https://openwrt.132lan.ru) 提供含 XMM 驱动的调制解调器软件源。

所安装的组件归其作者所有，并按其各自的许可证分发。MIT 许可证仅覆盖本安装器的代码。

### 许可证

[MIT](LICENSE) © 2026 lastik997
