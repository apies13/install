#!/bin/bash

# Domain yang digunakan waktu instalasi
DOMAIN="uptime.jartaseacloud.my.id"

echo "=============================="
echo "🗑️  Uninstalling Uptime Kuma..."
echo "📌 Domain: $DOMAIN"
echo "=============================="

# 1. Stop & Remove Docker Container & Image
echo "⏹️  Stopping and removing Docker container..."
sudo docker-compose -f /opt/uptime-kuma/docker-compose.yml down
sudo docker rm -f uptime-kuma 2>/dev/null
sudo docker rmi louislam/uptime-kuma:1 2>/dev/null

# 2. Remove data directory
echo "🧹 Removing data directory..."
sudo rm -rf /opt/uptime-kuma

# 3. Remove Nginx config
echo "🗑️  Removing Nginx configuration..."
sudo rm -f /etc/nginx/sites-enabled/uptime-kuma
sudo rm -f /etc/nginx/sites-available/uptime-kuma
sudo nginx -t && sudo systemctl restart nginx

# 4. Remove SSL certificate
echo "🔒 Deleting SSL certificate..."
sudo certbot delete --cert-name $DOMAIN --non-interactive

# 5. Done
echo "✅ Uptime Kuma uninstalled successfully."
