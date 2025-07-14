#!/bin/bash

# Warna terminal
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Welcome screen
display_welcome() {
  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]                                                 [+]${NC}"
  echo -e "${BLUE}[+]                AUTO INSTALLER THEMA            [+]${NC}"
  echo -e "${BLUE}[+]                    © PANNZYY                    [+]${NC}"
  echo -e "${BLUE}[+]                                                 [+]${NC}"
  echo -e "${RED}[+] =============================================== [+]${NC}"
  echo -e ""
  echo -e "Script ini dibuat untuk mempermudah penginstalan tema Pterodactyl."
  echo -e "Dilarang memperjualbelikan script ini."
  echo -e ""
  echo -e "WhatsApp : 0857-6016-5634"
  echo -e "YouTube  : @vanzzxyt"
  echo -e "Credits  : @pannzyy"
  sleep 4
  clear
}

# Theme installer
install_theme() {
  while true; do
    echo -e "${BLUE}[+] =============================================== [+]${NC}"
    echo -e "${BLUE}[+]                   SELECT THEME                  [+]${NC}"
    echo -e "${BLUE}[+] =============================================== [+]${NC}"
    echo -e "PILIH THEME YANG INGIN DI INSTALL:"
    echo "1. stellar"
    echo "2. billing"
    echo "3. enigma"
    echo "4. wemx"
    echo "x. kembali"
    echo -ne "Masukkan pilihan (1/2/3/4/x): "
    read -r SELECT_THEME

    case "$SELECT_THEME" in
      1)
        THEME_URL="https://github.com/VanzzzTOT/temaa/raw/refs/heads/main/stellarbaru.zip"
        ZIP_NAME="stellarbaru.zip"
        break
        ;;
      2)
        THEME_URL="https://github.com/panntzyy/temaa/raw/refs/heads/main/billing.zip"
        ZIP_NAME="billing.zip"
        break
        ;;
      3)
        THEME_URL="https://github.com/VanzzTOT/temaa/raw/main/enigma.zip"
        ZIP_NAME="enigma.zip"
        break
        ;;
      4)
        THEME_URL="https://github.com/apies13/install/raw/refs/heads/main/wemx.zip"
        ZIP_NAME="wemx.zip"
        break
        ;;
      x)
        return
        ;;
      *)
        echo -e "${RED}Pilihan tidak valid, silakan coba lagi.${NC}"
        ;;
    esac
  done

  # Cleanup folder sementara
  [ -d /root/pterodactyl ] && sudo rm -rf /root/pterodactyl

  echo -e "${BLUE}[+] Mengunduh theme...${NC}"
  wget -q -O "/root/$ZIP_NAME" "$THEME_URL"

  echo -e "${BLUE}[+] Mengekstrak theme...${NC}"
  unzip -o "/root/$ZIP_NAME" -d /root/pterodactyl

  echo -e "${BLUE}[+] Menyalin theme ke /var/www/pterodactyl...${NC}"
  sudo cp -rfT /root/pterodactyl /var/www/pterodactyl

  echo -e "${BLUE}[+] Menginstal Node.js & Yarn...${NC}"
  curl -sL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt install -y nodejs
  sudo npm i -g yarn

  cd /var/www/pterodactyl || { echo -e "${RED}Direktori tidak ditemukan!${NC}"; exit 1; }

  yarn add react-feather

  if [ "$SELECT_THEME" -eq 2 ]; then
    php artisan billing:install stable
  fi

  if [ "$SELECT_THEME" -eq 3 ]; then
    echo -ne "${YELLOW}Masukkan LINK_WA : ${NC}"
    read LINK_WA
    echo -ne "${YELLOW}Masukkan LINK_GROUP : ${NC}"
    read LINK_GROUP
    echo -ne "${YELLOW}Masukkan LINK_CHANNEL : ${NC}"
    read LINK_CH

    sed -i "s|LINK_WA|$LINK_WA|g" /var/www/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx
    sed -i "s|LINK_GROUP|$LINK_GROUP|g" /var/www/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx
    sed -i "s|LINK_CH|$LINK_CH|g" /var/www/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx
  fi

  php artisan migrate
  yarn build:production
  php artisan view:clear

  echo -e "${BLUE}[+] Membersihkan file sementara...${NC}"
  rm -f "/root/$ZIP_NAME"
  rm -rf /root/pterodactyl

  echo -e "${GREEN}[✓] Theme berhasil di-install!${NC}"
  sleep 2
  clear
}

# Menu utama
while true; do
  display_welcome
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]                   MAIN MENU                     [+]${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "Pilih opsi:"
  echo "1. Install theme"
  echo "x. Keluar"
  echo -ne "Masukkan pilihan: "
  read -r MENU_CHOICE

  case "$MENU_CHOICE" in
    1)
      install_theme
      ;;
    x)
      echo -e "${YELLOW}Keluar dari skrip.${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}Pilihan tidak valid.${NC}"
      ;;
  esac
done
