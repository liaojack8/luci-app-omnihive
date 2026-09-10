#!/bin/sh

set -eu

. /usr/share/omnihive/lib.sh

BIN_DIR="/etc/omnihive/bin"
BIN="$BIN_DIR/omnihive"
VERSION_FILE="$BIN_DIR/version"
ARCH_FILE="$BIN_DIR/arch"
DOWNLOAD_DIR="/tmp/omnihive/download"

fail() {
	printf '{"ok":false,"message":"%s"}\n' "$(json_escape "$*")"
	exit 1
}

repo="$(github_repo_slug "$(uci_get release_repo "$DEFAULT_CORE_REPO")")"
version="${1:-}"
[ -n "$version" ] || version="$(uci_get version 'latest')"
[ -n "$version" ] || version="latest"
core_arch="$(uci_get core_arch '')"

validate_github_repo "$repo" || fail "Invalid GitHub repository: $repo"

asset_arch="$(resolve_asset_arch "$core_arch")" || fail "Unsupported configured architecture: $core_arch"

if [ "$version" = "latest" ] || [ "$version" = "stable" ]; then
	latest_json="$(curl -fsSL --show-error --connect-timeout 15 --retry 2 "https://api.github.com/repos/$repo/releases/latest")" || fail "Failed to query latest release"
	version="$(printf '%s' "$latest_json" | jsonfilter -e '@.tag_name' 2>/dev/null || true)"
	[ -n "$version" ] || fail "Failed to parse latest release"
fi

asset="omnihive_${version}_linux_${asset_arch}"
url="https://github.com/$repo/releases/download/$version/$asset"
downloaded="$DOWNLOAD_DIR/$asset"
was_running=0

mkdir -p "$BIN_DIR" "$DOWNLOAD_DIR"
rm -f "$downloaded"

curl -fsSL --show-error --connect-timeout 15 --retry 2 "$url" -o "$downloaded" || fail "Failed to download $url"
[ -s "$downloaded" ] || fail "Downloaded file is empty"
chmod +x "$downloaded"

if command -v file >/dev/null 2>&1; then
	file "$downloaded" | grep -Eq 'ELF|executable' || fail "Downloaded file is not an executable"
fi

/etc/init.d/omnihive running >/dev/null 2>&1 && was_running=1
[ "$was_running" = "0" ] || /etc/init.d/omnihive stop || true

cp -f "$downloaded" "$BIN"
chmod 0755 "$BIN"
printf '%s\n' "$version" > "$VERSION_FILE"
printf '%s\n' "$asset_arch" > "$ARCH_FILE"

if [ "$was_running" = "1" ]; then
	if ! /etc/init.d/omnihive start >/tmp/omnihive-start.log 2>&1; then
		fail "核心已安装但服务启动失败"
	fi
fi

rm -f "$downloaded" "$BIN_DIR/omnihive.bak"

printf '{"ok":true,"message":"已安装 OmniHive 核心 %s"}\n' "$(json_escape "$version")"
