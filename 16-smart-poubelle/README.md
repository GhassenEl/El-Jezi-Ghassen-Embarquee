# 16 — Smart Poubelle (gestion dechets IoT)

Poubelles connectees : niveau de remplissage, poids, couvercle, odeur/gaz, batterie — ESP32, dashboard web, API IA et **app mobile Flutter**.

```
Capteurs / Simulateur ──MQTT──► Mosquitto (05-iot-mqtt)
        │                              │
        │                              ├── poubelle-dashboard (:8140)
        │                              ├── poubelle-api (:5150) — IA collecte
        │                              └── smart_poubelle (Flutter)
```

## Composants

| Dossier | Role |
|---------|------|
| `data/bins.json` | 5 poubelles Grand Tunis (types dechets) |
| `esp32-smart-poubelle/` | Module ESP32 WiFi + capteurs simules |
| `poubelle-dashboard/` | Dashboard Flask temps reel (port **8140**) |
| `poubelle-api/` | API FastAPI IA — prediction remplissage (port **5150**) |
| `poubelle-monitor/` | Moniteur MQTT CLI |
| `../04-mobile-flutter/smart_poubelle/` | App mobile Flutter |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/poubelle/telemetry` | `BIN=parc-lac,TYPE=RECYCLE,FILL=68,WEIGHT=42.5,LID=0,GAS=85,BATT=92,T=26.5,H=52` |
| `eljezi/poubelle/command` | `STATUS`, `EMPTY_CONFIRM`, `LID_LOCK`, `MODE_ALERT` |
| `eljezi/poubelle/status` | `BIN=parc-lac,ONLINE=1,MODE=NORMAL,COLLECT=0,ALARM=1` |
| `eljezi/poubelle/alert` | `BIN=medina-centre,ALERT=FILL_HIGH` |

## 5 poubelles

parc-lac (recyclage) · medina-centre (general) · campus-ensa (papier) · marche-central (organique) · plage-carthage (verre)

## Demarrage

```bash
cd ../05-iot-mqtt/mosquitto && docker compose up -d
cd ../demo-publisher && python simulator.py
cd ../poubelle-dashboard && pip install -r requirements.txt && python app.py --web-port 8140
cd ../poubelle-api && pip install -r requirements.txt && uvicorn main:app --host 0.0.0.0 --port 5150
cd ../../04-mobile-flutter/smart_poubelle && flutter pub get && flutter run
```

**Dashboard :** http://127.0.0.1:8140

## Branche GitHub

```bash
git clone -b project/16-smart-poubelle --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
