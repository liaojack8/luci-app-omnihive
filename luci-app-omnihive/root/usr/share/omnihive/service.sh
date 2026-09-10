#!/bin/sh

set -eu

action="${1:-}"

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

run_action() {
	case "$action" in
		start)
			[ -x /etc/omnihive/bin/omnihive ] || {
				printf '%s\n' "OmniHive core is not installed"
				return 1
			}
			/usr/share/omnihive/render_config.sh
			uci set omnihive.main.enabled='1'
			uci commit omnihive
			/etc/init.d/omnihive enable
			/etc/init.d/omnihive start
			;;
		stop)
			uci set omnihive.main.enabled='0'
			uci commit omnihive
			/etc/init.d/omnihive stop || true
			/etc/init.d/omnihive disable
			;;
		restart)
			/usr/share/omnihive/render_config.sh
			/etc/init.d/omnihive restart
			;;
		*)
			printf '{"ok":false,"message":"Unsupported service action"}\n'
			exit 1
			;;
	esac
}

output="$(run_action 2>&1)" || {
	printf '{"ok":false,"message":"%s"}\n' "$(json_escape "$output")"
	exit 1
}

printf '{"ok":true,"message":"%s"}\n' "$(json_escape "$output")"
