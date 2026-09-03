#!/bin/sh

# Non-destructive health check for a Fibocom L860-GL XMM interface.
# Subscriber identifiers (IMSI, ICCID and IMEI) are deliberately not printed.

IFACE_NAME="${IFACE_NAME:-LTE_Fibocom_860}"
AT_PORT="$(uci -q get "network.${IFACE_NAME}.device")"
[ -n "$AT_PORT" ] || AT_PORT="/dev/ttyACM0"

say() { printf '\n== %s ==\n' "$1"; }
at() { sms_tool -d "$AT_PORT" at "$1" 2>/dev/null || true; }

say "USB and ports"
if [ -c "$AT_PORT" ]; then
	echo "AT port: $AT_PORT"
else
	echo "ERROR: AT port $AT_PORT is absent"
fi
for port in /dev/ttyACM*; do
	[ -c "$port" ] && echo "$port"
done
for netdev in /sys/class/net/wwan*; do
	[ -d "$netdev" ] && basename "$netdev"
done

say "SIM"
at 'AT+CPIN?' | sed -n '/CPIN:/p'

say "Registration"
at 'AT+COPS?' | sed -n '/COPS:/p'
at 'AT+CEREG?' | sed -n '/CEREG:/p'

say "PDP context"
at 'AT+CGCONTRDP=1' | sed -n '/CGCONTRDP:/p'

say "OpenWrt interface"
STATUS="$(ifstatus "$IFACE_NAME" 2>/dev/null || true)"
if [ -n "$STATUS" ]; then
	printf 'up: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@.up')"
	printf 'pending: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@.pending')"
	printf 'available: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@.available')"
	printf 'device: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@.l3_device')"
	printf 'address: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@["ipv4-address"][0].address')"
	printf 'dns: %s\n' "$(printf '%s' "$STATUS" | jsonfilter -e '@["dns-server"][0]')"
else
	echo "ERROR: OpenWrt interface $IFACE_NAME was not found"
fi

L3_DEVICE="$(printf '%s' "$STATUS" | jsonfilter -e '@.l3_device')"
if [ -n "$L3_DEVICE" ]; then
	say "Connectivity"
	ip link show "$L3_DEVICE" 2>/dev/null | sed -n '1p'
	ping -I "$L3_DEVICE" -c 3 -W 3 1.1.1.1 || true
fi
