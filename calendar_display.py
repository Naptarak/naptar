#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import datetime
import traceback
import logging
import feedparser
import requests
from dateutil.easter import easter
from PIL import Image, ImageDraw, ImageFont
try:
    from astral import LocationInfo
    from astral.sun import sun
    from astral.moon import moon_phase, moonrise, moonset
except ImportError:
    print("Astral könyvtár hiányzik. Telepítsd: pip3 install astral")
    sys.exit(1)

# Import a saját e-Paper meghajtó
current_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(current_dir)
try:
    from epd_driver import EPaper
except ImportError:
    print("epd_driver.py nem található. Ellenőrizd, hogy ugyanabban a könyvtárban van-e.")
    sys.exit(1)

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/epaper_calendar.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Konstansok
RSS_URL = "https://telex.hu/rss"
CITY = "Pécs"  # Módosítsd a saját városodra
COUNTRY = "Hungary"
LATITUDE = 46.0727  # Módosítsd a saját koordinátáidra
LONGITUDE = 18.2323
TIMEZONE = "Europe/Budapest"

# Színek
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (0, 255, 0)
BLUE = (0, 0, 255)
RED = (255, 0, 0)
YELLOW = (255, 255, 0)
ORANGE = (255, 165, 0)

# Magyar ünnepnapok és jeles napok (fix dátumok)
FIXED_HOLIDAYS = {
    (1, 1): ("Újév", RED),
    (3, 15): ("Nemzeti ünnep", RED),
    (5, 1): ("A munka ünnepe", RED),
    (8, 20): ("Államalapítás ünnepe", RED),
    (10, 23): ("Nemzeti ünnep", RED),
    (11, 1): ("Mindenszentek", RED),
    (12, 24): ("Szenteste", RED),
    (12, 25): ("Karácsony 1. napja", RED),
    (12, 26): ("Karácsony 2. napja", RED)
}

# Jeles napok (nem ünnepnapok)
NOTABLE_DAYS = {
    (1, 22): ("A magyar kultúra napja", BLUE),
    (2, 2): ("Gyertyaszentelő Boldogasszony", BLUE),
    (2, 14): ("Valentin-nap", RED),
    (3, 8): ("Nemzetközi nőnap", ORANGE),
    (4, 11): ("A magyar költészet napja", BLUE),
    (4, 22): ("A Föld napja", GREEN),
    (5, 8): ("A vöröskereszt világnapja", RED),
    (5, 10): ("Madarak és fák napja", GREEN),
    (5, 31): ("Nemdohányzó világnap", BLUE),
    (6, 5): ("Környezetvédelmi világnap", GREEN),
    (7, 1): ("Köztisztviselők napja", BLUE),
    (8, 1): ("A forint születésnapja", BLUE),
    (9, 30): ("A magyar népmese napja", ORANGE),
    (10, 1): ("Zenei világnap", BLUE),
    (10, 6): ("Az aradi vértanúk napja", RED),
    (11, 3): ("A magyar tudomány napja", BLUE),
    (11, 27): ("Véradók napja", RED),
    (12, 6): ("Mikulás", RED)
}

