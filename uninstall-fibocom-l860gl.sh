#!/bin/sh
#
# uninstall-fibocom-l860gl.sh
# Reverses install-fibocom-l860gl.sh so you can re-test from a near-clean
# state WITHOUT reflashing the router.
#
# Removes: the LTE interface + its firewall membership; the 4IceG/XMM
# packages (deps like xmm-modem, modemband and the kmods are pulled out too);
# the panel config files (3ginfo, modemband, sms_tool_js); and the added
# apk feeds (4IceG + 132lan) plus the IceG signing key.
#
# NOTE: if you changed IFACE_NAME / FW_ZONE in the installer, match them here.
#
# Usage:  sh /tmp/uninstall-fibocom-l860gl.sh
# Safe to run even if some parts are already gone.

IFACE_NAME="LTE_Fibocom_860"
FW_ZONE="wan"
FEEDS="/etc/apk/repositories.d/customfeeds.list"

# World packages the installer added explicitly (dependents first). Deleting
# these makes apk cascade-remove their orphaned deps.
PKGS="luci-i18n-3ginfo-lite-ru luci-i18n-sms-tool-js-ru luci-i18n-modemband-ru
      luci-app-3ginfo-lite luci-app-sms-tool-js luci-app-modemband
      luci-proto-xmm sms-tool"

# Dependencies to mop up in case they weren't auto-orphaned (harmless if
# already gone, or refused because still needed elsewhere).
DEPS="modemband xmm-modem chat comgt
      kmod-usb-serial-option kmod-usb-serial-wwan kmod-usb-serial
      kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-usb-net-cdc-ether
      kmod-usb-net kmod-usb-acm kmod-mii"

say() { echo ""; echo ">>> $1"; }

# --- 1. Remove the network interface + firewall membership -----------------
say "Removing interface '$IFACE_NAME'"
uci -q delete network."$IFACE_NAME" && uci commit network
ZONE_SECT="$(uci show firewall 2>/dev/null | grep "\.name='${FW_ZONE}'" | head -n1 | sed "s/\.name='${FW_ZONE}'.*//")"
if [ -n "$ZONE_SECT" ]; then
    uci -q del_list "${ZONE_SECT}".network="$IFACE_NAME" && uci commit firewall
    echo "   removed from firewall zone '$FW_ZONE'"
fi

# --- 2. Remove packages (two passes handle dependency ordering) ------------
# Pass 1 does the real work; pass 2 mops up leftovers whose deps blocked them
# the first time. We filter apk's per-package "OK: <size> in <n> packages"
# summary: for a package that is already gone apk prints *only* that line, so a
# long PKGS/DEPS list would produce a wall of identical "OK:" lines that looks
# like the script hung (and tempts people to hit Ctrl+C). Real "Purging ..."
# lines are kept, so you still see what is actually being removed.
say "Removing packages"
for pkg in $PKGS $DEPS; do
    apk del "$pkg" 2>/dev/null | grep -vE '^OK:' || true
done
echo "   second pass (mopping up leftovers, quiet)..."
for pkg in $PKGS $DEPS; do
    apk del "$pkg" >/dev/null 2>&1 || true
done
echo "   packages removed"

# --- 3. Remove panel config files ------------------------------------------
say "Removing leftover configs"
rm -f /etc/config/3ginfo /etc/config/modemband /etc/config/sms_tool_js

# --- 4. Remove added apk feeds + IceG key ----------------------------------
say "Removing added apk feeds and key"
if [ -f "$FEEDS" ]; then
    sed -i '\#4IceG/Modem-extras-apk#d' "$FEEDS"
    sed -i '\#132lan#d' "$FEEDS"
fi
rm -f /etc/apk/keys/IceG-apkpub.pem
apk update

say "Готово — состояние близко к свежей прошивке."
echo "    Сейчас роутер перезагрузится, чтобы выгрузились снятые драйверы"
echo "    и пропали порты ttyACM. После этого можно ставить заново с чистого листа."

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
