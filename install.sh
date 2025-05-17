#!/bin/bash

# install.sh
# Telepítő szkript az e-Paper naptár kijelzőhöz Raspberry Pi Zero 2W-n
# Kijelző: Waveshare 4.01 inch e-Paper HAT (F) (7 színű, 640x400)

# Színek a kimenethez
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Alkalmazás könyvtára és egyéb beállítások
APP_NAME="epaper_calendar"
APP_DIR="/opt/$APP_NAME"
VENV_DIR="$APP_DIR/venv"
PYTHON_SCRIPT_NAME="display_calendar.py"
RUN_SCRIPT_NAME="run_display.sh"
LOG_FILE="/tmp/${APP_NAME}.log"
CRON_COMMENT="ePaper Calendar Update"

# Ellenőrizzük, hogy a szkript rootként fut-e
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${YELLOW}Ezt a szkriptet root jogosultságokkal (sudo) kell futtatni.${NC}"
  exit 1
fi

echo -e "${GREEN}E-Paper Naptár Telepítő Indítása...${NC}"

# --- 1. Rendszer frissítése és alapvető csomagok telepítése ---
echo -e "${GREEN}Rendszer frissítése és alapvető csomagok telepítése...${NC}"
apt-get update && apt-get upgrade -y
if ! apt-get install -y git python3 python3-pip python3-venv python3-pil python3-numpy libopenjp2-7 libtiff5 ttf-dejavu wiringpi; then
    echo -e "${RED}HIBA: Nem sikerült telepíteni az alapvető rendszerfüggőségeket. Ellenőrizd az internetkapcsolatot és az apt forrásokat.${NC}"
    exit 1
fi
# A wiringpi szükséges lehet a Waveshare BCM2835 lib-hez, bár a python libek ezt általában nem használják közvetlenül.
# Ellenőrizzük a python3-pip telepítését expliciten
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}HIBA: A pip3 telepítése sikertelen volt. Próbáld meg manuálisan: sudo apt-get install python3-pip${NC}"
    exit 1
fi

# --- 2. SPI interfész engedélyezésének ellenőrzése (emlékeztető) ---
echo -e "${YELLOW}FIGYELEM: Győződj meg róla, hogy az SPI interfész engedélyezve van a 'sudo raspi-config' segítségével.${NC}"
echo -e "${YELLOW}Interfacing Options -> SPI -> Yes. Ha most engedélyezted, indítsd újra a Pi-t a telepítés folytatása előtt.${NC}"
# Megpróbáljuk non-interaktívan engedélyezni, de a manuális ellenőrzés a biztos.
raspi-config nonint get_spi | grep -q "0" # 0 means enabled
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Az SPI nincs engedélyezve. Megpróbálom engedélyezni...${NC}"
    raspi-config nonint do_spi 0
    echo -e "${YELLOW}Az SPI engedélyezve. Javasolt egy újraindítás a folytatás előtt.${NC}"
    read -p "Szeretnéd most újraindítani? (i/n): " REBOOT_CHOICE
    if [[ "$REBOOT_CHOICE" == "i" || "$REBOOT_CHOICE" == "I" ]]; then
        echo "Újraindítás..."
        reboot
        exit 0
    fi
fi

# --- 3. Waveshare e-Paper illesztőprogram telepítése ---
echo -e "${GREEN}Waveshare e-Paper illesztőprogram telepítése...${NC}"
if [ -d "/tmp/e-Paper" ]; then
    rm -rf /tmp/e-Paper
fi
git clone https://github.com/waveshare/e-Paper.git /tmp/e-Paper
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült letölteni a Waveshare e-Paper könyvtárat. Ellenőrizd a git telepítését és az internetkapcsolatot.${NC}"
    exit 1
fi

# A 4.01inch HAT (F) 7-color kijelzőhöz a waveshare_epd könyvtár szükséges.
# Ezt a python/lib/waveshare_epd útvonalon találjuk.
# Ahelyett, hogy globálisan telepítenénk, bemásoljuk az alkalmazásunk mappájába.
echo -e "${GREEN}Waveshare Python könyvtár másolása az alkalmazás könyvtárába...${NC}"


