#!/bin/bash

# ========== Warna ==========
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ========== Banner ==========
clear
echo -e "${CYAN}"
echo "=================================================="
echo "          🚀 AUTO INSTALL PHPMYADMIN v5.2.1       "
echo "           by Sunda Cloud - Bash Script          "
echo "=================================================="
echo -e "${NC}"

# ========== Input ==========
read -p "🌐 Domain untuk phpMyAdmin (contoh: php.domainmu.com): " DOMAIN
read -p "👤 Username database MySQL: " DBUSER
read -sp "🔑 Password untuk user [$DBUSER]: " DBPASS
echo ""

# ========== Konfirmasi ==========
echo -e "\n${YELLOW}========================================"
echo "🔧 Mulai Proses Instalasi phpMyAdmin..."
echo "🌐 Domain     : $DOMAIN"
echo "👤 DB User    : $DBUSER"
echo "🔐 DB Password: **********"
echo "========================================${NC}\n"
sleep 2

# ========== Update dan Install ==========
echo -e "${CYAN}📦 Menginstal dependensi...${NC}"
sudo apt update && sudo apt install -y wget unzip nginx php php-fpm php-mysql mariadb-server certbot python3-certbot-nginx unzip > /dev/null

# ========== Unduh phpMyAdmin ==========
echo -e "${CYAN}📥 Mengunduh phpMyAdmin...${NC}"
wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
unzip -q phpMyAdmin-5.2.1-all-languages.zip
sudo mkdir -p /var/www/phpmyadmin
sudo mv phpMyAdmin-5.2.1-all-languages/* /var/www/phpmyadmin
rm -rf phpMyAdmin-5.2.1-all-languages*

# ========== Konfigurasi phpMyAdmin ==========
echo -e "${CYAN}⚙️  Konfigurasi phpMyAdmin...${NC}"
cd /var/www/phpmyadmin
cp config.sample.inc.php config.inc.php
BLOWFISH=$(openssl rand -base64 32)
sed -i "s|\['blowfish_secret'\] = ''|['blowfish_secret'] = '$BLOWFISH'|g" config.inc.php
echo "\$cfg['TempDir'] = '/tmp';" >> config.inc.php

# ========== Konfigurasi NGINX ==========
echo -e "${CYAN}📁 Menyiapkan konfigurasi NGINX...${NC}"
cat <<EOF | sudo tee /etc/nginx/sites-available/phpmyadmin.conf > /dev/null
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    root /var/www/phpmyadmin;
    index index.php;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 100m;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# ========== SSL Let's Encrypt ==========
echo -e "${CYAN}🔐 Mengaktifkan SSL...${NC}"
sudo certbot --nginx --non-interactive --agree-tos -m admin@$DOMAIN -d $DOMAIN

# ========== Konfigurasi Database ==========
echo -e "${CYAN}🗄️  Membuat user MySQL...${NC}"
sudo mysql -u root <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '$DBUSER'@'%' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON *.* TO '$DBUSER'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# ========== Remote Access ==========
echo -e "${CYAN}🔓 Mengaktifkan akses remote MySQL...${NC}"
sudo sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb

# ========== Selesai ==========
echo -e "\n${GREEN}✅ Instalasi phpMyAdmin selesai!${NC}"
echo -e "🌐 Akses phpMyAdmin : ${CYAN}https://$DOMAIN${NC}"
echo -e "👤 Username MySQL   : ${YELLOW}$DBUSER${NC}"
echo -e "🔐 Password MySQL   : ${YELLOW}$DBPASS${NC}"
