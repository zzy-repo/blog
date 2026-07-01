#!/usr/bin/env bash

set -euo pipefail

: "${DEPLOY_PATH:?DEPLOY_PATH is required}"
: "${BLOG_DOMAIN:?BLOG_DOMAIN is required}"
: "${BLOG_UPSTREAM_PORT:?BLOG_UPSTREAM_PORT is required}"

NGINX_AVAILABLE_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
MANAGED_CONF="$NGINX_AVAILABLE_DIR/${BLOG_DOMAIN}.conf"
ENABLED_CONF="$NGINX_ENABLED_DIR/${BLOG_DOMAIN}.conf"

install -d -m 755 "$NGINX_AVAILABLE_DIR" "$NGINX_ENABLED_DIR"

cat >"$MANAGED_CONF" <<EOF
# Managed by blog deploy workflow.
server {
    listen 127.0.0.1:${BLOG_UPSTREAM_PORT};
    server_name _;

    root ${DEPLOY_PATH}/current;
    index index.html;

    location / {
        try_files \$uri \$uri/ \$uri.html =404;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${BLOG_DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${BLOG_UPSTREAM_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sfn "$MANAGED_CONF" "$ENABLED_CONF"

nginx -t
systemctl reload nginx