# Magyar névnapok
def get_hungarian_namedays():
    namedays = {
        (1, 1): "Fruzsina",
        (1, 2): "Ábel",
        (1, 3): "Genovéva, Benjámin",
        (1, 4): "Titusz, Leona",
        (1, 5): "Simon",
        (1, 6): "Boldizsár",
        (1, 7): "Attila, Ramóna",
        (1, 8): "Gyöngyvér",
        (1, 9): "Marcell",
        (1, 10): "Melánia",
        (1, 11): "Ágota",
        (1, 12): "Ernő",
        (1, 13): "Veronika",
        (1, 14): "Bódog",
        (1, 15): "Lóránt, Loránd",
        (1, 16): "Gusztáv",
        (1, 17): "Antal, Antónia",
        (1, 18): "Piroska",
        (1, 19): "Sára, Márió",
        (1, 20): "Fábián, Sebestyén",
        (1, 21): "Ágnes",
        (1, 22): "Vince, Artúr",
        (1, 23): "Zelma, Rajmund",
        (1, 24): "Timót",
        (1, 25): "Pál",
        (1, 26): "Vanda, Paula",
        (1, 27): "Angelika",
        (1, 28): "Károly, Karola",
        (1, 29): "Adél",
        (1, 30): "Martina, Gerda",
        (1, 31): "Marcella",
        (2, 1): "Ignác",
        (2, 2): "Karolina, Aida",
        (2, 3): "Balázs",
        (2, 4): "Ráhel, Csenge",
        (2, 5): "Ágota, Ingrid",
        (2, 6): "Dorottya, Dóra",
        (2, 7): "Tódor, Rómeó",
        (2, 8): "Aranka",
        (2, 9): "Abigél, Alex",
        (2, 10): "Elvira",
        (2, 11): "Bertold, Marietta",
        (2, 12): "Lívia, Lídia",
        (2, 13): "Ella, Linda",
        (2, 14): "Bálint, Valentin",
        (2, 15): "Kolos, Georgina",
        (2, 16): "Julianna, Lilla",
        (2, 17): "Donát",
        (2, 18): "Bernadett",
        (2, 19): "Zsuzsanna",
        (2, 20): "Aladár, Álmos",
        (2, 21): "Eleonóra",
        (2, 22): "Gerzson",
        (2, 23): "Alfréd",
        (2, 24): "Mátyás",
        (2, 25): "Géza",
        (2, 26): "Edina",
        (2, 27): "Ákos, Bátor",
        (2, 28): "Elemér",
        (2, 29): "Antónia, Román",
        (3, 1): "Albin",
        (3, 2): "Lujza",
        (3, 3): "Kornélia",
        (3, 4): "Kázmér",
        (3, 5): "Adorján, Adrián",
        (3, 6): "Leonóra, Inez",
        (3, 7): "Tamás",
        (3, 8): "Zoltán",
        (3, 9): "Franciska, Fanni",
        (3, 10): "Ildikó",
        (3, 11): "Szilárd",
        (3, 12): "Gergely",
        (3, 13): "Krisztián, Ajtony",
        (3, 14): "Matild",
        (3, 15): "Kristóf",
        (3, 16): "Henrietta",
        (3, 17): "Gertrúd, Patrik",
        (3, 18): "Sándor, Ede",
        (3, 19): "József, Bánk",
        (3, 20): "Klaudia",
        (3, 21): "Benedek",
        (3, 22): "Beáta, Izolda",
        (3, 23): "Emőke",
        (3, 24): "Gábor, Karina",
        (3, 25): "Irén, Írisz",
        (3, 26): "Emánuel",
        (3, 27): "Hajnalka",
        (3, 28): "Gedeon, Johanna",
        (3, 29): "Auguszta",
        (3, 30): "Zalán",
        (3, 31): "Árpád",
        (4, 1): "Hugó",
        (4, 2): "Áron",
        (4, 3): "Buda, Richárd",
        (4, 4): "Izidor",
        (4, 5): "Vince",
        (4, 6): "Vilmos, Bíborka",
        (4, 7): "Herman",
        (4, 8): "Dénes",
        (4, 9): "Erhard",
        (4, 10): "Zsolt",
        (4, 11): "Leó, Szaniszló",
        (4, 12): "Gyula",
        (4, 13): "Ida",
        (4, 14): "Tibor",
        (4, 15): "Anasztázia, Tas",
        (4, 16): "Csongor",
        (4, 17): "Rudolf",
        (4, 18): "Andrea, Ilma",
        (4, 19): "Emma",
        (4, 20): "Tivadar",
        (4, 21): "Konrád",
        (4, 22): "Csilla, Noémi",
        (4, 23): "Béla",
        (4, 24): "György",
        (4, 25): "Márk",
        (4, 26): "Ervin",
        (4, 27): "Zita",
        (4, 28): "Valéria",
        (4, 29): "Péter",
        (4, 30): "Katalin, Kitti",
        (5, 1): "Fülöp, Jakab",
        (5, 2): "Zsigmond",
        (5, 3): "Tímea, Irma",
        (5, 4): "Mónika, Flórián",
        (5, 5): "Györgyi",
        (5, 6): "Ivett, Frida",
        (5, 7): "Gizella",
        (5, 8): "Mihály",
        (5, 9): "Gergely",
        (5, 10): "Ármin, Pálma",
        (5, 11): "Ferenc",
        (5, 12): "Pongrác",
        (5, 13): "Szervác, Imola",
        (5, 14): "Bonifác",
        (5, 15): "Zsófia, Szonja",
        (5, 16): "Mózes, Botond",
        (5, 17): "Paszkál",
        (5, 18): "Erik, Alexandra",
        (5, 19): "Ivó, Milán",
        (5, 20): "Bernát, Felícia",
        (5, 21): "Konstantin",
        (5, 22): "Júlia, Rita",
        (5, 23): "Dezső",
        (5, 24): "Eszter, Eliza",
        (5, 25): "Orbán",
        (5, 26): "Fülöp, Evelin",
        (5, 27): "Hella",
        (5, 28): "Emil, Csanád",
        (5, 29): "Magdolna",
        (5, 30): "Janka, Zsanett",
        (5, 31): "Angéla, Petronella",
        (6, 1): "Tünde",
        (6, 2): "Kármen, Anita",
        (6, 3): "Klotild",
        (6, 4): "Bulcsú",
        (6, 5): "Fatime",
        (6, 6): "Norbert, Cintia",
        (6, 7): "Róbert",
        (6, 8): "Medárd",
        (6, 9): "Félix",
        (6, 10): "Margit, Gréta",
        (6, 11): "Barnabás",
        (6, 12): "Villő",
        (6, 13): "Antal, Anett",
        (6, 14): "Vazul",
        (6, 15): "Jolán, Vid",
        (6, 16): "Jusztin",
        (6, 17): "Laura, Alida",
        (6, 18): "Arnold, Levente",
        (6, 19): "Gyárfás",
        (6, 20): "Rafael",
        (6, 21): "Alajos, Leila",
        (6, 22): "Paulina",
        (6, 23): "Zoltán",
        (6, 24): "Iván",
        (6, 25): "Vilmos",
        (6, 26): "János, Pál",
        (6, 27): "László",
        (6, 28): "Levente, Irén",
        (6, 29): "Péter, Pál",
        (6, 30): "Pál",
        (7, 1): "Tihamér, Annamária",
        (7, 2): "Ottó",
        (7, 3): "Kornél, Soma",
        (7, 4): "Ulrik",
        (7, 5): "Emese, Sarolta",
        (7, 6): "Csaba",
        (7, 7): "Apollónia",
        (7, 8): "Ellák",
        (7, 9): "Lukrécia",
        (7, 10): "Amália",
        (7, 11): "Nóra, Lili",
        (7, 12): "Izabella, Dalma",
        (7, 13): "Jenő",
        (7, 14): "Örs, Stella",
        (7, 15): "Henrik, Roland",
        (7, 16): "Valter",
        (7, 17): "Endre, Elek",
        (7, 18): "Frigyes",
        (7, 19): "Emília",
        (7, 20): "Illés",
        (7, 21): "Dániel, Daniella",
        (7, 22): "Magdolna",
        (7, 23): "Lenke",
        (7, 24): "Kinga, Kincső",
        (7, 25): "Kristóf, Jakab",
        (7, 26): "Anna, Anikó",
        (7, 27): "Olga, Liliána",
        (7, 28): "Szabolcs",
        (7, 29): "Márta, Flóra",
        (7, 30): "Judit, Xénia",
        (7, 31): "Oszkár",
        (8, 1): "Boglárka",
        (8, 2): "Lehel",
        (8, 3): "Hermina",
        (8, 4): "Domonkos, Dominika",
        (8, 5): "Krisztina",
        (8, 6): "Berta, Bettina",
        (8, 7): "Ibolya",
        (8, 8): "László",
        (8, 9): "Emőd",
        (8, 10): "Lőrinc",
        (8, 11): "Zsuzsanna, Tiborc",
        (8, 12): "Klára",
        (8, 13): "Ipoly",
        (8, 14): "Marcell",
        (8, 15): "Mária",
        (8, 16): "Ábrahám",
        (8, 17): "Jácint",
        (8, 18): "Ilona",
        (8, 19): "Huba",
        (8, 20): "István",
        (8, 21): "Sámuel, Hajna",
        (8, 22): "Menyhért, Mirjam",
        (8, 23): "Bence",
        (8, 24): "Bertalan",
        (8, 25): "Lajos, Patrícia",
        (8, 26): "Izsó",
        (8, 27): "Gáspár",
        (8, 28): "Ágoston",
        (8, 29): "Beatrix, Erna",
        (8, 30): "Rózsa",
        (8, 31): "Erika, Bella",
        (9, 1): "Egyed, Egon",
        (9, 2): "Rebeka, Dorina",
        (9, 3): "Hilda",
        (9, 4): "Rozália",
        (9, 5): "Viktor, Lőrinc",
        (9, 6): "Zakariás",
        (9, 7): "Regina",
        (9, 8): "Mária, Adrienn",
        (9, 9): "Ádám",
        (9, 10): "Nikolett, Hunor",
        (9, 11): "Teodóra",
        (9, 12): "Mária",
        (9, 13): "Kornél",
        (9, 14): "Szeréna, Roxána",
        (9, 15): "Enikő, Melitta",
        (9, 16): "Edit",
        (9, 17): "Zsófia",
        (9, 18): "Diána",
        (9, 19): "Vilhelmina",
        (9, 20): "Friderika",
        (9, 21): "Máté, Mirella",
        (9, 22): "Móric",
        (9, 23): "Tekla",
        (9, 24): "Gellért, Mercédesz",
        (9, 25): "Eufrozina, Kende",
        (9, 26): "Jusztina, Pál",
        (9, 27): "Adalbert",
        (9, 28): "Vencel",
        (9, 29): "Mihály",
        (9, 30): "Jeromos",
        (10, 1): "Malvin",
        (10, 2): "Petra",
        (10, 3): "Helga",
        (10, 4): "Ferenc",
        (10, 5): "Aurél",
        (10, 6): "Brúnó, Renáta",
        (10, 7): "Amália",
        (10, 8): "Koppány",
        (10, 9): "Dénes",
        (10, 10): "Gedeon",
        (10, 11): "Brigitta",
        (10, 12): "Miksa",
        (10, 13): "Kálmán, Ede",
        (10, 14): "Helén",
        (10, 15): "Teréz",
        (10, 16): "Gál",
        (10, 17): "Hedvig",
        (10, 18): "Lukács",
        (10, 19): "Nándor",
        (10, 20): "Vendel",
        (10, 21): "Orsolya",
        (10, 22): "Előd",
        (10, 23): "Gyöngyi",
        (10, 24): "Salamon",
        (10, 25): "Blanka, Bianka",
        (10, 26): "Dömötör",
        (10, 27): "Szabina",
        (10, 28): "Simon, Szimonetta",
        (10, 29): "Nárcisz",
        (10, 30): "Alfonz",
        (10, 31): "Farkas",
        (11, 1): "Marianna",
        (11, 2): "Achilles",
        (11, 3): "Győző",
        (11, 4): "Károly",
        (11, 5): "Imre",
        (11, 6): "Lénárd",
        (11, 7): "Rezső",
        (11, 8): "Zsombor",
        (11, 9): "Tivadar",
        (11, 10): "Réka",
        (11, 11): "Márton",
        (11, 12): "Jónás, Renátó",
        (11, 13): "Szilvia",
        (11, 14): "Aliz",
        (11, 15): "Albert, Lipót",
        (11, 16): "Ödön",
        (11, 17): "Hortenzia, Gergő",
        (11, 18): "Jenő",
        (11, 19): "Erzsébet",
        (11, 20): "Jolán",
        (11, 21): "Olivér",
        (11, 22): "Cecília",
        (11, 23): "Kelemen, Klementina",
        (11, 24): "Emma",
        (11, 25): "Katalin",
        (11, 26): "Virág",
        (11, 27): "Virgil",
        (11, 28): "Stefánia",
        (11, 29): "Taksony",
        (11, 30): "András, Andor",
        (12, 1): "Elza",
        (12, 2): "Melinda, Vivien",
        (12, 3): "Ferenc, Olívia",
        (12, 4): "Borbála, Barbara",
        (12, 5): "Vilma",
        (12, 6): "Miklós",
        (12, 7): "Ambrus",
        (12, 8): "Mária",
        (12, 9): "Natália",
        (12, 10): "Judit",
        (12, 11): "Árpád",
        (12, 12): "Gabriella",
        (12, 13): "Luca, Otília",
        (12, 14): "Szilárda",
        (12, 15): "Valér",
        (12, 16): "Etelka, Aletta",
        (12, 17): "Lázár, Olimpia",
        (12, 18): "Auguszta",
        (12, 19): "Viola",
        (12, 20): "Teofil",
        (12, 21): "Tamás",
        (12, 22): "Zénó",
        (12, 23): "Viktória",
        (12, 24): "Ádám, Éva",
        (12, 25): "Eugénia",
        (12, 26): "István",
        (12, 27): "János",
        (12, 28): "Kamilla",
        (12, 29): "Tamás, Tamara",
        (12, 30): "Dávid",
        (12, 31): "Szilveszter"
    }
    return namedays

