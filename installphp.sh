#!/bin/bash

# Warna
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
clear
echo -e "${CYAN}"
echo "=================================================="
echo "          🚀 AUTO INSTALL PHPMYADMIN v5.2.1       "
echo "           by Sunda Cloud - Bash Script          "
echo "=================================================="
echo -e "${NC}"

# Prompt Input
read -p "🌐 Masukkan domain phpMyAdmin (contoh: php.sundacloud.com): " DOMAIN
read -p "👤 Masukkan username database MySQL: " DBUSER
read -p "🔑 Masukkan password untuk user MySQL [$DBUSER]: " DBPASS

echo -e "\n${YELLOW}========================================"
echo "🔧 Mulai Proses Instalasi phpMyAdmin..."
echo "🌐 Domain     : $DOMAIN"
echo "👤 DB User    : $DBUSER"
echo "🔐 DB Password: $DBPASS"
echo "========================================${NC}\n"
sleep 2

# Step 1: Update dan Install Paket
echo -e "${CYAN}📦 Menginstal dependensi...${NC}"
sudo apt update
sudo apt install -y wget unzip nginx php php-fpm php-mysql mariadb-server certbot > /dev/null

# Step 2: Unduh dan Ekstrak phpMyAdmin
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

# Step 4: Sertifikat SSL
echo -e "${CYAN}🔐 Mengaktifkan SSL untuk $DOMAIN...${NC}"
sudo certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN

# Step 5: Konfigurasi NGINX
echo -e "${CYAN}📁 Membuat konfigurasi NGINX...${NC}"
NGINX_CONF="/etc/nginx/sites-available/phpmyadmin.conf"

sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    root /var/www/phpmyadmin;
    index index.php;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/ > /dev/null
sudo nginx -t && sudo systemctl restart nginx

# Step 6: Setup Database
echo -e "${CYAN}🗄️  Konfigurasi MySQL...${NC}"
sudo mysql -u root <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '$DBUSER'@'%' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON *.* TO '$DBUSER'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Step 7: Remote Access MySQL
echo -e "${CYAN}🔓 Membuka akses remote MySQL...${NC}"
sudo sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mysql mariadb

# DONE
echo -e "\n${GREEN}✅ Instalasi Selesai!${NC}"
echo -e "🌐 Akses phpMyAdmin: ${CYAN}https://$DOMAIN${NC}"
echo -e "👤 Username MySQL  : ${YELLOW}$DBUSER${NC}"
echo -e "🔐 Password MySQL  : ${YELLOW}$DBPASS${NC}"
echo ""
