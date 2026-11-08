#!/bin/sh

EVENT="$1"
if [ "$EVENT" = "bound" ] || [ "$EVENT" = "renew" ]; then
    . /usr/lib/repeater_options.sh
    repeater_load_options
    dns="$DNS_SERVER"
    export dns
fi

exec /etc/udhcpc.d/50default "$@"