# Meteorrajok adatai
def get_meteor_showers():
    meteor_showers = [
        {"name": "Quadrantidák", "start": (1, 1), "peak": (1, 3), "end": (1, 6)},
        {"name": "Lyridák", "start": (4, 16), "peak": (4, 22), "end": (4, 25)},
        {"name": "Eta Aquaridák", "start": (4, 19), "peak": (5, 6), "end": (5, 28)},
        {"name": "Delta Aquaridák", "start": (7, 12), "peak": (7, 30), "end": (8, 23)},
        {"name": "Perseidák", "start": (7, 17), "peak": (8, 12), "end": (8, 24)},
        {"name": "Orionidák", "start": (10, 2), "peak": (10, 21), "end": (11, 7)},
        {"name": "Leonidák", "start": (11, 6), "peak": (11, 17), "end": (11, 30)},
        {"name": "Geminidák", "start": (12, 4), "peak": (12, 14), "end": (12, 17)}
    ]
    return meteor_showers

# Mozgó ünnepek meghatározása adott évre
def get_moving_holidays(year):
    # Húsvét vasárnap
    easter_date = easter(year)
    
    # Nagypéntek (Húsvét vasárnap - 2 nap)
    good_friday = easter_date - datetime.timedelta(days=2)
    
    # Húsvét hétfő (Húsvét vasárnap + 1 nap)
    easter_monday = easter_date + datetime.timedelta(days=1)
    
    # Pünkösd vasárnap (Húsvét vasárnap + 49 nap)
    pentecost = easter_date + datetime.timedelta(days=49)
    
    # Pünkösd hétfő (Húsvét vasárnap + 50 nap)
    pentecost_monday = easter_date + datetime.timedelta(days=50)
    
    return {
        (good_friday.month, good_friday.day): ("Nagypéntek", RED),
        (easter_date.month, easter_date.day): ("Húsvét vasárnap", RED),
        (easter_monday.month, easter_monday.day): ("Húsvét hétfő", RED),
        (pentecost.month, pentecost.day): ("Pünkösd vasárnap", RED),
        (pentecost_monday.month, pentecost_monday.day): ("Pünkösd hétfő", RED)
    }

