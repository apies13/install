#!/bin/bash

# Ganti domain ini dengan domain kamu
DOMAIN="uptime.jartaseacloud.my.id"

echo "=============================="
echo "🚀 Installing Uptime Kuma..."
echo "📌 Domain: $DOMAIN"
echo "=============================="

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install Docker & Docker Compose
sudo apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx

# 3. Setup Uptime Kuma Directory
mkdir -p /opt/uptime-kuma && cd /opt/uptime-kuma

# 4. Create docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.3'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
EOF

# 5. Start Uptime Kuma
sudo docker-compose up -d

# 6. Configure NGINX reverse proxy
cat > /etc/nginx/sites-available/uptime-kuma <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Redirect root to /status/service
        rewrite ^/$ /status/service permanent;
    }
}
EOF

# Enable site config
ln -s /etc/nginx/sites-available/uptime-kuma /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# 7. Issue SSL via Certbot
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

# 8. Done
echo "✅ Uptime Kuma installed and accessible at: https://$DOMAIN/status/service"
