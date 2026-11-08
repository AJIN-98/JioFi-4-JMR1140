#!/bin/sh

REPEATER_OPTIONS_FILE="/data/repeater-options.conf"

repeater_option_value() {
    OPTION_NAME="$1"
    OPTION_DEFAULT="$2"
    OPTION_VALUE=$(sed -n "s/^${OPTION_NAME}=//p" "$REPEATER_OPTIONS_FILE" 2>/dev/null | head -n 1)
    [ -n "$OPTION_VALUE" ] || OPTION_VALUE="$OPTION_DEFAULT"
    printf '%s' "$OPTION_VALUE"
}

repeater_valid_ipv4() {
    printf '%s\n' "$1" | awk -F. '
        NF != 4 { bad = 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || length($i) > 3 || $i > 255) {
                    bad = 1
                }
            }
        }
        END { exit bad }
    '
}

repeater_load_options() {
    DNS_SERVER=$(repeater_option_value dns_server 8.8.8.8)
    POWER_LED=$(repeater_option_value power_led 1)
    WIFI_LED=$(repeater_option_value wifi_led 1)
    RSSI_LED=$(repeater_option_value rssi_led 1)
    POWER_SAVE=$(repeater_option_value power_save 0)

    repeater_valid_ipv4 "$DNS_SERVER" || DNS_SERVER=8.8.8.8
    case "$POWER_LED" in 0|1) ;; *) POWER_LED=1 ;; esac
    case "$WIFI_LED" in 0|1) ;; *) WIFI_LED=1 ;; esac
    case "$RSSI_LED" in 0|1) ;; *) RSSI_LED=1 ;; esac
    case "$POWER_SAVE" in 0|1) ;; *) POWER_SAVE=0 ;; esac
}
