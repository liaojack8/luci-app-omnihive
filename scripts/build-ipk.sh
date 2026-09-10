#!/usr/bin/env bash
#
# build-ipk.sh - Build an OpenWrt .ipk for a package in this repo without the
# OpenWrt SDK.
#
# This only works for packages whose Build/Compile is empty (pure
# shell/JS/JSON payload), which is the case for luci-app-omnihive. It stages
# <pkg>/root as the data payload, synthesises control + postinst from the
# package Makefile, and packs everything with ar/tar the same way the SDK
# would. It does NOT work for omnihive-core (that needs a per-arch binary).
#
# Usage:
#   scripts/build-ipk.sh [package-dir] [output-dir]
#
# Defaults: package-dir=luci-app-omnihive  output-dir=bin/packages
#
# Env overrides: PKG_VERSION, PKG_RELEASE
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="${1:-luci-app-omnihive}"
OUT_DIR="${2:-bin/packages}"

case "$PKG_DIR" in
	/*) : ;;
	*) PKG_DIR="$REPO_ROOT/$PKG_DIR" ;;
esac
case "$OUT_DIR" in
	/*) : ;;
	*) OUT_DIR="$REPO_ROOT/$OUT_DIR" ;;
esac

MK="$PKG_DIR/Makefile"
[ -f "$MK" ] || { echo "no Makefile at $MK" >&2; exit 1; }
[ -d "$PKG_DIR/root" ] || { echo "no payload dir at $PKG_DIR/root" >&2; exit 1; }

mk_get() { sed -n "s/^$1[?:]*=//p" "$MK" | head -n1 | sed 's/[[:space:]]*$//'; }

PKG_NAME="$(mk_get PKG_NAME)"
PKG_VERSION="${PKG_VERSION:-$(mk_get PKG_VERSION)}"
PKG_RELEASE="${PKG_RELEASE:-$(mk_get PKG_RELEASE)}"
PKG_MAINTAINER="$(mk_get PKG_MAINTAINER)"
PKG_LICENSE="$(mk_get PKG_LICENSE)"
SECTION="$(sed -n 's/^[[:space:]]*SECTION:=//p' "$MK" | head -n1 | sed 's/[[:space:]]*$//')"
TITLE="$(sed -n 's/^[[:space:]]*TITLE:=//p' "$MK" | head -n1 | sed 's/[[:space:]]*$//')"
DESC="$(awk '/^define Package\/.*\/description/{f=1;next} f&&/^endef/{f=0} f{print}' "$MK" \
	| sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | head -n1)"

DEPS="$(sed -n 's/^[[:space:]]*DEPENDS:=//p' "$MK" | head -n1 | awk '
	{ for (i = 1; i <= NF; i++) {
		d = $i; sub(/^\+/, "", d); sub(/^@[^ ]*/, "", d)
		if (d != "") printf "%s%s", (n++ ? ", " : ""), d
	} }')"

[ -n "$PKG_NAME" ] && [ -n "$PKG_VERSION" ] || { echo "failed to parse PKG_NAME/PKG_VERSION" >&2; exit 1; }
VER="${PKG_VERSION}-r${PKG_RELEASE:-1}"
IPK="$OUT_DIR/${PKG_NAME}_${VER}_all.ipk"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ipk.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
DATA="$WORK/data"
CTRL="$WORK/control"
mkdir -p "$DATA" "$CTRL" "$OUT_DIR"

# --- data payload -----------------------------------------------------------
cp -R "$PKG_DIR/root/." "$DATA/"
# strip any macOS cruft that may have been copied in
find "$DATA" -name '.DS_Store' -o -name '._*' | xargs -r rm -f 2>/dev/null || true

# plugin_version file, as the package Makefile generates it
if [ -d "$DATA/usr/share/omnihive" ]; then
	printf '%s\n' "$PKG_VERSION" > "$DATA/usr/share/omnihive/plugin_version"
fi