# Az aktuális dátum ellenőrzése, hogy ünnepnap vagy jeles nap-e
def check_special_day(date):
    year = date.year
    month = date.month
    day = date.day
    
    # Mozgó ünnepek lekérése az adott évre
    moving_holidays = get_moving_holidays(year)
    
    # Rögzített ünnepek ellenőrzése
    if (month, day) in FIXED_HOLIDAYS:
        return FIXED_HOLIDAYS[(month, day)]
    
    # Mozgó ünnepek ellenőrzése
    if (month, day) in moving_holidays:
        return moving_holidays[(month, day)]
    
    # Jeles napok ellenőrzése
    if (month, day) in NOTABLE_DAYS:
        return NOTABLE_DAYS[(month, day)]
    
    return None

# Az aktuális névnap lekérése
def get_nameday(date):
    month = date.month
    day = date.day
    
    namedays = get_hungarian_namedays()
    
    if (month, day) in namedays:
        return namedays[(month, day)]
    
    return "Ismeretlen"

# Aktív meteorrajok ellenőrzése
def check_meteor_showers(date):
    month = date.month
    day = date.day
    
    meteor_showers = get_meteor_showers()
    active_showers = []
    
    for shower in meteor_showers:
        start_month, start_day = shower["start"]
        peak_month, peak_day = shower["peak"]
        end_month, end_day = shower["end"]
        
        # Ellenőrizzük, hogy a dátum a meteorraj időszakban van-e
        if (month > start_month or (month == start_month and day >= start_day)) and \
           (month < end_month or (month == end_month and day <= end_day)):
            
            # Ellenőrizzük, hogy a csúcs napon vagyunk-e
            is_peak = (month == peak_month and day == peak_day)
            
            active_showers.append({
                "name": shower["name"],
                "is_peak": is_peak
            })
    
    return active_showers

