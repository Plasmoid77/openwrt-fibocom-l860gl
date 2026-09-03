#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

scripts="
install-fibocom-l860gl.sh
uninstall-fibocom-l860gl.sh
l860-healthcheck.sh
files/99-l860-autostart
"

for script in $scripts; do
	sh -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
	# OpenWrt runtime libraries are intentionally unavailable on the host.
	# ipv6-off.sh is an unrelated upstream utility and remains upstream-owned.
	shellcheck -e SC1091 $scripts
fi

echo "All shell checks passed."
