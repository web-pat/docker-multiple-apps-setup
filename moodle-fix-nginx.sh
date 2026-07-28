#!/bin/sh
for f in /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf; do
    [ -f "$f" ] || continue
    sed -i '/^\s*allow\s\+127\.0\.0\.1\s*;/d' "$f"
    sed -i '/^\s*deny\s\+all\s*;/d' "$f"
done

CONFIG_PHP="/var/www/html/config.php"
if [ -f "$CONFIG_PHP" ]; then
    if ! grep -q "trustedproxies" "$CONFIG_PHP"; then
        sed -i '/$CFG->reverseproxy/a $CFG->trustedproxies = '"'"'127.0.0.1, 172.0.0.0/8'"'"';' "$CONFIG_PHP"
    fi
fi
