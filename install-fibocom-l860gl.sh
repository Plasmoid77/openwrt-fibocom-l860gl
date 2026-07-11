#!/bin/sh
#
# install-fibocom-l860gl.sh
# One-shot installer for Fibocom L860-GL (Intel XMM7560)
# on a clean OpenWrt 25.x (apk-based) router.
#
# Installs: XMM proto/drivers (via 132lan modem feed), sms-tool,
#           luci-app-3ginfo-lite + luci-app-sms-tool-js + luci-app-modemband
#           (from 4IceG apk repo) + Russian translations,
#           auto-detects and sets the AT port, and creates a ready-to-use
#           XMM network interface (APN prompted at install time) in the
#           firewall WAN zone.
#
# Differences vs the DW5821e script:
#   - DW5821e = Qualcomm  -> MBIM stack, AT port /dev/ttyUSB1, needs CRLF JSON fix
#   - L860-GL = Intel XMM -> xmm proto, AT port /dev/ttyACM* (auto-detected),
#                            no CRLF fix needed (3ginfo data parses cleanly here)
#
# Usage:
#   scp this file to the router (e.g. /tmp), then:
#   sh /tmp/install-fibocom-l860gl.sh
#
# Re-running is safe: every step is idempotent.

set -e

AT_PORT_DEFAULT="/dev/ttyACM0"  # L860-GL AT port is cdc-acm (ttyACM*), NOT ttyUSB
FEEDS="/etc/apk/repositories.d/customfeeds.list"
KEYDIR="/etc/apk/keys"
# Direct raw.githubusercontent.com URLs on purpose: the github.com/.../raw/...
# form issues a 302 redirect, which HTTP proxies (e.g. Clash/ssclash on :7890)
# mishandle -> "HTTP error 400" / "unexpected end of file" during apk update.
# REPO_ADB is read by apk itself, so a bad URL breaks apk update, not just wget.
REPO_ADB="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/packages.adb"
REPO_KEY="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/IceG-apkpub.pem"
LAN132_BASE="https://openwrt.132lan.ru/packages"

# --- Network interface settings --------------------------------------------
CREATE_INTERFACE="yes"          # yes | no  -- create the XMM interface
IFACE_NAME="LTE_Fibocom_860"    # interface (and UCI section) name
FW_ZONE="wan"                   # firewall zone to place the interface into
APN_DEFAULT="internet"          # used if you just press Enter at the prompt
PDP_TYPE="IPV4V6"               # IP (IPv4) | IPV6 | IPV4V6 (dual-stack)
PIN_CODE=""                     # SIM PIN, leave empty if the SIM has none

# --- 4IceG panel settings --------------------------------------------------
SMS_PREFIX="7"                  # country dialing prefix for sms-tool (48=PL, 7=RU)

say() { echo ""; echo ">>> $1"; }

# Best-effort apk add: never abort the whole run (set -e) if one package is
# missing (e.g. the 4IceG feed is unreachable behind a proxy).
add_opt() { apk add "$1" || echo "   (skipped $1)"; }

# --- Ask for the APN up front so the rest can run unattended ---------------
APN="$APN_DEFAULT"
if [ "$CREATE_INTERFACE" = "yes" ]; then
    printf 'APN for the LTE interface [%s]: ' "$APN_DEFAULT"
    read -r apn_input || apn_input=""
    [ -n "$apn_input" ] && APN="$apn_input"
    echo "   using APN: $APN"
fi

# --- Ask whether to install Russian translations ---------------------------
# Covers all three 4IceG panels: 3ginfo-lite, sms-tool-js and modemband.
INSTALL_RU="yes"
printf 'Install Russian translations for the 4IceG panels? [Y/n]: '
read -r ru_input || ru_input=""
case "$ru_input" in
    [Nn]*) INSTALL_RU="no" ;;
    *)     INSTALL_RU="yes" ;;
esac
echo "   Russian translations: $INSTALL_RU"

# --- 1. Drivers: XMM proto + serial/ACM AT ports ---------------------------
# The 132lan add.sh registers the modem feed; `apk add luci-proto-xmm` then
# pulls xmm-modem, kmod-usb-net-cdc-ncm, kmod-usb-acm, kmod-usb-serial-option,
# i.e. everything the L860-GL needs (cdc-acm gives us the /dev/ttyACM* AT port).
say "Step 1: installing modem drivers (XMM proto via 132lan feed)"
apk update
. /etc/openwrt_release
REL="${DISTRIB_RELEASE%.*}"          # e.g. 25.12.4 -> 25.12
cd /tmp && wget "${LAN132_BASE}/${REL}/packages/add.sh" -O - | sh
apk add luci-proto-xmm
apk add sms-tool

