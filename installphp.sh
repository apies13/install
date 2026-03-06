#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PHPMYADMIN_VERSION="5.2.1"
INSTALL_DIR="/var/www/phpmyadmin"
NGINX_CONF="/etc/nginx/sites-available/phpmyadmin.conf"
NGINX_LINK="/etc/nginx/sites-enabled/phpmyadmin.conf"

clear
echo -e "${CYAN}"
echo "=================================================="
echo "      AUTO INSTALL PHPMYADMIN v${PHPMYADMIN_VERSION} - FIXED     "
echo "=================================================="
echo -e "${NC}"

read -r -p "Domain phpMyAdmin (contoh: pma.domain.com): " DOMAIN
read -r -p "MySQL Username: " DBUSER
read -r -s -p "MySQL Password: " DBPASS
echo ""
read -r -p "Email Let's Encrypt: " LE_EMAIL

if [[ -z "${DOMAIN}" || -z "${DBUSER}" || -z "${DBPASS}" || -z "${LE_EMAIL}" ]]; then
    echo -e "${RED}Input gak boleh kosong.${NC}"
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo -e "${RED}sudo gak ada. jalanin sebagai root atau install sudo dulu.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}========================================"
echo "Mulai proses install phpMyAdmin..."
echo "Domain     : ${DOMAIN}"
echo "DB User    : ${DBUSER}"
echo "DB Password: **********"
echo "LE Email   : ${LE_EMAIL}"
echo -e "========================================${NC}\n"

echo -e "${CYAN}1. Install dependensi...${NC}"
sudo apt update
sudo apt install -y nginx mariadb-server certbot python3-certbot-nginx wget unzip curl rsync software-properties-common ca-certificates lsb-release apt-transport-https

if ! php -v >/dev/null 2>&1; then
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update
fi

sudo apt install -y php8.3 php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml php8.3-zip php8.3-curl php8.3-gd php8.3-intl

echo -e "${CYAN}2. Aktifkan service...${NC}"
sudo systemctl enable nginx
sudo systemctl enable mariadb
sudo systemctl enable php8.3-fpm
sudo systemctl start nginx
sudo systemctl start mariadb
sudo systemctl start php8.3-fpm

echo -e "${CYAN}3. Download phpMyAdmin...${NC}"
TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip" -O phpmyadmin.zip
unzip -q phpmyadmin.zip

sudo mkdir -p "${INSTALL_DIR}"
sudo rm -rf "${INSTALL_DIR:?}/"*
sudo rsync -a "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages/" "${INSTALL_DIR}/"

rm -rf "$TMP_DIR"

echo -e "${CYAN}4. Konfigurasi phpMyAdmin...${NC}"
cd "${INSTALL_DIR}"
sudo cp -f config.sample.inc.php config.inc.php
BLOWFISH="$(openssl rand -base64 32 | tr -d '\n')"
sudo sed -i "s|\['blowfish_secret'\] = ''|['blowfish_secret'] = '${BLOWFISH}'|g" config.inc.php

if ! grep -q "TempDir" config.inc.php; then
    echo "\$cfg['TempDir'] = '/tmp';" | sudo tee -a config.inc.php >/dev/null
fi

sudo chown -R www-data:www-data "${INSTALL_DIR}"
sudo find "${INSTALL_DIR}" -type d -exec chmod 755 {} \;
sudo find "${INSTALL_DIR}" -type f -exec chmod 644 {} \;

echo -e "${CYAN}5. Buat nginx config HTTP dulu...${NC}"
cat <<EOF | sudo tee "${NGINX_CONF}" >/dev/null
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${INSTALL_DIR};
    index index.php index.html index.htm;

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
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sudo ln -sf "${NGINX_CONF}" "${NGINX_LINK}"
sudo nginx -t
sudo systemctl reload nginx

echo -e "${CYAN}6. Request SSL...${NC}"
sudo certbot --nginx --non-interactive --agree-tos -m "${LE_EMAIL}" -d "${DOMAIN}" --redirect

echo -e "${CYAN}7. Buat user MySQL...${NC}"
sudo mysql -u root <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '${DBUSER}'@'%' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON *.* TO '${DBUSER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo -e "${CYAN}8. Enable remote MySQL...${NC}"
MYSQL_CNF=""
if [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
    MYSQL_CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [[ -f /etc/mysql/mysql.conf.d/mysqld.cnf ]]; then
    MYSQL_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
fi

if [[ -n "${MYSQL_CNF}" ]]; then
    sudo sed -i 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' "${MYSQL_CNF}"
fi

sudo systemctl restart mariadb

echo -e "\n${GREEN}Install kelar.${NC}"
echo -e "URL      : ${CYAN}https://${DOMAIN}${NC}"
echo -e "DB User  : ${YELLOW}${DBUSER}${NC}"
echo -e "Password : ${YELLOW}${DBPASS}${NC}"
