#!/bin/sh
# network_setup.sh — OmniHive network management actions
#
# Usage:
#   network_setup.sh setup     Create network.omnihive + add to wan zone (router config only)
#   network_setup.sh restore   Remove network.omnihive + firewall config (router config only)
#   network_setup.sh enable    Enable OmniHive network via API only (no router config changes)
#   network_setup.sh disable   Disable OmniHive network via API only (no router config changes)
#   network_setup.sh set_metric <value>  Set route metric for network.omnihive interface

set -eu

. /usr/share/omnihive/lib.sh

ACTION="${1:-}"

PORT="$(uci_get port '7575')"
USERNAME="$(uci_get username 'admin')"
PASSWORD="$(uci_get password 'admin')"

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/	/\\t/g'
}

result_ok() {
	printf '{"ok":true,"message":"%s"}\n' "$(json_escape "$1")"
}

result_fail() {
	printf '{"ok":false,"message":"%s"}\n' "$(json_escape "$1")"
	exit 1
}

# ---------------------------------------------------------------------------
# Get auth token (single login per script invocation)
# ---------------------------------------------------------------------------
OMNIHIVE_TOKEN=""

get_token() {
	if ! /etc/init.d/omnihive running >/dev/null 2>&1; then
		return 1
	fi
	OMNIHIVE_TOKEN="$(curl -s --connect-timeout 3 "http://127.0.0.1:${PORT}/api/auth/login" \
		-X POST -H 'Content-Type: application/json' \
		-d '{"username":"'"$USERNAME"'","password":"'"$PASSWORD"'"}' \
		2>/dev/null | jsonfilter -e '@.token' 2>/dev/null || true)"
	[ -n "$OMNIHIVE_TOKEN" ] || return 1
	return 0
}

# ---------------------------------------------------------------------------
# Get device info using cached token
# ---------------------------------------------------------------------------
get_device_info() {
	local data dev_id iface

	[ -n "$OMNIHIVE_TOKEN" ] || return 1

	data="$(curl -s --connect-timeout 3 "http://127.0.0.1:${PORT}/api/devices" \
		-H "Authorization: Bearer $OMNIHIVE_TOKEN" 2>/dev/null || true)"

	dev_id="$(printf '%s' "$data" | jsonfilter -e '@.devices[0].id' 2>/dev/null || true)"
	iface="$(printf '%s' "$data" | jsonfilter -e '@.devices[0].interface' 2>/dev/null || true)"

	printf '%s %s' "$dev_id" "$iface"
}