# --- 2. Add 4IceG apk repository (key first, then feed, roll back on failure)
# Order matters: fetch a VALID key BEFORE adding the feed line. Otherwise a
# failed key download (set -e) leaves the feed line in place, and every later
# apk update on the router breaks with a non-obvious error.
say "Step 2: adding 4IceG apk repository"
mkdir -p "$KEYDIR"
ICEG_KEY="$KEYDIR/IceG-apkpub.pem"

# A leftover file doesn't prove the key is correct (a stale/foreign key gives
# "UNTRUSTED signature"; behind a proxy an HTML error page may land here too).
# So we check the PEM header, not just existence.
key_ok() { [ -s "$1" ] && head -n1 "$1" | grep -q 'BEGIN PUBLIC KEY'; }

if key_ok "$ICEG_KEY"; then
    echo "   signing key present"
else
    rm -f "$ICEG_KEY"
    if wget -q "$REPO_KEY" -O "$ICEG_KEY" && key_ok "$ICEG_KEY"; then
        echo "   signing key installed"
    else
        rm -f "$ICEG_KEY"
        echo "   WARNING: could not fetch a valid 4IceG key — panels will be skipped"
        echo "   (behind a proxy? try: /etc/init.d/clash stop, then re-run)"
    fi
fi

ICEG_OK=0
if [ -s "$ICEG_KEY" ]; then
    grep -qF "$REPO_ADB" "$FEEDS" 2>/dev/null || echo "$REPO_ADB" >> "$FEEDS"
    if apk update; then
        ICEG_OK=1
    else
        echo "   WARNING: apk update failed with the 4IceG feed — removing it again"
        sed -i '\#4IceG/Modem-extras-apk#d' "$FEEDS" 2>/dev/null
        apk update || true
    fi
else
    # No key -> never leave the feed line behind (it would break apk update).
    sed -i '\#4IceG/Modem-extras-apk#d' "$FEEDS" 2>/dev/null
    apk update || true
fi

# --- 3. Install the plugins ------------------------------------------------
# Best-effort throughout: if the 4IceG feed is unavailable the modem still
# comes up (the XMM interface below is built from the 132lan feed, which has
# no redirect and works behind a proxy).
say "Step 3: installing 3ginfo-lite, sms-tool-js and modemband"
if [ "$ICEG_OK" = "1" ]; then
    add_opt luci-app-3ginfo-lite
    add_opt luci-app-sms-tool-js
    # modemband: GUI band-locking for L860-GL (drives AT+XACT under the hood).
    add_opt luci-app-modemband

    if [ "$INSTALL_RU" = "yes" ]; then
        say "Step 3: installing Russian translations"
        add_opt luci-i18n-3ginfo-lite-ru
        add_opt luci-i18n-sms-tool-js-ru
        add_opt luci-i18n-modemband-ru
    fi
else
    echo "   WARNING: 4IceG feed unavailable — skipping panels (3ginfo/sms-tool/modemband)."
    echo "   The modem itself will still come up. Re-run after fixing feed access"
    echo "   (behind a proxy? /etc/init.d/clash stop, then re-run this script)."
fi

# --- 4. Detect + set the AT port -------------------------------------------
# L860-GL exposes several /dev/ttyACM* ports; only one answers AT commands.
# We probe ttyACM0..3 with ATI and pick the one that identifies as Fibocom/L860
# (falling back to the first AT-capable port, then to the default).
say "Step 4: detecting modem AT port"
AT_PORT=""
if command -v sms_tool >/dev/null 2>&1; then
    for p in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2 /dev/ttyACM3; do
        [ -c "$p" ] || continue
        resp="$(sms_tool -d "$p" at "ATI" 2>/dev/null || true)"
        if echo "$resp" | grep -qiE 'Fibocom|L860'; then
            AT_PORT="$p"; break
        fi
        if [ -z "$AT_PORT" ] && echo "$resp" | grep -qi 'OK'; then
            AT_PORT="$p"   # remember first AT-capable port, keep looking for L860
        fi
    done
fi
[ -n "$AT_PORT" ] || AT_PORT="$AT_PORT_DEFAULT"

say "Step 4: setting AT port to $AT_PORT"
if [ "$AT_PORT" = "$AT_PORT_DEFAULT" ] && ! [ -c "$AT_PORT" ]; then
    echo "   NOTE: could not probe a live AT port (modem may enumerate after reboot)."
    echo "   Using default $AT_PORT. Verify after reboot with:"
    echo "       ls -l /dev/ttyACM* ; sms_tool -d /dev/ttyACM0 at ATI"
    echo "   and if needed:  uci set 3ginfo.@3ginfo[0].device=/dev/ttyACMx; uci commit 3ginfo"
fi
# Guarded: if the 4IceG feed was unreachable, 3ginfo isn't installed and its
# config doesn't exist -- skip rather than abort (the modem still comes up).
if [ -f /etc/config/3ginfo ]; then
    uci set 3ginfo.@3ginfo[0].device="$AT_PORT"
    [ "$CREATE_INTERFACE" = "yes" ] && uci set 3ginfo.@3ginfo[0].network="$IFACE_NAME"
    uci commit 3ginfo