# --- 4. Alkalmazás könyvtár és virtuális környezet létrehozása ---
echo -e "${GREEN}Alkalmazás könyvtár létrehozása: $APP_DIR ${NC}"
mkdir -p "$APP_DIR/lib"
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült létrehozni az alkalmazás könyvtárát: $APP_DIR ${NC}"
    exit 1
fi
# Waveshare lib másolása
cp -R /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/lib/"
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült átmásolni a Waveshare Python könyvtárat ide: $APP_DIR/lib/waveshare_epd ${NC}"
    echo -e "${YELLOW}Lehetséges ok: A letöltött e-Paper repository struktúrája megváltozott.${NC}"
    exit 1
fi
# BCM2835 library telepítése (néhány Waveshare példa használja, jó ha megvan)
cd /tmp/e-Paper/RaspberryPi_JetsonNano/c/lib/
make clean
make -j4
make install
# Vissza az eredeti könyvtárba
cd -

echo -e "${GREEN}Python virtuális környezet létrehozása: $VENV_DIR ${NC}"
python3 -m venv "$VENV_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült létrehozni a Python virtuális környezetet.${NC}"
    exit 1
fi

# --- 5. Python függőségek telepítése a virtuális környezetbe ---
echo -e "${GREEN}Python függőségek telepítése...${NC}"
# Aktiváljuk a venv-et a pip parancsokhoz
source "$VENV_DIR/bin/activate"

pip3 install Pillow holidays astral feedparser requests hunకాల # hunnameday helyett hunకాల
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült telepíteni a Python függőségeket (Pillow, holidays, astral, feedparser, requests, hunకాల).${NC}"
    echo -e "${YELLOW}Ellenőrizd az internetkapcsolatot és a pip működését.${NC}"
    echo -e "${YELLOW}Próbáld meg manuálisan a venv aktiválása után: pip3 install Pillow holidays astral feedparser requests hunకాల${NC}"
    deactivate
    exit 1
fi
deactivate

# --- 6. Python alkalmazás létrehozása ---
echo -e "${GREEN}Python alkalmazás létrehozása ($APP_DIR/$PYTHON_SCRIPT_NAME)...${NC}"
cat << EOF > "$APP_DIR/$PYTHON_SCRIPT_NAME"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import datetime
import time
import sys
import os
import logging

# Helyi Waveshare könyvtár hozzáadása a Python útvonalhoz
# A lib könyvtárat az APP_DIR-be másoltuk, ami tartalmazza a waveshare_epd mappát.
# Tehát az APP_DIR/lib lesz a sys.path-ban.
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'lib'))

try:
    from waveshare_epd import epd4in01f
except ImportError:
    logging.error("HIBA: Waveshare EPD könyvtár nem található. Ellenőrizd a telepítést és a PYTHONPATH-ot.")
    # Próbáljuk meg a globálisat, ha a helyi import sikertelen
    try:
        logging.info("Próbálkozás globális Waveshare könyvtárral...")
        # Ideiglenesen eltávolítjuk a helyi útvonalat, hogy a globálisat részesítse előnyben
        # Ez a rész inkább hibakeresésre van, normál esetben a helyi importnak működnie kell.
        # original_sys_path = list(sys.path)
        # sys.path = [p for p in sys.path if 'APP_DIR/lib' not in p] # Nem triviális dinamikusan
        # from waveshare_epd import epd4in01f
        # sys.path = original_sys_path
    except ImportError:
        logging.error("HIBA: Globális Waveshare EPD könyvtár sem található.")
        sys.exit("Kérlek telepítsd a Waveshare illesztőprogramot megfelelően.")


from PIL import Image, ImageDraw, ImageFont
import holidays
import astral
import astral.sun
import astral.moon
import feedparser
import requests
# from hunnameday import get_namedays # Eredeti terv
from hunkal import HungarianCalendar, HolidayType # Újabb, jobb könyvtár

