# Branches GitHub — un projet par branche

Le dépôt **main** contient l'intégralité des projets (monorepo).
Chaque branche `project/*` est une **vue isolée** : seul le contenu de ce projet est à la racine, pour cloner et travailler sans le reste.

## Branches disponibles

| Branche | Contenu à la racine | Description |
|---------|---------------------|-------------|
| `main` | Monorepo complet | Tous les dossiers `01` … `08` |
| `project/01-rtos` | `01-rtos/` | FreeRTOS + BLE |
| `project/02-linux-embarque` | `02-linux-embarque/` | GPIO sysfs, libgpiod, driver noyau, MQTT Pi |
| `project/03-affichage-data` | `03-affichage-data/` | Dashboard Python matplotlib |
| `project/04-mobile-flutter` | `04-mobile-flutter/` | Apps Flutter IoT |
| `project/05-iot-mqtt` | `05-iot-mqtt/` | Mosquitto + ESP32 MQTT |
| `project/06-iot-web-dashboard` | `06-iot-web-dashboard/` | Dashboard Flask SSE |
| `project/07-oled-ssd1306` | `07-oled-ssd1306/` | OLED SSD1306 ESP32 |
| `project/08-esp32-unified`   | `08-esp32-unified/` | **BLE + MQTT + OLED** |
| `project/09-smart-farm`      | `09-smart-farm/` | **Smart Farm** |
| `project/10-smart-meteo`     | `10-smart-meteo/` | **Smart Meteo** |

## Cloner un seul projet

```bash
# Exemple : firmware unifié uniquement
git clone -b project/08-esp32-unified --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git eljezi-unified

cd eljezi-unified/esp32-all-in-one
pio run -t upload
```

```bash
# Exemple : apps Flutter uniquement
git clone -b project/04-mobile-flutter --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git eljezi-flutter
```

## Régénérer les branches (maintenance)

Depuis `main`, après modification d'un projet :

```bash
./scripts/publish-project-branches.sh
```

Sous Windows PowerShell :

```powershell
.\scripts\publish-project-branches.ps1
```

Chaque script recrée les branches `project/*` à partir des dossiers correspondants sur `main`.

## Lien monorepo ↔ branche

Chaque branche projet contient un fichier `MONOREPO.md` à la racine avec le lien vers `main` et la date de publication.
