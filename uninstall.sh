#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/var/www/phpmyadmin"
NGINX_CONF="/etc/nginx/sites-available/phpmyadmin.conf"
NGINX_LINK="/etc/nginx/sites-enabled/phpmyadmin.conf"

clear
echo -e "${CYAN}"
echo "=================================================="
echo "         AUTO UNINSTALL PHPMYADMIN CLEAN          "
echo "=================================================="
echo -e "${NC}"

read -r -p "Domain phpMyAdmin yang mau dihapus: " DOMAIN
read -r -p "Hapus user MySQL juga? (y/n): " REMOVE_DBUSER
DBUSER=""
if [[ "${REMOVE_DBUSER}" =~ ^[Yy]$ ]]; then
    read -r -p "MySQL Username yang mau dihapus: " DBUSER
fi

read -r -p "Hapus sertifikat Let's Encrypt juga? (y/n): " REMOVE_CERT

if [[ -z "${DOMAIN}" ]]; then
    echo -e "${RED}Domain gak boleh kosong.${NC}"
    exit 1
fi

echo -e "${YELLOW}Mulai uninstall untuk ${DOMAIN}...${NC}"

echo -e "${CYAN}1. Hapus nginx config...${NC}"
sudo rm -f "${NGINX_LINK}"
sudo rm -f "${NGINX_CONF}"

if sudo nginx -t >/dev/null 2>&1; then
    sudo systemctl reload nginx
else
    echo -e "${RED}nginx config masih ada yang bermasalah. cek manual.${NC}"
fi

echo -e "${CYAN}2. Hapus file phpMyAdmin...${NC}"
sudo rm -rf "${INSTALL_DIR}"

if [[ "${REMOVE_CERT}" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}3. Hapus sertifikat Let's Encrypt...${NC}"
    sudo certbot delete --cert-name "${DOMAIN}" --non-interactive || true
    sudo rm -rf "/etc/letsencrypt/live/${DOMAIN}" \
                "/etc/letsencrypt/archive/${DOMAIN}" \
                "/etc/letsencrypt/renewal/${DOMAIN}.conf"
fi

if [[ -n "${DBUSER}" ]]; then
    echo -e "${CYAN}4. Hapus user MySQL...${NC}"
    sudo mysql -u root <<MYSQL_SCRIPT
DROP USER IF EXISTS '${DBUSER}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
fi

echo -e "\n${GREEN}Uninstall kelar.${NC}"
echo -e "Domain: ${YELLOW}${DOMAIN}${NC}"
