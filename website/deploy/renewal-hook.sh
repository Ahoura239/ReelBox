#!/bin/sh
set -eu
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/reelbox.dartty.top ]; then
    if systemctl is-active --quiet reelbox-web.service; then
        /usr/sbin/nginx -t -c /etc/reelbox/nginx.conf
        systemctl reload reelbox-web.service
    fi
fi
