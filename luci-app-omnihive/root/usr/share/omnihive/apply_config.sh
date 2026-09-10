#!/bin/sh

set -eu

/usr/share/omnihive/render_config.sh

if /etc/init.d/omnihive running >/dev/null 2>&1; then
	/etc/init.d/omnihive restart
fi

printf '{"ok":true,"message":"配置已保存"}\n'