# permissions: executables 0755, data 0644, dirs 0755  (mirrors INSTALL_BIN/INSTALL_DATA)
find "$DATA" -type d -exec chmod 0755 {} +
find "$DATA" -type f -exec chmod 0644 {} +
[ -f "$DATA/etc/init.d/omnihive" ]        && chmod 0755 "$DATA/etc/init.d/omnihive"
[ -d "$DATA/etc/uci-defaults" ]           && find "$DATA/etc/uci-defaults" -type f -exec chmod 0755 {} +
[ -d "$DATA/usr/share/omnihive" ]         && find "$DATA/usr/share/omnihive" -name '*.sh' -exec chmod 0755 {} +

INSTALLED_SIZE="$(find "$DATA" -type f -exec cat {} + | wc -c | tr -d ' ')"

# --- control --------------------------------------------------------------
cat > "$CTRL/control" <<EOF
Package: ${PKG_NAME}
Version: ${VER}
Depends: ${DEPS}
Source: package/${PKG_NAME}
SourceName: ${PKG_NAME}
License: ${PKG_LICENSE:-MIT}
Section: ${SECTION:-luci}
Maintainer: ${PKG_MAINTAINER:-OmniHive}
Architecture: all
Installed-Size: ${INSTALLED_SIZE}
Description: ${TITLE:-$PKG_NAME}
 ${DESC:-$TITLE}
EOF

# postinst: package Makefile's postinst body + run uci-defaults once (what the
# SDK build appends for packages shipping /etc/uci-defaults) + drop luci caches.
cat > "$CTRL/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	mkdir -p /etc/omnihive/bin /etc/omnihive/config /etc/omnihive/data /tmp/omnihive/logs /tmp/omnihive/download
	chmod 0755 /etc/init.d/omnihive /usr/share/omnihive/*.sh 2>/dev/null || true
	[ -f /etc/uci-defaults/omnihive ] && {
		( . /etc/uci-defaults/omnihive ) && rm -f /etc/uci-defaults/omnihive
	}
	if [ -x /etc/init.d/rpcd ]; then
		/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
	fi
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
}
exit 0
EOF
chmod 0755 "$CTRL/postinst"

# --- pack ---------------------------------------------------------------
printf '2.0\n' > "$WORK/debian-binary"

tar_reset() {  # $1=outfile  rest=paths (relative to -C dir)
	local out="$1"; shift
	if tar --version 2>/dev/null | grep -q 'GNU tar'; then
		tar --numeric-owner --owner=0 --group=0 -czf "$out" "$@"
	else
		tar --numeric-owner --uid 0 --gid 0 --uname '' --gname '' -czf "$out" "$@"
	fi
}

( cd "$CTRL" && tar_reset "$WORK/control.tar.gz" ./control ./postinst )
( cd "$DATA" && tar_reset "$WORK/data.tar.gz" ./ )

# Write a GNU-format `ar` archive by hand. macOS /usr/bin/ar emits BSD-style
# member headers that opkg rejects ("Malformed package file"); GNU ar uses a
# trailing '/' as the name terminator, which opkg's parser requires.
ar_add() {  # $1=archive  $2=member name  $3=source file
	local ar="$1" name="$2" src="$3" size
	size=$(wc -c < "$src" | tr -d ' ')
	printf '%-16s%-12u%-6u%-6u%-8s%-10u\140\n' "${name}/" 0 0 0 100644 "$size" >> "$ar"
	cat "$src" >> "$ar"
	[ $((size % 2)) -eq 0 ] || printf '\n' >> "$ar"
}

rm -f "$IPK"
printf '!<arch>\n' > "$IPK"
ar_add "$IPK" debian-binary  "$WORK/debian-binary"
ar_add "$IPK" control.tar.gz "$WORK/control.tar.gz"
ar_add "$IPK" data.tar.gz    "$WORK/data.tar.gz"

# --- report -----------------------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$IPK"); else SUM=$(shasum -a 256 "$IPK"); fi
echo "built:  $IPK"
echo "size:   $(wc -c < "$IPK" | tr -d ' ') bytes"
echo "sha256: ${SUM%% *}"
echo "ar:     $(ar t "$IPK" 2>/dev/null | tr '\n' ' ')"
echo
echo "install on router:"
echo "  scp '$IPK' root@ROUTER:/tmp/"
echo "  ssh root@ROUTER 'opkg install --force-reinstall /tmp/$(basename "$IPK")'"
