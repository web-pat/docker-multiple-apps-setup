#!/bin/sh
for f in /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf; do
    [ -f "$f" ] || continue
    sed -i '/^\s*allow\s\+127\.0\.0\.1\s*;/d' "$f"
    sed -i '/^\s*deny\s\+all\s*;/d' "$f"
done