# Hold fázis szöveges leírása
def get_moon_phase_description(phase_percent):
    if phase_percent < 1:
        return "Újhold"
    elif phase_percent < 25:
        return "Növekvő sarló"
    elif phase_percent < 49:
        return "Növekvő félhold"
    elif phase_percent < 51:
        return "Félhold"
    elif phase_percent < 75:
        return "Növekvő domború"
    elif phase_percent < 99:
        return "Telihold közeli"
    else:
        return "Telihold"

# Időformázás
def format_time(dt):
    if dt is None:
        return "Nem kel/nyugszik"
    return dt.strftime("%H:%M")

# RSS feed lekérése
def get_rss_feed():
    try:
        logger.info("RSS hírcsatorna lekérése a Telex.hu-ról...")
        feed = feedparser.parse(RSS_URL)
        
        # Az első 3 bejegyzés lekérése
        entries = []
        for i, entry in enumerate(feed.entries[:3]):
            title = entry.title
            entries.append(title)
            logger.info(f"RSS bejegyzés {i+1}: {title[:50]}...")
        
        return entries
    except Exception as e:
        logger.error(f"HIBA az RSS lekérésénél: {e}")
        logger.error(traceback.format_exc())
        return ["RSS hiba: Nem sikerült betölteni a híreket."]

