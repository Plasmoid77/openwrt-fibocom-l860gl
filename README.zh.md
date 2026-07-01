# openwrt-fibocom-l860gl

在 **OpenWrt 25 (apk)** 上一键部署 **Fibocom L860-GL**（Intel XMM7560）调制解调器：安装 XMM 驱动、创建即用型网络接口，并安装 [4IceG](https://github.com/4IceG) 面板 —— `3ginfo-lite`、`sms-tool-js`、`modemband`。

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · [English](README.en.md) · **中文**

---

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
wget https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/install-fibocom-l860gl.sh
sh install-fibocom-l860gl.sh
```

重启后，打开 **LuCI → Network → Interfaces**（`LTE_Fibocom_860` 应显示 Carrier/RX/TX），以及 **LuCI → Modem(s)**（按 Ctrl+F5 查看信号、运营商、频段）。

设置项位于脚本顶部的变量中：接口名、防火墙区域、默认 APN、PDP 类型、PIN、短信前缀——可在一处修改。

### 卸载

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-fibocom-l860gl/main/uninstall-fibocom-l860gl.sh
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

[MIT](LICENSE) © 2026 lastik9