# --- Konfiguráció ---
CITY_NAME = "Pecs"
COUNTRY_NAME = "Hungary"
TIMEZONE = "Europe/Budapest"
LATITUDE = 46.0724
LONGITUDE = 18.2284
EPD_WIDTH = 640
EPD_HEIGHT = 400
RSS_URL = "https://telex.hu/rss"
LOG_PATH = "$LOG_FILE" # A shell scriptből átvett érték

# --- Betűtípusok (győződj meg róla, hogy telepítve vannak) ---
# A ttf-dejavu csomag biztosítja ezeket
FONT_BOLD_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REGULAR_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
# Kisebb méretű betűk, ha szükséges
FONT_SMALL_REGULAR_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_SMALL_BOLD_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


# --- Színek a Waveshare epd4in01f számára (a könyvtár által definiált konstansok) ---
# Ezeket a konstansokat használjuk a PIL ImageDraw-ban is, de RGB tuple-ként.
# A driver skonvertálja ezeket a saját formátumára.
# PIL RGB values:
COLOR_BLACK = (0, 0, 0)
COLOR_WHITE = (255, 255, 255)
COLOR_GREEN = (0, 255, 0)
COLOR_BLUE = (0, 0, 255)
COLOR_RED = (255, 0, 0)
COLOR_YELLOW = (255, 255, 0)
COLOR_ORANGE = (255, 128, 0) # Kicsit sötétebb narancs a jobb láthatóságért

# Waveshare specific color constants (for reference, not directly used by Pillow draw)
# EPD_BLACK   = 0
# EPD_WHITE   = 1
# EPD_GREEN   = 2
# EPD_BLUE    = 3
# EPD_RED     = 4
# EPD_YELLOW  = 5
# EPD_ORANGE  = 6

# --- Logging beállítása ---
log_dir = os.path.dirname(LOG_PATH)
if not os.path.exists(log_dir):
    os.makedirs(log_dir, exist_ok=True) # Győződjünk meg róla, hogy a log könyvtár létezik