# Naptár megjelenítése a kijelzőn
def update_display():
    try:
        logger.info("Naptár megjelenítése a kijelzőn...")
        
        # Kijelző objektum létrehozása
        epd = EPaper()
        
        try:
            # Kijelző inicializálása
            epd.init()
            
            # Aktuális dátum és idő lekérése
            now = datetime.datetime.now()
            date_str = now.strftime("%Y. %m. %d.")
            day_str = now.strftime("%A")
            time_str = now.strftime("%H:%M")
            
            # Magyar hónapnevek és napok
            hungarian_days = ["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek", "Szombat", "Vasárnap"]
            hungarian_months = ["január", "február", "március", "április", "május", "június", 
                               "július", "augusztus", "szeptember", "október", "november", "december"]
            
            day_of_week = now.weekday()
            month = now.month - 1  # 0-tól indexelve
            
            hu_day = hungarian_days[day_of_week]
            hu_month = hungarian_months[month]
            hu_date = f"{now.year}. {hu_month} {now.day}., {hu_day}"
            
            # Kép létrehozása
            image = Image.new('RGB', (epd.width, epd.height), color=(255, 255, 255))
            draw = ImageDraw.Draw(image)
            
            # Betűtípus beállítása
            # Alapértelmezett betűtípus használata, mivel a betűtípusok problémát okozhatnak
            font = ImageFont.load_default()
            
            # Ellenőrizzük, hogy a mai nap speciális nap-e
            special_day = check_special_day(now)
            is_holiday = False
            special_day_color = BLACK
            
            if special_day:
                special_day_name, color_code = special_day
                is_holiday = (color_code == RED)
                special_day_color = color_code
            
            # Névnap lekérése
            nameday = get_nameday(now)
            
            # Nap és hold információk
            city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
            
            s = sun(city.observer, date=now.date())
            sunrise = s["sunrise"].astimezone(datetime.timezone.utc).astimezone()
            sunset = s["sunset"].astimezone(datetime.timezone.utc).astimezone()
            
            # Hold információk
            moon_phase_value = moon_phase(now)
            moon_phase_percent = round(moon_phase_value * 100 / 29.53)
            moon_phase_text = get_moon_phase_description(moon_phase_percent)
            
            try:
                moonrise_val = moonrise(city.observer, now.date())
                moonset_val = moonset(city.observer, now.date())
                
                if moonrise_val:
                    moonrise_val = moonrise_val.astimezone(datetime.timezone.utc).astimezone()
                
                if moonset_val:
                    moonset_val = moonset_val.astimezone(datetime.timezone.utc).astimezone()
            except Exception as e:
                logger.error(f"Hiba a holdkelte/holdnyugta számításánál: {e}")
                moonrise_val = None
                moonset_val = None
            
            # Meteorrajok ellenőrzése
            meteor_showers = check_meteor_showers(now)
            
            # RSS hírfolyam lekérése
            rss_entries = get_rss_feed()
            
            # Képernyő elemek rajzolása
            # Fejléc háttér
            draw.rectangle([(0, 0), (epd.width, 50)], fill=(230, 230, 255))
            
            # Dátum kiírása
            if is_holiday:
                date_color = RED
            else:
                date_color = BLACK
            
            draw.text((20, 10), hu_date, font=font, fill=date_color)
            
            # Idő kiírása
            draw.text((epd.width - 100, 10), time_str, font=font, fill=BLACK)
            
            # Aktuális pozíció a rajzoláshoz
            y_pos = 70
            
            # Speciális nap kiírása, ha van
            if special_day:
                special_day_name, _ = special_day
                draw.text((20, y_pos), f"Mai nap: {special_day_name}", font=font, fill=special_day_color)
                y_pos += 30
            
            # Névnap kiírása
            draw.text((20, y_pos), f"Névnap: {nameday}", font=font, fill=BLUE)
            y_pos += 30
            
            # Napkelte és napnyugta információk
            sunrise_str = format_time(sunrise)
            sunset_str = format_time(sunset)
            draw.text((20, y_pos), f"Napkelte: {sunrise_str} | Napnyugta: {sunset_str}", font=font, fill=ORANGE)
            y_pos += 30
            
            # Holdkelte és holdnyugta információk
            moonrise_str = format_time(moonrise_val)
            moonset_str = format_time(moonset_val)
            draw.text((20, y_pos), f"Holdkelte: {moonrise_str} | Holdnyugta: {moonset_str}", font=font, fill=BLACK)
            y_pos += 30
            
            # Hold fázis kiírása
            draw.text((20, y_pos), f"Hold fázis: {moon_phase_percent}% ({moon_phase_text})", font=font, fill=BLUE)
            y_pos += 30
            
            # Meteorraj információk kiírása, ha van
            if meteor_showers:
                meteor_text = "Meteorraj: "
                for i, shower in enumerate(meteor_showers):
                    if i > 0:
                        meteor_text += ", "
                    meteor_text += shower["name"]
                    if shower["is_peak"]:
                        meteor_text += " (csúcs)"
                
                draw.text((20, y_pos), meteor_text, font=font, fill=(150, 0, 150))
                y_pos += 30
            
            # Elválasztó vonal
            draw.line([(20, y_pos), (epd.width - 20, y_pos)], fill=(200, 200, 200), width=2)
            y_pos += 20
            
            # RSS hírfolyam fejléc
            draw.text((20, y_pos), "Hírek (Telex.hu):", font=font, fill=GREEN)
            y_pos += 30
            
            # RSS hírek kiírása
            for i, entry in enumerate(rss_entries):
                # Szöveg hosszának korlátozása
                if len(entry) > 80:
                    entry = entry[:77] + "..."
                
                draw.text((30, y_pos), f"• {entry}", font=font, fill=BLACK)
                y_pos += 25
            
            # Utolsó frissítés ideje
            updated_str = f"Frissítve: {now.strftime('%Y-%m-%d %H:%M')}"
            draw.text((epd.width - 200, epd.height - 20), updated_str, font=font, fill=(100, 100, 100))
            
            # Kép megjelenítése a kijelzőn
            epd.display(image)
            
            # Kijelző alvó módba helyezése
            epd.sleep()
            
            logger.info("Naptár sikeresen megjelenítve a kijelzőn")
            
        finally:
            # Erőforrások felszabadítása
            try:
                epd.close()
            except:
                pass
            
    except Exception as e:
        logger.error(f"Hiba a naptár megjelenítésekor: {e}")
        logger.error(traceback.format_exc())

# Főprogram
def main():
    try:
        logger.info("E-Paper Naptár alkalmazás indítása")
        
        # Kezdeti megjelenítés
        update_display()
        
        # Fő ciklus - 10 percenkénti frissítés
        while True:
            logger.info("Várakozás 10 percig a következő frissítésig...")
            time.sleep(600)  # 10 perc = 600 másodperc
            
            # Kijelző frissítése
            update_display()
            
    except KeyboardInterrupt:
        logger.info("Program megszakítva a felhasználó által")
    except Exception as e:
        logger.error(f"Váratlan hiba: {e}")
        logger.error(traceback.format_exc())
    finally:
        logger.info("Program leállítva")

if __name__ == "__main__":
    main()