fi

# --- 5. Create the XMM network interface -----------------------------------
# Builds a ready-to-use interface: proto=xmm, the auto-detected modem port,
# the APN entered above, and membership in the WAN firewall zone.
if [ "$CREATE_INTERFACE" = "yes" ]; then
    say "Step 5: creating interface '$IFACE_NAME' (proto xmm, port $AT_PORT, APN $APN)"

    uci set network."$IFACE_NAME"=interface
    uci set network."$IFACE_NAME".proto='xmm'
    uci set network."$IFACE_NAME".device="$AT_PORT"
    uci set network."$IFACE_NAME".apn="$APN"
    uci set network."$IFACE_NAME".pdptype="$PDP_TYPE"
    uci set network."$IFACE_NAME".auth='none'
    if [ -n "$PIN_CODE" ]; then
        uci set network."$IFACE_NAME".pincode="$PIN_CODE"
    fi
    uci commit network

    # Put the interface into the firewall zone (default: wan).
    ZONE_SECT="$(uci show firewall 2>/dev/null | grep "\.name='${FW_ZONE}'" | head -n1 | sed "s/\.name='${FW_ZONE}'.*//")"
    if [ -n "$ZONE_SECT" ]; then
        uci -q del_list "${ZONE_SECT}".network="$IFACE_NAME"   # avoid duplicates
        uci add_list "${ZONE_SECT}".network="$IFACE_NAME"
        uci commit firewall
        echo "   added '$IFACE_NAME' to firewall zone '$FW_ZONE'"
    else
        echo "   WARNING: firewall zone '$FW_ZONE' not found."
        echo "   Add '$IFACE_NAME' to a WAN zone manually in LuCI -> Firewall."
    fi
fi

# --- 6. Configure the 4IceG panels (modemband + sms-tool) ------------------
# Point modemband and sms-tool at the detected AT port, bind modemband to the
# LTE interface, and set the SMS dialing prefix. Each block is guarded on its
# config file so a skipped/absent panel can't abort the run.
say "Step 6: configuring 4IceG panels (port $AT_PORT)"

if [ -f /etc/config/modemband ]; then
    uci set modemband.@modemband[0].set_port="$AT_PORT"
    if [ "$CREATE_INTERFACE" = "yes" ]; then
        uci set modemband.@modemband[0].iface="$IFACE_NAME"
        uci commit modemband
        echo "   modemband: port=$AT_PORT, iface=$IFACE_NAME"
    else
        uci commit modemband
        echo "   modemband: port=$AT_PORT"
    fi
fi

if [ -f /etc/config/sms_tool_js ]; then
    S="sms_tool_js.@sms_tool_js[0]"
    uci set "$S".pnumber="$SMS_PREFIX"
    # All five SMS/USSD/AT/call/read ports -> the detected AT port.
    uci set "$S".readport="$AT_PORT"    # чтение SMS
    uci set "$S".callport="$AT_PORT"    # журнал вызовов
    uci set "$S".sendport="$AT_PORT"    # отправка SMS
    uci set "$S".ussdport="$AT_PORT"    # USSD
    uci set "$S".atport="$AT_PORT"      # AT-команды
    uci commit sms_tool_js
    echo "   sms-tool: prefix=$SMS_PREFIX, all ports=$AT_PORT"
fi

# --- 7. Restart web UI -----------------------------------------------------
say "Step 7: restarting web interface"
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

# --- 8. Reboot -------------------------------------------------------------
# A full reboot ensures modem drivers, ttyACM ports and the web UI all come
# up cleanly from scratch. The reminder is printed BEFORE the countdown so
# there's time to read it (and cancel with Ctrl+C).
say "Step 8: installation complete"
echo "    После перезагрузки:"
echo "      - LuCI -> Network -> Interfaces: у '$IFACE_NAME' должны появиться Carrier/RX/TX."
echo "        Если Carrier остаётся 'Absent' — обычно дело в APN (исправь и Save & Apply)."
echo "      - LuCI -> Modem(s): обнови Ctrl+F5 для сигнала / оператора / бэнда."
echo "    Если 3ginfo не показывает данные модема — проверь AT-порт:"
echo "        ls -l /dev/ttyACM* ; sms_tool -d /dev/ttyACM0 at ATI"
echo "        uci set 3ginfo.@3ginfo[0].device=/dev/ttyACMx; uci commit 3ginfo; /etc/init.d/uhttpd restart"

echo ""
echo ">>> Перезагрузка через 10 секунд (Ctrl+C — отмена)"
i=10
while [ "$i" -gt 0 ]; do
    printf '\r   перезагрузка через %2d с ... ' "$i"
    sleep 1
    i=$((i - 1))
done
echo ""
sync
reboot
