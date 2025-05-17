#!/bin/bash

# uninstall.sh
# Eltávolító szkript az e-Paper naptár kijelzőhöz

# Színek
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

APP_NAME="epaper_calendar"
APP_DIR="/opt/$APP_NAME"
CRON_COMMENT="ePaper Calendar Update"

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${YELLOW}Ezt a szkriptet root jogosultságokkal (sudo) kell futtatni.${NC}"
  exit 1
fi

echo -e "${YELLOW}E-Paper Naptár Eltávolító Indítása...${NC}"

echo -e "${GREEN}Cron job eltávolítása...${NC}"
(crontab -l 2>/dev/null | grep -v -F "$CRON_COMMENT") | crontab -
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Cron job sikeresen eltávolítva (ha létezett).${NC}"
else
    echo -e "${YELLOW}Nem sikerült módosítani a crontab-ot, vagy nem volt ilyen job.${NC}"
fi

if [ -d "$APP_DIR" ]; then
    echo -e "${GREEN}Alkalmazás könyvtárának ($APP_DIR) eltávolítása...${NC}"
    rm -rf "$APP_DIR"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Alkalmazás könyvtár sikeresen eltávolítva.${NC}"
    else
        echo -e "${RED}HIBA: Nem sikerült eltávolítani az alkalmazás könyvtárát: $APP_DIR ${NC}"
    fi
else
    echo -e "${YELLOW}Az alkalmazás könyvtára ($APP_DIR) nem található.${NC}"
fi

LOG_FILE="/tmp/${APP_NAME}.log"
if [ -f "$LOG_FILE" ]; then
    echo -e "${GREEN}Naplófájl ($LOG_FILE) eltávolítása...${NC}"
    rm -f "$LOG_FILE"
fi

read -p "Szeretnéd megkísérelni az APT által telepített rendszerszintű függőségek (pl. python3-pil, libtiff6) eltávolítását? (Ez más programokat is érinthet!) (i/n): " REMOVE_DEPS
if [[ "$REMOVE_DEPS" == "i" || "$REMOVE_DEPS" == "I" ]]; then
    echo -e "${YELLOW}Megpróbálom eltávolítani a telepítéskor felhasznált APT csomagokat...${NC}"
    echo -e "${YELLOW}FIGYELEM: Ez más, ezeket a csomagokat használó alkalmazásokat is érinthet!${NC}"
    # A REQUIRED_PACKAGES változó itt nem létezik, ezért manuálisan listázzuk, vagy az install.sh-ból kellene átvenni
    PACKAGES_TO_REMOVE="python3-pil python3-numpy libopenjp2-7 libtiff6 python3-rpi.gpio python3-spidev ttf-dejavu" # git, python3, pip, venv általában maradnak
    apt-get remove --purge $PACKAGES_TO_REMOVE
    apt-get autoremove --purge
    echo -e "${GREEN}Függőségek eltávolítása befejeződött (ha telepítve voltak és más nem függött tőlük).${NC}"
else
    echo -e "${YELLOW}Rendszerszintű függőségek nem lettek eltávolítva.${NC}"
fi

echo -e "${GREEN}AZ ELTÁVOLÍTÁS BEFEJEZŐDÖTT!${NC}"
echo -e "Az SPI interfészt manuálisan tilthatod le a 'sudo raspi-config' segítségével, ha már nincs rá szükség."

exit 0
