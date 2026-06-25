# 13 — Smart Home (maison connectee)

Domotique IoT : temperature, luminosite, mouvement, porte, eclairage, chauffage et securite — ESP32, dashboard web, **app mobile Flutter** et **IA** (locale + cloud).

```
ESP32 / Simulateur ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── home-dashboard (:8100)
        │                         ├── home-api (:8120) — IA + historique
        │                         └── smart_home (Flutter) — IA locale
```

## Composants

| Dossier | Role |
|---------|------|
| `data/zones.json` | 5 zones (salon, chambre, cuisine, bureau, garage) |
| `esp32-smart-home/` | Module ESP32 WiFi + capteurs simules |
| `home-dashboard/` | Dashboard Flask temps reel (port **8100**) |
| `home-api/` | **API FastAPI IA** — ingestion MQTT, SQLite, insights |
| `home-monitor/` | Moniteur Python + alertes securite |
| `../04-mobile-flutter/smart_home/` | **App mobile Flutter** (4 onglets dont IA) |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/home/telemetry` | `ZONE=salon,T=22.5,H=48,LUX=420,MOTION=1,DOOR=0,LIGHT=1,HEAT=0,PWR=380` |
| `eljezi/home/command` | `STATUS`, `LIGHT_ON`, `MODE_AWAY`, `LOCK_ON` |
| `eljezi/home/status` | `ZONE=salon,ONLINE=1,MODE=HOME,TARGET_T=22,ALARM=1,LOCK=1` |
| `eljezi/home/alert` | `ZONE=salon,ALERT=MOTION_AWAY` |

## 5 zones

salon · chambre · cuisine · bureau · garage

## IA domotique

| Couche | Description |
|--------|-------------|
| **Locale (Flutter)** | Confort, securite, energie, recommandations instantanees |
| **Cloud (Python)** | `home-api` ingere MQTT, historique SQLite, endpoints REST |

Endpoints API (port **8120**) :

- `GET /api/v1/health`
- `GET /api/v1/zones`
- `GET /api/v1/ai/insights?zone=salon&mode=HOME`
- `GET /api/v1/ai/overview`

## Commandes

| Commande | Action |
|----------|--------|
| `STATUS` | Publication telemetrie + status |
| `LIGHT_ON` / `LIGHT_OFF` | Eclairage |
| `HEAT_ON` / `HEAT_OFF` | Chauffage |
| `MODE_HOME` / `MODE_AWAY` / `MODE_SLEEP` | Profil domotique |
| `LOCK_ON` / `LOCK_OFF` | Verrouillage porte |
| `SET_TEMP_22` | Consigne temperature (°C) |
| `ALARM_OFF` / `ALARM_ON` | Alarmes |

## Alertes

| Alerte | Condition |
|--------|-----------|
| `MOTION_AWAY` | Mouvement en mode AWAY |
| `DOOR_OPEN` | Porte ouverte |
| `INTRUSION` | Porte + mouvement en mode AWAY |
| `TEMP_HIGH` | Temperature > 30°C |

## Demarrage

```bash
# 1. Broker MQTT
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# 2. Simulateur (5 zones domotique)
cd ../demo-publisher && python simulator.py

# 3. API IA cloud (optionnel)
cd ../../13-smart-home/home-api
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8120

# 4. Dashboard web
cd ../home-dashboard && pip install -r requirements.txt && python app.py --web-port 8100

# 5. App mobile
cd ../../04-mobile-flutter/smart_home
flutter pub get && flutter run
```

Dans l'app : onglet **IA** → URL `http://<IP_PC>:8120`

**Dashboard :** http://127.0.0.1:8100

## Branche GitHub

```bash
git clone -b project/13-smart-home --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
