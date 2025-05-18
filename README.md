# Raspberry Pi E-Paper Naptár Kijelző

Naptár és információs kijelző alkalmazás Raspberry Pi Zero 2W + Waveshare 4.01 inch (F) 7-színű e-paper kijelzőhöz.

## Jellemzők

- Aktuális dátum és idő, magyar névnapokkal
- Ünnepnapok és jeles napok színes megjelenítése
- Napkelte és napnyugta ideje
- Holdkelte, holdnyugta és holdfázis információk
- Aktuális meteorraj információk (ha van aktív)
- Telex.hu RSS hírfolyam legfrissebb hírei
- 10 percenkénti automatikus frissítés

## Hardver követelmények

- Raspberry Pi Zero 2W (512MB RAM)
- Waveshare 4.01 inch (F) 7-színű e-paper kijelző (640x400 pixel)
- Működő SPI interfész

## Telepítés

Egyszerűen futtasd:

```bash
git clone https://github.com/felhasznalonev/epaper-calendar.git
cd epaper-calendar
chmod +x install.sh
./install.sh