logging.basicConfig(filename=LOG_PATH,
                    level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S')

# --- Adatlekérő Funkciók ---
def get_calendar_data(target_date):
    cal = HungarianCalendar(target_date.year)
    data = {
        "holiday_name": None,
        "is_holiday": False,
        "name_days": [],
        "memorial_days": [],
        "other_events": []
    }

    day_info = cal.get_day(target_date.month, target_date.day)

    if day_info:
        for event in day_info:
            if event.type == HolidayType.PUBLIC_HOLIDAY or event.type == HolidayType.RELIGIOUS_HOLIDAY_WITH_WORKDAY_SWAP:
                data["is_holiday"] = True
                data["holiday_name"] = event.name
            elif event.type == HolidayType.NAME_DAY:
                data["name_days"].append(event.name)
            elif event.type == HolidayType.MEMORIAL_DAY or event.type == HolidayType.IMPORTANT_DAY:
                data["memorial_days"].append(event.name)
            else: # OTHER, TRADITIONAL, etc.
                data["other_events"].append(event.name)
    
    # Mozgó ünnepek ellenőrzése, ha a get_day nem tartalmazza mindet (bár a hunkal általában jó)
    # Pl. Húsvét, Pünkösd. A hunkal ezeket is kezeli a megadott évre.

    # Régi holidays library (fallback vagy összehasonlítás)
    # hu_holidays_legacy = holidays.HU(years=target_date.year)
    # legacy_holiday = hu_holidays_legacy.get(target_date)
    # if legacy_holiday and not data["holiday_name"]:
    #    data["holiday_name"] = legacy_holiday
    #    data["is_holiday"] = True
        
    return data

def get_astro_data(city_info, target_date):
    try:
        sun_info = astral.sun.sun(city_info.observer, date=target_date, tzinfo=city_info.timezone)
        
        moon_phase_val = astral.moon.phase(target_date) # 0-27.99
        
        try:
            moonrise_utc = astral.moon.moonrise(city_info.observer, date=target_date)
            moonrise_local = moonrise_utc.astimezone(city_info.timezone) if moonrise_utc else None
        except ValueError:
            moonrise_local = None # Hold nem kel aznap
        
        try:
            moonset_utc = astral.moon.moonset(city_info.observer, date=target_date)
            moonset_local = moonset_utc.astimezone(city_info.timezone) if moonset_utc else None
        except ValueError:
            moonset_local = None # Hold nem nyugszik aznap

        # Holdfázis szövegesen magyarul
        if 0 <= moon_phase_val < 1.0 or moon_phase_val >= 27.0: phase_text = "Újhold"
        elif 1.0 <= moon_phase_val < 6.5: phase_text = "Növekvő sarló"
        elif 6.5 <= moon_phase_val < 7.5: phase_text = "Első negyed"
        elif 7.5 <= moon_phase_val < 13.0: phase_text = "Növekvő hold"
        elif 13.0 <= moon_phase_val < 14.5: phase_text = "Telihold"
        elif 14.5 <= moon_phase_val < 20.0: phase_text = "Fogyó hold"
        elif 20.0 <= moon_phase_val < 21.5: phase_text = "Utolsó negyed"
        else: phase_text = "Fogyó sarló" # 21.5 to < 27.0

        return {
            "sunrise": sun_info["sunrise"].strftime("%H:%M") if sun_info["sunrise"] else "N/A",
            "sunset": sun_info["sunset"].strftime("%H:%M") if sun_info["sunset"] else "N/A",
            "moonrise": moonrise_local.strftime("%H:%M") if moonrise_local else "N/A",
            "moonset": moonset_local.strftime("%H:%M") if moonset_local else "N/A",
            "moon_phase_percent": f"{((moon_phase_val / 27.99) * 100):.0f}%",
            "moon_phase_text": phase_text
        }
    except Exception as e:
        logging.error(f"Hiba az asztrológiai adatok lekérésekor: {e}")
        return {}

def get_meteor_showers(target_date):
    # Forrás: https://www.csillagaszat.hu/csilltortmeteorithullasok/meteorrajok/
    # (év, hónap, nap)
    showers = {
        "Quadrantidák": {"start_month": 12, "start_day": 28, "peak_month": 1, "peak_day": 3, "end_month": 1, "end_day": 12},
        "Lyridák": {"start_month": 4, "start_day": 16, "peak_month": 4, "peak_day": 22, "end_month": 4, "end_day": 25},
        "Eta Aquaridák": {"start_month": 4, "start_day": 19, "peak_month": 5, "peak_day": 6, "end_month": 5, "end_day": 28},
        "Déli Delta Aquaridák": {"start_month": 7, "start_day": 12, "peak_month": 7, "peak_day": 30, "end_month": 8, "end_day": 23},
        "Perseidák": {"start_month": 7, "start_day": 17, "peak_month": 8, "peak_day": 12, "end_month": 8, "end_day": 24}, # Csúcs aug 12-13
        "Drakonidák": {"start_month": 10, "start_day": 6, "peak_month": 10, "peak_day": 8, "end_month": 10, "end_day": 10},
        "Orionidák": {"start_month": 10, "start_day": 2, "peak_month": 10, "peak_day": 21, "end_month": 11, "end_day": 7},
        "Leonidák": {"start_month": 11, "start_day": 6, "peak_month": 11, "peak_day": 17, "end_month": 11, "end_day": 30}, # Csúcs nov 17-18
        "Geminidák": {"start_month": 12, "start_day": 4, "peak_month": 12, "peak_day": 14, "end_month": 12, "end_day": 17},
        "Ursidák": {"start_month": 12, "start_day": 17, "peak_month": 12, "peak_day": 22, "end_month": 12, "end_day": 26},
    }
    active_showers_info = []
    
    for name, data in showers.items():
        # Dátumok az aktuális évre (vagy előző/következő évre, ha a raj átnyúlik)
        year = target_date.year
        
        # Kezdő és végdátum objektumok létrehozása
        # Óvatosan az évváltással (pl. Quadrantidák)
        start_year = year if data["start_month"] <= data["end_month"] else (year -1 if target_date.month <= data["end_month"] else year)
        end_year = year

        try:
            start_dt = datetime.date(start_year, data["start_month"], data["start_day"])
            end_dt = datetime.date(end_year, data["end_month"], data["end_day"])
            peak_dt = datetime.date(year, data["peak_month"], data["peak_day"]) # Csúcs mindig az aktuális évben releváns

            # Quadrantidák speciális kezelése (Dec végétől Jan elejéig)
            if name == "Quadrantidák":
                if target_date.month == 12: # Ha december van, a csúcs jövőre lesz
                    peak_dt = datetime.date(year + 1, data["peak_month"], data["peak_day"])
                    # Az aktivitási periódus vége is jövőre lesz
                    end_dt = datetime.date(year + 1, data["end_month"], data["end_day"])
                elif target_date.month == 1: # Ha január van, a kezdete előző évben volt
                     start_dt = datetime.date(year - 1, data["start_month"], data["start_day"])


            if start_dt <= target_date <= end_dt:
                info = name
                # Ha a csúcs +/- 2 napon belül van, jelezzük
                if abs((target_date - peak_dt).days) <= 2:
                    info += f" (Csúcs: {data['peak_month']}.{data['peak_day']}.)"
                active_showers_info.append(info)
        except ValueError: # Hiba pl. február 29 miatt nem létező dátum esetén
            logging.warning(f"Érvénytelen dátum a(z) {name} meteorrajhoz: {data}")
            continue
            
    return active_showers_info


def get_rss_feed(url, count=3):
    try:
        headers = {'User-Agent': 'RaspberryPiEPaperCalendar/1.0'}
        feed = feedparser.parse(url, agent=headers)
        return [entry.title for entry in feed.entries[:count]]
    except Exception as e:
        logging.error(f"Hiba az RSS feed lekérésekor ({url}): {e}")
        return ["Hírforrás nem elérhető"] * count

# --- Fő Rajzolási Logika ---
def main():
    logging.info("E-Paper frissítés indítása.")
    epd = None # Inicializálás None-ra a finally blokkhoz
    try:
        epd = epd4in01f.EPD()
        logging.info("EPD inicializálása...")
        epd.Init()
        # epd.Clear(epd4in01f.WHITE) # A 4in01f Clear parancsa nem vesz át színt, fixen töröl.
                                     # Üres kép rajzolása a törléshez.
        
        image = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), COLOR_WHITE)
        draw = ImageDraw.Draw(image)

        # --- Betűtípusok betöltése ---
        try:
            font_date = ImageFont.truetype(FONT_BOLD_PATH, 32)
            font_holiday = ImageFont.truetype(FONT_BOLD_PATH, 26)
            font_nameday = ImageFont.truetype(FONT_REGULAR_PATH, 24)
            font_memorial = ImageFont.truetype(FONT_REGULAR_PATH, 20)
            font_astro_label = ImageFont.truetype(FONT_BOLD_PATH, 20)
            font_astro_value = ImageFont.truetype(FONT_REGULAR_PATH, 20)
            font_meteor = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 18)
            font_week = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 18)
            font_rss = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 16)
        except IOError as e:
            logging.error(f"Betűtípusok nem találhatóak: {e}. Alapértelmezett betűtípus használata.")
            # Alapértelmezett betűtípusok használata vészhelyzetben
            font_date = font_holiday = font_nameday = font_memorial = ImageFont.load_default()
            font_astro_label = font_astro_value = font_meteor = font_week = font_rss = ImageFont.load_default()

        # --- Adatok Lekérése ---
        now = datetime.datetime.now(datetime.timezone.utc).astimezone(datetime.timezone(datetime.timedelta(hours=2 if TIMEZONE == "Europe/Budapest" and time.localtime().tm_isdst else 1))) # CEST/CET
        # Pontosabb:
        import pytz
        tz = pytz.timezone(TIMEZONE)
        now = datetime.datetime.now(tz)
        
        today_date_obj = now.date()

        city_info = astral.LocationInfo(CITY_NAME, COUNTRY_NAME, TIMEZONE, LATITUDE, LONGITUDE)

        hun_months = ["január", "február", "március", "április", "május", "június", "július", "augusztus", "szeptember", "október", "november", "december"]
        hun_days = ["hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat", "vasárnap"]
        current_date_str_hu = f"{now.year}. {hun_months[now.month-1]} {now.day}., {hun_days[now.weekday()]}"

        calendar_data = get_calendar_data(today_date_obj)
        astro_data = get_astro_data(city_info, today_date_obj)
        meteor_showers = get_meteor_showers(today_date_obj)
        rss_titles = get_rss_feed(RSS_URL)
        week_number = today_date_obj.isocalendar()[1]

        # --- Rajzolás ---
        y_pos = 10
        padding = 10
        line_spacing_large = 8
        line_spacing_medium = 6
        line_spacing_small = 4

        # 1. Dátum
        date_color = COLOR_RED if calendar_data["is_holiday"] else COLOR_BLACK
        draw.text((padding, y_pos), current_date_str_hu.upper(), font=font_date, fill=date_color)
        y_pos += font_date.getbbox(current_date_str_hu.upper())[3] + line_spacing_large

        # 2. Ünnepnap
        if calendar_data["is_holiday"] and calendar_data["holiday_name"]:
            draw.text((padding, y_pos), calendar_data["holiday_name"], font=font_holiday, fill=COLOR_RED)
            y_pos += font_holiday.getbbox(calendar_data["holiday_name"])[3] + line_spacing_medium
        
        # 3. Névnap(ok)
        if calendar_data["name_days"]:
            nameday_str = "Névnap: " + ", ".join(calendar_data["name_days"])
            draw.text((padding, y_pos), nameday_str, font=font_nameday, fill=COLOR_BLUE)
            y_pos += font_nameday.getbbox(nameday_str)[3] + line_spacing_medium
        
        # 4. Emléknapok / Fontos napok
        significant_days = calendar_data["memorial_days"] + calendar_data["other_events"]
        if significant_days:
            for day_event in significant_days:
                # Ne írjuk ki újra, ha már ünnepként szerepel
                if day_event != calendar_data["holiday_name"]:
                    draw.text((padding, y_pos), day_event, font=font_memorial, fill=COLOR_GREEN)
                    y_pos += font_memorial.getbbox(day_event)[3] + line_spacing_small
            y_pos += line_spacing_medium - line_spacing_small # Korrekció


        y_pos = max(y_pos, 130) # Biztosítunk helyet az asztro adatoknak, ha a felső rész rövid

        # --- Asztro Info (két oszlopban) ---
        col1_x = padding
        col2_x = EPD_WIDTH // 2 
        astro_y_start = y_pos

        if astro_data:
            # Nap
            draw.text((col1_x, astro_y_start), "Napkelte:", font=font_astro_label, fill=COLOR_ORANGE)
            draw.text((col1_x + 110, astro_y_start), astro_data.get('sunrise', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            astro_y_start_col2 = astro_y_start # Külön y_pos a második oszlopnak
            draw.text((col2_x, astro_y_start_col2), "Napnyugta:", font=font_astro_label, fill=COLOR_ORANGE)
            draw.text((col2_x + 120, astro_y_start_col2), astro_data.get('sunset', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            current_astro_y = astro_y_start + font_astro_label.getbbox("Napkelte:")[3] + line_spacing_small
            current_astro_y_col2 = astro_y_start_col2 + font_astro_label.getbbox("Napnyugta:")[3] + line_spacing_small

            # Hold
            draw.text((col1_x, current_astro_y), "Holdkelte:", font=font_astro_label, fill=COLOR_BLUE)
            draw.text((col1_x + 110, current_astro_y), astro_data.get('moonrise', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)

            draw.text((col2_x, current_astro_y_col2), "Holdnyugta:", font=font_astro_label, fill=COLOR_BLUE)
            draw.text((col2_x + 120, current_astro_y_col2), astro_data.get('moonset', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            current_astro_y += font_astro_label.getbbox("Holdkelte:")[3] + line_spacing_small
            current_astro_y_col2 += font_astro_label.getbbox("Holdnyugta:")[3] + line_spacing_small

            # Holdfázis (középre, a két oszlop alá, vagy az egyik oszlopba)
            moon_phase_str = f"{astro_data.get('moon_phase_text','N/A')} ({astro_data.get('moon_phase_percent','N/A')})"
            draw.text((col1_x, current_astro_y), "Holdfázis:", font=font_astro_label, fill=COLOR_BLUE)
            # Hosszabb szöveg miatt lehet, hogy új sorba kell törni, vagy a második oszlopot használni
            # Most az egyszerűség kedvéért egy sorba írjuk
            # draw.text((col1_x + 120, current_astro_y), moon_phase_str, font=font_astro_value, fill=COLOR_BLACK)
            y_pos = max(current_astro_y, current_astro_y_col2) # Következő elem pozíciója
            y_pos += font_astro_value.getbbox(moon_phase_str)[3] # Hely a holdfázis szövegének
            # A holdfázis szövegét a következő sorba írjuk, hogy elférjen
            draw.text((col1_x + 10, y_pos - font_astro_value.getbbox(moon_phase_str)[3] - line_spacing_small), moon_phase_str, font=font_astro_value, fill=COLOR_BLACK)
        
        y_pos += line_spacing_medium

        # 6. Meteorrajok
        if meteor_showers:
            meteor_text = "Meteorraj: " + ", ".join(meteor_showers)
            # Szövegtördelés, ha túl hosszú
            max_width = EPD_WIDTH - 2 * padding
            words = meteor_text.split(' ')
            current_line = ""
            for word in words:
                if draw.textlength(current_line + word, font=font_meteor) <= max_width:
                    current_line += word + " "
                else:
                    draw.text((padding, y_pos), current_line.strip(), font=font_meteor, fill=COLOR_GREEN)
                    y_pos += font_meteor.getbbox(current_line)[3] + line_spacing_small
                    current_line = word + " "
            if current_line: # Utolsó sor kiírása
                draw.text((padding, y_pos), current_line.strip(), font=font_meteor, fill=COLOR_GREEN)
                y_pos += font_meteor.getbbox(current_line)[3] + line_spacing_medium
        
        # 7. Hét száma
        week_str = f"{week_number}. hét"
        draw.text((padding, y_pos), week_str, font=font_week, fill=COLOR_BLACK)
        y_pos += font_week.getbbox(week_str)[3] + line_spacing_large


        # --- RSS Hírek alul ---
        rss_y_start = EPD_HEIGHT - (3 * (font_rss.getbbox("TESZT")[3] + line_spacing_small)) - padding # Hely 3 hírnek
        draw.line([(0, rss_y_start - line_spacing_small), (EPD_WIDTH, rss_y_start - line_spacing_small)], fill=COLOR_BLACK, width=1)

        if rss_titles:
            for i, title in enumerate(rss_titles):
                if i >= 3: break # Max 3 hír
                # Cím rövidítése, ha túl hosszú
                max_chars_rss = (EPD_WIDTH - padding * 2) // (font_rss.getbbox("A")[3] // 2) # Becslés
                display_title = (title[:max_chars_rss-3] + "...") if len(title) > max_chars_rss else title
                
                draw.text((padding, rss_y_start + (i * (font_rss.getbbox(display_title)[3] + line_spacing_small))),
                          f"• {display_title}", font=font_rss, fill=COLOR_BLACK)
        
        logging.info("Kép előkészítve, megjelenítés...")
        # A Waveshare driver várhatóan egy bytearray-t vár a képből.
        # A display() metódusnak kell kezelnie a PIL Image objektum konverzióját.
        # A 4in01f driver az RGB képet egy 7 színű palettára konvertálja.
        epd.display(image)

        logging.info("Kijelző alvó módba helyezése.")
        epd.sleep()

    except IOError as e:
        logging.error(f"IO Hiba (valószínűleg betűtípus vagy fájl): {e}")
    except ImportError as e:
        logging.error(f"Importálási hiba: {e}. Győződj meg róla, hogy minden függőség telepítve van és a Waveshare könyvtár elérhető.")
    except Exception as e:
        logging.exception(f"Váratlan hiba történt a Python szkriptben:") # Exception tartalmazza a traceback-et
    finally:
        if epd:
            logging.info("Modul erőforrásainak felszabadítása (GPIO).")
            # A sleep után érdemes a modul exit-et hívni, hogy a GPIO lábak felszabaduljanak.
            # A display() után a sleep() fontos az e-papírnak.
            # time.sleep(2) # Rövid várakozás a sleep parancs után, ha szükséges
            epd4in01f.epdconfig.module_exit(cleanup=True) # Fontos a GPIO cleanup!
        logging.info("E-Paper frissítés befejezve.")

if __name__ == '__main__':
    main()
EOF
chmod +x "$APP_DIR/$PYTHON_SCRIPT_NAME"

# --- 7. Futtató szkript létrehozása ---
echo -e "${GREEN}Futtató szkript létrehozása ($APP_DIR/$RUN_SCRIPT_NAME)...${NC}"
cat << EOF > "$APP_DIR/$RUN_SCRIPT_NAME"
#!/bin/bash
APP_DIR="$APP_DIR"
VENV_DIR="$VENV_DIR"
PYTHON_SCRIPT="$APP_DIR/$PYTHON_SCRIPT_NAME"
LOG_FILE="$LOG_FILE" # A Python script is ezt használja

# Győződjünk meg róla, hogy a log fájl írható
touch "\$LOG_FILE"
chmod 666 "\$LOG_FILE"

echo "Indítás: \$(date)" >> "\$LOG_FILE"
# Virtuális környezet aktiválása
source "\$VENV_DIR/bin/activate"

# Python útvonal beállítása a helyi Waveshare könyvtárhoz
# A Python szkript már kezeli ezt a sys.path.append segítségével,
# de biztonság kedvéért itt is megadhatjuk.
# export PYTHONPATH="\$APP_DIR/lib:\$PYTHONPATH"

# Futtatás
python3 "\$PYTHON_SCRIPT" >> "\$LOG_FILE" 2>&1
if [ \$? -ne 0 ]; then
    echo "HIBA a Python szkript futtatása során. Részletek: \$LOG_FILE" >> "\$LOG_FILE"
fi

# Deaktiválás (nem feltétlenül szükséges cron job esetén, mert a shell kilép)
deactivate
echo "Befejezés: \$(date)" >> "\$LOG_FILE"
echo "--------------------------------------" >> "\$LOG_FILE"
EOF
chmod +x "$APP_DIR/$RUN_SCRIPT_NAME"

# --- 8. Cron job beállítása ---
echo -e "${GREEN}Cron job beállítása 10 percenkénti frissítéshez...${NC}"
# Először távolítsuk el a régi cron jobot, ha létezik
(crontab -l 2>/dev/null | grep -v -F "$CRON_COMMENT") | crontab -
# Majd adjuk hozzá az újat
(crontab -l 2>/dev/null; echo "*/10 * * * * $APP_DIR/$RUN_SCRIPT_NAME # $CRON_COMMENT") | crontab -
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült beállítani a cron jobot.${NC}"
    echo -e "${YELLOW}Próbáld meg manuálisan: crontab -e, majd add hozzá: */10 * * * * $APP_DIR/$RUN_SCRIPT_NAME # $CRON_COMMENT ${NC}"
else
    echo -e "${GREEN}Cron job sikeresen beállítva.${NC}"
fi

# --- 9. Befejezés és takarítás ---
echo -e "${GREEN}Takarítás...${NC}"
rm -rf /tmp/e-Paper

echo -e "${GREEN}A TELEPÍTÉS BEFEJEZŐDÖTT!${NC}"
echo -e "Az alkalmazás a következő helyre települt: ${YELLOW}$APP_DIR${NC}"
echo -e "A naplófájl itt található: ${YELLOW}$LOG_FILE${NC}"
echo -e "Az első frissítés kb. 10 percen belül várható, vagy futtasd manuálisan: ${YELLOW}$APP_DIR/$RUN_SCRIPT_NAME${NC}"
echo -e "${YELLOW}FONTOS: Ha még nem tetted meg, és a szkript nem indította újra a Pi-t, egy újraindítás javasolt az SPI driverek megfelelő betöltődéséhez.${NC}"

exit 0
