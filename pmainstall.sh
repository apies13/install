#!/bin/bash

# Warna
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Banner
clear
echo -e "${CYAN}"
echo "=================================================="
echo "      🚀 AUTO INSTALL PHPMYADMIN v5.2.1 (SSL)     "
echo "       by Sunda Cloud - Bash Script (Modified)   "
echo "=================================================="
echo -e "${NC}"

# Prompt Input
read -p "🌐 Domain phpMyAdmin (ex: php.domain.com): " DOMAIN
read -p "👤 MySQL Username: " DBUSER
read -sp "🔑 MySQL Password: " DBPASS
echo ""

echo -e "\n${YELLOW}========================================"
echo "🔧 Mulai Proses Instalasi phpMyAdmin..."
echo "🌐 Domain     : $DOMAIN"
echo "👤 DB User    : $DBUSER"
echo "🔐 DB Password: **********"
echo "========================================${NC}\n"
sleep 2

# Step 1: Install packages
echo -e "${CYAN}📦 Menginstal dependensi...${NC}"
sudo apt update
sudo apt install -y wget unzip nginx php php-fpm php-mysql mariadb-server unzip software-properties-common > /dev/null

# Step 2: Unduh phpMyAdmin
echo -e "${CYAN}📥 Mengunduh phpMyAdmin...${NC}"
wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
unzip -q phpMyAdmin-5.2.1-all-languages.zip
sudo mkdir -p /var/www/phpmyadmin
sudo mv phpMyAdmin-5.2.1-all-languages/* /var/www/phpmyadmin
rm -rf phpMyAdmin-5.2.1-all-languages*

# Step 3: Konfigurasi phpMyAdmin
echo -e "${CYAN}⚙️  Konfigurasi phpMyAdmin...${NC}"
cd /var/www/phpmyadmin
cp config.sample.inc.php config.inc.php
BLOWFISH=$(openssl rand -base64 32)
sed -i "s|\['blowfish_secret'\] = ''|['blowfish_secret'] = '$BLOWFISH'|g" config.inc.php
echo "\$cfg['TempDir'] = '/tmp';" >> config.inc.php

sudo chown -R www-data:www-data /var/www/phpmyadmin

# Step 4: Konfigurasi NGINX tanpa SSL (sementara)
echo -e "${CYAN}📁 Menyiapkan konfigurasi NGINX awal (HTTP)...${NC}"
cat <<EOF | sudo tee /etc/nginx/sites-available/phpmyadmin.conf > /dev/null
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/phpmyadmin;
    index index.php;

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

# Step 5: Install Certbot & dapatkan SSL cert
echo -e "${CYAN}🔐 Menginstal Certbot dan mendapatkan SSL certificate...${NC}"
sudo apt install -y certbot python3-certbot-nginx > /dev/null

sudo certbot --nginx --non-interactive --agree-tos -m admin@$DOMAIN -d $DOMAIN --redirect
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Gagal mendapatkan sertifikat SSL. Periksa domain dan konfigurasi DNS.${NC}"
    exit 1
fi

# Step 6: MySQL Config
echo -e "${CYAN}🗄️  Membuat user MySQL...${NC}"
sudo mysql -u root <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '$DBUSER'@'%' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON *.* TO '$DBUSER'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Step 7: Enable remote MySQL
echo -e "${CYAN}🔓 Mengaktifkan remote MySQL...${NC}"
sudo sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb

# Done
echo -e "\n${GREEN}✅ phpMyAdmin berhasil diinstall dengan SSL!${NC}"
echo -e "🌐 URL: ${CYAN}https://$DOMAIN${NC} (akses melalui HTTPS)"
echo -e "👤 MySQL User: ${YELLOW}$DBUSER${NC}"
echo -e "🔐 Password  : ${YELLOW}$DBPASS${NC}"
echo -e "\n🔔 Jangan lupa buka port 80 dan 443 di firewall kamu jika ada."

