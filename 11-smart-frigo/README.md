# 11 — Smart Frigo (refrigerateur connecte)

Refrigerateur IoT : temperatures frigo/congelateur, porte, compresseur, consommation — ESP32, dashboard web, moniteur et app mobile.

```
ESP32 Smart Frigo ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── frigo-dashboard (:5090)
        │                         ├── frigo-monitor (CLI)
        │                         └── smart_frigo (Flutter)
```

## Composants

| Dossier | Role |
|---------|------|
| `esp32-smart-frigo/` | Module ESP32 WiFi + capteurs simules |
| `frigo-dashboard/` | Dashboard Flask temps reel (port **5090**) |
| `frigo-monitor/` | Moniteur Python + alertes |
| `../04-mobile-flutter/smart_frigo/` | **App mobile Flutter** |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/frigo/telemetry` | `ZONE=cuisine,T=4.2,F=-18.5,H=42,DOOR=0,COMP=1,PWR=120` |
| `eljezi/frigo/command` | `STATUS`, `MODE_ECO`, `SET_FRIDGE_4`, `ALARM_OFF` |
| `eljezi/frigo/status` | `ZONE=cuisine,ONLINE=1,MODE=NORMAL,TARGET_F=4,TARGET_Z=-18,ALARM=1` |
| `eljezi/frigo/alert` | `ZONE=cuisine,ALERT=DOOR_OPEN_LONG` |

## Commandes

| Commande | Action |
|----------|--------|
| `STATUS` | Publication telemetrie + status |
| `MODE_ECO` / `MODE_NORMAL` | Profil consommation |
| `SET_FRIDGE_4` | Consigne frigo 4°C |
| `SET_FREEZE_-18` | Consigne congelateur -18°C |
| `ALARM_OFF` / `ALARM_ON` | Couper / reactiver alarmes |

## Alertes

| Alerte | Condition |
|--------|-----------|
| `DOOR_OPEN_LONG` | Porte ouverte > 60 s |
| `FRIDGE_TEMP_HIGH` | Frigo > 8°C |
| `FREEZER_TEMP_HIGH` | Congelateur > -12°C |
| `POWER_HIGH` | Consommation > 150 W |

## Demarrage

```bash
cd ../05-iot-mqtt/mosquitto && docker compose up -d
cd ../../11-smart-frigo/esp32-smart-frigo/include && copy secrets.h.example secrets.h
cd .. && pio run -t upload
cd ../frigo-dashboard && pip install -r requirements.txt && python app.py --web-port 5090
cd ../04-mobile-flutter/smart_frigo && flutter pub get && flutter run
```

**Dashboard :** http://127.0.0.1:5090

## Branche GitHub

```bash
git clone -b project/11-smart-frigo --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
