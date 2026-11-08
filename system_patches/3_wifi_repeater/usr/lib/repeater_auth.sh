#!/bin/sh

AUTH_DB="/data/repeater_users.db"
AUTH_HTTPD_CONF="/data/repeater-httpd.conf"
HTTPD_BIN="/sbin/httpd"

auth_json_error() {
    CODE="$1"
    MESSAGE="$2"
    case "$CODE" in
        400) STATUS="400 Bad Request" ;;
        403) STATUS="403 Forbidden" ;;
        409) STATUS="409 Conflict" ;;
        *) STATUS="500 Internal Server Error" ;;
    esac
    printf 'Status: %s\r\nContent-Type: application/json\r\n\r\n' "$STATUS"
    printf '{"success":false,"error":"%s"}\n' "$MESSAGE"
    exit 0
}

auth_valid_username() {
    case "$1" in
        ""|*[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    [ "${#1}" -le 32 ]
}

auth_valid_password() {
    [ "${#1}" -ge 1 ] && [ "${#1}" -le 64 ] || return 1
    case "$1" in
        *'"'*|*'\'*|*'
'*) return 1 ;;
    esac
    printf '%s' "$1" | LC_ALL=C grep -q '^[ -~]*$'
}

auth_role() {
    [ -n "$REMOTE_USER" ] || return 1
    awk -F: -v user="$REMOTE_USER" '
        $1 == user {
            if ($2 == "readonly") print "user"
            else print $2
            exit
        }
    ' "$AUTH_DB" 2>/dev/null
}

auth_require_admin() {
    if [ "$(auth_role)" != "admin" ]; then
        auth_json_error 403 "Administrator access required"
    fi
}

auth_require_wifi() {
    case "$(auth_role)" in
        admin|user) ;;
        *) auth_json_error 403 "Wi-Fi account access required" ;;
    esac
}

auth_password_hash() {
    HASH=$("$HTTPD_BIN" -m "$1" 2>/dev/null) || return 1
    case "$HASH" in
        '$1$'*) ;;
        *) return 1 ;;
    esac
    printf '%s' "$HASH"
}

auth_write_httpd_conf() {
    AUTH_SOURCE_DB="$1"
    AUTH_DEST_CONF="$2"
    AUTH_CONF_TEMP="$AUTH_DEST_CONF.$$"
    umask 077
    : > "$AUTH_CONF_TEMP" || return 1

    while IFS=: read -r username role hash || [ -n "$username" ]; do
        [ -n "$username" ] || continue
        auth_valid_username "$username" || {
            rm -f "$AUTH_CONF_TEMP"
            return 1
        }
        case "$role" in
            admin|user|readonly) ;;
            *)
                rm -f "$AUTH_CONF_TEMP"
                return 1
                ;;
        esac
        case "$hash" in
            '$1$'*) ;;
            *)
                rm -f "$AUTH_CONF_TEMP"
                return 1
                ;;
        esac
        printf '/cgi-bin/save:%s:%s\n/cgi-bin/users:%s:%s\n/cgi-bin/reboot:%s:%s\n/cgi-bin/scan:%s:%s\n' \
            "$username" "$hash" "$username" "$hash" "$username" "$hash" "$username" "$hash" >> "$AUTH_CONF_TEMP" || {
            rm -f "$AUTH_CONF_TEMP"
            return 1
        }
    done < "$AUTH_SOURCE_DB"

    [ -s "$AUTH_CONF_TEMP" ] || {
        rm -f "$AUTH_CONF_TEMP"
        return 1
    }
    chmod 600 "$AUTH_CONF_TEMP" && mv "$AUTH_CONF_TEMP" "$AUTH_DEST_CONF"
}

auth_init() {
    umask 077
    mkdir -p "$(dirname "$AUTH_DB")" || return 1
    if [ ! -f "$AUTH_DB" ]; then
        : > "$AUTH_DB" || return 1
    fi
    for DEFAULT_USER in admin user; do
        if ! awk -F: -v user="$DEFAULT_USER" '$1 == user { found=1 } END { exit !found }' "$AUTH_DB"; then
            HASH=$(auth_password_hash "$DEFAULT_USER") || return 1
            TEMP_DB="$AUTH_DB.$$"
            cat "$AUTH_DB" > "$TEMP_DB" || return 1
            printf '%s:%s:%s\n' "$DEFAULT_USER" "$DEFAULT_USER" "$HASH" >> "$TEMP_DB" || return 1
            chmod 600 "$TEMP_DB" && mv "$TEMP_DB" "$AUTH_DB" || return 1
        fi
    done
    auth_write_httpd_conf "$AUTH_DB" "$AUTH_HTTPD_CONF"
}

case "$1" in
    init)
        auth_init
        ;;
esac
