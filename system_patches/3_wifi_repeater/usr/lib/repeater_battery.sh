#!/bin/sh

repeater_battery_read() {
    BATT_LEVEL=""
    BATT_STATUS=""

    RESULT=$(cat /sys/devices/qpnp-vadc-8/vbatt 2>/dev/null | grep -o 'Result:[0-9]*' | cut -d: -f2)
    if [ -n "$RESULT" ]; then
        VOLTAGE=$((RESULT * 3 / 1000))
        if [ "$VOLTAGE" -lt 2000 ]; then
            BATT_LEVEL=0
            BATT_STATUS="No Battery (USB Powered)"
            return
        elif [ "$VOLTAGE" -ge 4200 ]; then
            BATT_LEVEL=100
        elif [ "$VOLTAGE" -le 3400 ]; then
            BATT_LEVEL=0
        else
            BATT_LEVEL=$(((VOLTAGE - 3400) * 100 / 800))
        fi
    fi

    CHARGER_STATUS=$(cat /sys/class/power_supply/sy6923-charger/status 2>/dev/null | tr '[:upper:]' '[:lower:]')
    USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
    if [ -z "$USB_ONLINE" ]; then
        USB_ONLINE=$(cat /sys/class/power_supply/sy6923-charger/online 2>/dev/null)
    fi

    case "$CHARGER_STATUS" in
        charging)
            BATT_STATUS="Charging"
            ;;
        full)
            BATT_STATUS="Full"
            ;;
        discharging|"not charging"|unknown|"")
            if [ "$USB_ONLINE" = "1" ]; then
                if [ -n "$BATT_LEVEL" ] && [ "$BATT_LEVEL" -ge 95 ]; then
                    BATT_STATUS="Full"
                else
                    BATT_STATUS="Charging"
                fi
            else
                BATT_STATUS="Discharging"
            fi
            ;;
        *)
            if [ "$USB_ONLINE" = "1" ]; then
                BATT_STATUS="Charging"
            else
                BATT_STATUS="$CHARGER_STATUS"
            fi
            ;;
    esac
}

repeater_battery_led_state() {
    STATUS="$1"
    LEVEL="$2"
    if [ "$STATUS" = "No Battery (USB Powered)" ]; then
        echo off
        return
    fi

    case "$LEVEL" in
        ""|*[!0-9]*) COLOR=green ;;
        *)
            if [ "$LEVEL" -lt 20 ]; then
                COLOR=red
            elif [ "$LEVEL" -lt 40 ]; then
                COLOR=amber
            else
                COLOR=green
            fi
            ;;
    esac
    echo "$STATUS:$COLOR"
}

repeater_battery_set_led_channel() {
    LED="$1"
    ENABLED="$2"
    CHARGING="$3"
    [ -d "/sys/class/leds/$LED" ] || return 0

    echo none > "/sys/class/leds/$LED/trigger" 2>/dev/null
    if [ "$ENABLED" = "1" ]; then
        LED_MAX=$(cat "/sys/class/leds/$LED/max_brightness" 2>/dev/null)
        case "$LED_MAX" in
            ""|*[!0-9]*) LED_MAX=1 ;;
        esac
        echo "$LED_MAX" > "/sys/class/leds/$LED/brightness" 2>/dev/null
        if [ "$CHARGING" = "1" ]; then
            echo 500 > "/sys/class/leds/$LED/delay_on" 2>/dev/null
            echo 500 > "/sys/class/leds/$LED/delay_off" 2>/dev/null
            echo timer > "/sys/class/leds/$LED/trigger" 2>/dev/null
        fi
    else
        echo 0 > "/sys/class/leds/$LED/brightness" 2>/dev/null
    fi
}

repeater_battery_set_power_led() {
    STATUS="$1"
    LEVEL="$2"
    ENABLED="${3:-1}"
    [ -d /sys/class/leds/pwr_r ] || return 0

    if [ "$ENABLED" != "1" ] || [ "$STATUS" = "No Battery (USB Powered)" ]; then
        RED=0
        GREEN=0
        BLUE=0
        CHARGING=0
    else
        case "$LEVEL" in
            ""|*[!0-9]*) COLOR=green ;;
            *)
                if [ "$LEVEL" -lt 20 ]; then
                    COLOR=red
                elif [ "$LEVEL" -lt 40 ]; then
                    COLOR=amber
                else
                    COLOR=green
                fi
                ;;
        esac
        RED=0
        GREEN=0
        BLUE=0
        case "$COLOR" in
            red) RED=1 ;;
            amber) RED=1; GREEN=1 ;;
            green) GREEN=1 ;;
        esac
        CHARGING=0
        [ "$STATUS" = "Charging" ] && CHARGING=1
    fi

    repeater_battery_set_led_channel pwr_r "$RED" "$CHARGING"
    repeater_battery_set_led_channel pwr_g "$GREEN" "$CHARGING"
    repeater_battery_set_led_channel pwr_b "$BLUE" "$CHARGING"
}
