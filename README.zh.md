# openwrt-fibocom-l860gl

在 **OpenWrt 25 (apk)** 上一键部署 **Fibocom L860-GL**（Intel XMM7560）调制解调器：安装 XMM 驱动、创建即用型网络接口，并安装 [4IceG](https://github.com/4IceG) 面板 —— `3ginfo-lite`、`sms-tool-js`、`modemband`。

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue) ![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · [English](README.en.md) · **中文**

---

这是 [lastik9/openwrt-fibocom-l860gl](https://github.com/lastik9/openwrt-fibocom-l860gl)
的实机修复版本。修复内容包括 `pdp` UCI 参数、SIM 状态诊断、运营商自动
APN，以及无需重启路由器的 USB 重新连接。详细说明请参阅
[English field notes](docs/TROUBLESHOOTING.en.md)。

一键安装脚本，在 **OpenWrt 25 (apk)** 上部署 **Fibocom L860-GL**（Intel XMM7560）调制解调器：安装 XMM 驱动、创建可直接使用的网络接口，并安装 [4IceG](https://github.com/4IceG) 面板（`3ginfo-lite`、`sms-tool-js`、`modemband`）。另附卸载脚本，可干净还原全部改动。

### 为什么

L860-GL 是基于 Intel XMM7560 的 M.2 模块。与高通模块（qmi/mbim）不同，它使用 **XMM** 协议，AT 端口为 `cdc-acm`（`/dev/ttyACM*`），而非 `option`/`ttyUSB*`。要在 OpenWrt 上使其工作并读取遥测数据，需要一组特定的软件包以及正确的端口/接口绑定。脚本会自动完成这些操作，并将 4IceG 面板配置到检测到的端口，绕开常见坑（见“已知问题”）。

### 脚本做了什么

1. 询问 **APN**（留空则使用运营商 Default APN）以及是否安装面板的**俄语**翻译（`[Y/n]`）。
2. 添加 [132lan](https://openwrt.132lan.ru) 调制解调器软件源，并安装 XMM 组件：`luci-proto-xmm`、`xmm-modem`、`kmod-usb-acm`、`kmod-usb-net-cdc-ncm`、`kmod-usb-serial-option` 等，以及 `sms-tool`。
3. 添加 [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) 的 apk 软件源与密钥（幂等，与 132lan 源并存）。
4. 安装 `luci-app-3ginfo-lite`、`luci-app-sms-tool-js`、`luci-app-modemband`（如选择，含俄语本地化）。
5. **自动检测 AT 端口**：用 `AT+CGMM` 探测端口，并用 `AT+CPIN?` 检查 SIM 状态。
6. 创建 **`LTE_Fibocom_860`** 接口（协议 `xmm`、检测到的端口、APN、正确的 `pdp` 参数），并加入 `wan` 防火墙区域。
7. 将各面板指向检测到的端口：3ginfo（`device` + `network`）、modemband（`set_port` + `iface`）、sms-tool（5 个端口），并将短信前缀设为 `7`。
8. 安装 USB 自动重连 hook 和 `l860-healthcheck` 诊断命令。
9. 重启路由器（10 秒倒计时，可用 `Ctrl+C` 取消）。

### 系统要求

- 使用 **apk** 包管理器的 OpenWrt **25.x**（不支持 opkg 版本）。
- **Fibocom L860-GL**（Intel XMM7560），已插入并被识别（存在 `/dev/ttyACM*`）。
- 安装时路由器**可访问互联网**（通过其他上行或已连通的模块）——需要下载软件包与密钥。
- **SSH** 访问及 root 权限。

### 安装

在**路由器上**（通过 SSH）执行：

```
wget -O install-fibocom-l860gl.sh https://raw.githubusercontent.com/Plasmoid77/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

重启后，打开 **LuCI → Network → Interfaces**（`LTE_Fibocom_860` 应显示 Carrier/RX/TX），以及 **LuCI → Modem(s)**（按 Ctrl+F5 查看信号、运营商、频段）。

设置项位于脚本顶部的变量中：接口名、防火墙区域、默认 APN、PDP 类型、PIN、短信前缀——可在一处修改。

### 卸载

```
wget -O uninstall-fibocom-l860gl.sh https://raw.githubusercontent.com/Plasmoid77/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
sh uninstall-fibocom-l860gl.sh
```

卸载脚本会移除接口及其防火墙归属，删除软件包（面板、`luci-proto-xmm`、`sms-tool` 及其依赖），清理面板配置以及新增的软件源/密钥，然后重启。可安全重复运行。

### 已知问题

- **`add.sh` / `apk update` 报 `Failed to send request: Operation not permitted`，或 4IceG 面板未安装（`error 8` / `unexpected end of file` / `UNTRUSTED signature`）** —— 罪魁是路由器上的**透明代理**（Clash / [ssclash](https://github.com/lastik9/openwrt-ssclash) / Mihomo）。它常把 `openwrt.132lan.ru` 源导入 REJECT 规则（因而出现 `Operation not permitted`），并破坏 GitHub 重定向。**不要停止代理** —— 在“白名单”模式下这会让路由器彻底断网。从此版本起，脚本会检测正在运行的 Clash/Mihomo，并把自身的下载经其本地代理 `http://127.0.0.1:7890`（环境变量 `http_proxy`/`https_proxy`，与 openwrt-ssclash 一致）转发；4IceG 的密钥/源链接现已改为直连（`raw.githubusercontent.com`，无 302 重定向）。通常无需任何操作。若代理端口不同，可在启动时指定：

  ```
  CLASH_PROXY=http://127.0.0.1:7890 sh install-fibocom-l860gl.sh
  ```

  若源仍不可达，请在 Mihomo 配置中放行该域名并重载内核：

  ```
  rules:
    - DOMAIN-SUFFIX,132lan.ru,DIRECT   # 白名单模式下改为 PROXY
  ```

  旧版本残留的源行可这样清理：

  ```
  sed -i '\#4IceG/Modem-extras-apk#d' /etc/apk/repositories.d/customfeeds.list && apk update
  ```

- **`wget` 把文件保存成了 `index.html`** —— 在代理后 busybox 的 `wget` 会丢失 URL 中的文件名。始终用显式文件名下载：`wget -O install-fibocom-l860gl.sh <URL>`。
- 132lan 的 `add.sh` 运行时出现 **`Failed add repository modem_kmod!`** —— 在已测试的环境中无害：主 `modemfeed` 已成功添加，匹配内核的 `kmod-*` 可从官方 OpenWrt 源获得。仍需确认后续 `xmm-modem` 和 `luci-proto-xmm` 安装成功。
- 安装后 **`Carrier: Absent`** —— 不要先假定是 APN。运行 `l860-healthcheck`，依次检查 USB、`CPIN: READY`、LTE 注册、PDP、`wwan0 LOWER_UP` 和 ping。`SIM NOT INSERTED` 表示物理 SIM/触点问题。
- 普通 SIM 可将 APN 留空；Beeline、MegaFon 和 T2 的 Default APN 已通过实机验证。
- USB 断电后，本版本的 `99-l860-autostart` 会等待设备稳定并自动恢复 XMM 接口。
- **3ginfo 无数据** —— 检查 AT 端口（`ls -l /dev/ttyACM*`，然后 `sms_tool -d /dev/ttyACM0 at ATI`）。若可用端口不同，请更新 3ginfo 的 `device`。
- 通过 modemband 或 `AT+XACT` **锁频段** —— 谨慎：若锁定本地不存在的频段，模块将无法注册。撤销：`AT+XACT=2,,,0`（允许所有 LTE 频段）。`AT+XACT` 中 LTE 频段编号需 +100（B3 → 103，B7 → 107，B20 → 120）。
- **在 Windows 上编辑脚本？** 请保存为 **LF（Unix）** 换行。`#!/bin/sh` 中的 CRLF 会导致在路由器上无法运行。仓库的 `.gitattributes` 已做防护。

### 诊断

```
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

OpenWrt 25.12.5（mediatek/filogic，`aarch64_cortex-a53`），Fibocom L860-GL-16，Beeline、MegaFon 和 T2 普通 SIM，并验证了 USB 适配器断电重连。

### 致谢

本项目只是一个安装器。核心工作由 **[4IceG](https://github.com/4IceG)** 完成：

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) —— 模块监控面板
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) —— 短信 / USSD / AT 命令
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) —— LTE 频段控制
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) —— apk 软件源

同时感谢 [132lan](https://openwrt.132lan.ru) 提供含 XMM 驱动的调制解调器软件源。“白名单更新”技巧（将路由器流量经 Mihomo 转发）来自 [openwrt-ssclash](https://github.com/lastik9/openwrt-ssclash)。

所安装的组件归其作者所有，并按其各自的许可证分发。MIT 许可证仅覆盖本安装器的代码。

### 许可证

[MIT](LICENSE) © 2026 lastik9，field fixes © 2026 Plasmoid77