# ---------------------------------------------------------------------------
# Enable/disable OmniHive network via API (uses cached token)
# ---------------------------------------------------------------------------
network_control() {
	local dev_id="$1"
	local enabled="$2"

	[ -n "$OMNIHIVE_TOKEN" ] || return 1

	curl -s --connect-timeout 5 "http://127.0.0.1:${PORT}/api/devices/${dev_id}/network" \
		-X PATCH -H 'Content-Type: application/json' \
		-H "Authorization: Bearer $OMNIHIVE_TOKEN" \
		-d '{"enabled":'"$enabled"'}' \
		2>/dev/null | jsonfilter -e '@.status' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Router config helpers
# ---------------------------------------------------------------------------
get_wwan_iface() {
	local info dev_id iface

	info="$(get_device_info 2>/dev/null || true)"
	dev_id="${info%% *}"
	iface="${info#* }"
	[ -n "$iface" ] && [ "$iface" != "$dev_id" ] && { printf '%s' "$iface"; return 0; }

	for net in /sys/class/net/wwan*/; do
		[ -d "$net" ] || continue
		printf '%s' "$(basename "$net")"
		return 0
	done
	return 1
}

find_wan_zone_idx() {
	local i=0 name
	while true; do
		name="$(uci -q get "firewall.@zone[$i].name" 2>/dev/null || true)"
		[ -n "$name" ] || break
		[ "$name" = "wan" ] && { printf '%s' "$i"; return 0; }
		i=$((i + 1))
	done
	return 1
}

in_zone_networks() {
	local idx="$1"
	local current_networks net

	current_networks="$(uci -q get "firewall.@zone[$idx].network" 2>/dev/null || true)"
	for net in $current_networks; do
		[ "$net" = "omnihive" ] && return 0
	done
	return 1
}

# ---------------------------------------------------------------------------
# Setup: create network.omnihive + add to wan zone (router config only)
# ---------------------------------------------------------------------------
do_setup() {
	local info dev_id wwan_iface wan_idx

	get_token || result_fail "OmniHive 服务未运行或认证失败"

	info="$(get_device_info 2>/dev/null || true)"
	dev_id="${info%% *}"
	wwan_iface="${info#* }"
	[ -n "$wwan_iface" ] && [ "$wwan_iface" != "$dev_id" ] || wwan_iface=""
	[ -n "$wwan_iface" ] || wwan_iface="$(get_wwan_iface)" || result_fail "未找到 OmniHive 管理的网络接口（wwan*）"
	wan_idx="$(find_wan_zone_idx)" || result_fail "未找到防火墙 wan 区域"

	uci set network.omnihive=interface
	uci set network.omnihive.proto='none'
	uci set network.omnihive.device="$wwan_iface"
	uci commit network

	if ! in_zone_networks "$wan_idx"; then
		uci add_list firewall.@zone[$wan_idx].network=omnihive
		uci commit firewall
	fi

	/etc/init.d/network reload 2>/dev/null || true
	/etc/init.d/firewall reload 2>/dev/null || true

	result_ok "路由器配置已完成（接口 $wwan_iface 已加入防火墙 wan 域）"
}

# ---------------------------------------------------------------------------
# Restore: remove network.omnihive + firewall config (router config only)
# ---------------------------------------------------------------------------
do_restore() {
	local wan_idx

	wan_idx="$(find_wan_zone_idx 2>/dev/null || true)"

	if [ -n "$wan_idx" ]; then
		if in_zone_networks "$wan_idx"; then
			uci del_list firewall.@zone[$wan_idx].network=omnihive 2>/dev/null || true
			uci commit firewall
		fi
	fi

	if uci -q get network.omnihive >/dev/null 2>&1; then
		uci delete network.omnihive
		uci commit network
	fi

	/etc/init.d/network reload 2>/dev/null || true
	/etc/init.d/firewall reload 2>/dev/null || true

	result_ok "已撤销配置（已移除网络接口和防火墙配置，恢复原始状态）"
}

# ---------------------------------------------------------------------------
# Enable: enable OmniHive network via API only
# ---------------------------------------------------------------------------
do_enable() {
	local info dev_id

	get_token || result_fail "OmniHive 服务未运行或认证失败"

	info="$(get_device_info 2>/dev/null || true)"
	dev_id="${info%% *}"

	if [ -n "$dev_id" ] && [ "$dev_id" != "" ]; then
		network_control "$dev_id" true >/dev/null 2>&1 || true
		sleep 3
		result_ok "已启用网络"
	else
		result_fail "无法获取 OmniHive 设备信息"
	fi
}

# ---------------------------------------------------------------------------
# Disable: disable OmniHive network via API only
# ---------------------------------------------------------------------------
do_disable() {
	local info dev_id

	get_token || result_fail "OmniHive 服务未运行或认证失败"

	info="$(get_device_info 2>/dev/null || true)"
	dev_id="${info%% *}"

	if [ -n "$dev_id" ] && [ "$dev_id" != "" ]; then
		network_control "$dev_id" false >/dev/null 2>&1 || true
		sleep 1
		result_ok "已禁用网络"
	else
		result_fail "无法获取 OmniHive 设备信息"
	fi
}

# ---------------------------------------------------------------------------
# Set route priority: adjust other WAN interfaces' metric relative to cellular
#
# The cellular route metric (5000) is set by the QMI library and cannot be
# changed via UCI.  Instead we toggle the metric of OTHER WAN interfaces:
#   primary: set other WAN metric > 5000  → cellular wins
#   backup:  set other WAN metric = 0     → other WAN wins
#   custom:  set other WAN metric = <value>
# ---------------------------------------------------------------------------
do_set_metric() {
	local mode="${1:-}"

	uci -q get network.omnihive >/dev/null 2>&1 || result_fail "network.omnihive 接口未创建，请先一键配置"

	local other_metric=""
	case "$mode" in
		primary) other_metric="5001" ;;
		backup)  other_metric="0" ;;
		*[!0-9]*|'') result_fail "无效的模式: $mode（可用: primary | backup | 0-65535）" ;;
		*) [ "$mode" -ge 0 ] && [ "$mode" -le 65535 ] || result_fail "metric 范围: 0-65535"; other_metric="$mode" ;;
	esac

	# Find all networks in the wan firewall zone except omnihive
	local wan_idx wan_networks net changed=0
	wan_idx="$(find_wan_zone_idx 2>/dev/null || true)"
	[ -n "$wan_idx" ] || result_fail "未找到防火墙 wan 区域"

	wan_networks="$(uci -q get "firewall.@zone[$wan_idx].network" 2>/dev/null || true)"
	[ -n "$wan_networks" ] || result_fail "wan 区域中没有网络接口"

	for net in $wan_networks; do
		[ "$net" = "omnihive" ] && continue
		uci -q get "network.$net" >/dev/null 2>&1 || continue
		uci set "network.$net.metric=$other_metric"
		changed=1
	done

	[ "$changed" = "1" ] || result_fail "未找到可调整的 WAN 接口"

	uci commit network
	/etc/init.d/network reload 2>/dev/null || true

	case "$mode" in
		primary) result_ok "路由优先级已设为主力（4G/5G 优先，其他 WAN metric=$other_metric）" ;;
		backup)  result_ok "路由优先级已设为备用（其他 WAN 优先，metric=0）" ;;
		*)       result_ok "其他 WAN 接口 metric 已设为 $other_metric" ;;
	esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$ACTION" in
	setup)
		do_setup
		;;
	restore)
		do_restore
		;;
	enable)
		do_enable
		;;
	disable)
		do_disable
		;;
	set_metric)
		do_set_metric "${2:-}"
		;;
	*)
		result_fail "用法: network_setup.sh <setup|restore|enable|disable|set_metric> [value]"
		;;
esac
