# 15 — Smart Station (transport public)

Station connectee pour **moyens de transport publics** : metro, bus, TGM — horaires temps reel, affluence, alertes via MQTT + **app mobile Flutter** avec **IA** (locale + cloud).

```
Simulateur / ESP32 ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── smart_station (Flutter) — IA locale
        │                         └── station-api (:8130) — IA cloud + historique SQLite
```

## Composants

| Dossier | Role |
|---------|------|
| `data/stations.json` | Lignes et stations Grand Tunis |
| `station-monitor/` | Moniteur MQTT CLI |
| `station-api/` | **API FastAPI IA** — ingestion MQTT, SQLite, `/api/v1/ai/insights` |
| `../04-mobile-flutter/smart_station/` | **App mobile Flutter** (4 onglets dont IA) |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/station/telemetry` | `STATION=metro-lac,LINE=M4,VEHICLE=METRO,DIR=Ariana,ETA=4,OCC=65,VALIDATORS=3,T=25,H=50,CROWD=2` |
| `eljezi/station/command` | `STATUS`, `REFRESH_ETA`, `MODE_NORMAL` |
| `eljezi/station/status` | `STATION=metro-lac,ONLINE=1,MODE=NORMAL,LINES=4,SERVICES=6` |
| `eljezi/station/alert` | `STATION=metro-lac,ALERT=DELAY_HIGH` |

## Metriques

| Champ | Description |
|-------|-------------|
| `LINE` | Identifiant ligne (M4, L5, TGM…) |
| `VEHICLE` | METRO, BUS, TRAIN, TRAM |
| `DIR` | Direction / terminus |
| `ETA` | Prochain passage (minutes) |
| `OCC` | Taux occupation % |
| `VALIDATORS` | Validateurs actifs |
| `CROWD` | Densite quai (1–5) |

## 5 stations

metro-lac · metro-republique · bus-bab-bhar · tgm-carthage · metro-ariana

## IA transport

| Couche | Description |
|--------|-------------|
| **Locale (Flutter)** | Analyse instantanee sans serveur : risque retard, confort, ETA prevu, station alternative |
| **Cloud (Python)** | `station-api` ingere MQTT, stocke historique, endpoints REST IA |

Endpoints API (port **8130**) :

- `GET /api/v1/health`
- `GET /api/v1/ai/insights?station=metro-lac`
- `GET /api/v1/ai/network`

## Demarrage

```bash
# 1. Broker MQTT
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# 2. Simulateur (inclut stations)
cd ../demo-publisher && python simulator.py

# 3. API IA cloud (optionnel)
cd ../../15-smart-station/station-api
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8130

# 4. App mobile
cd ../../04-mobile-flutter/smart_station
flutter pub get
flutter run
```

Dans l'app : onglet **IA** → URL `http://<IP_PC>:8130` pour l'analyse cloud.

**Moniteur :** `python station-monitor/monitor.py`

## Branche GitHub

```bash
git clone -b project/15-smart-station --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
