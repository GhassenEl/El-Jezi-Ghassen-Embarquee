# 17 — Smart Parking IoT

Parking connecte Grand Tunis : places libres, occupation, bornes EV, barrieres.

```
ESP32 / simulateur ──MQTT──► Mosquitto
        │                         ├── parking-api (:5160) — IA recommandation
        │                         └── smart_parking (Flutter)
```

| Dossier | Role |
|---------|------|
| `data/lots.json` | 5 parkings Grand Tunis |
| `parking-api/` | API FastAPI IA — meilleur parking (port **5160**) |
| `../04-mobile-flutter/smart_parking/` | **App mobile Flutter** (4 onglets dont IA) |

## Topics MQTT

| Topic | Exemple |
|-------|---------|
| `eljezi/parking/telemetry` | `LOT=lac-nord,SPOTS=120,FREE=34,OCC=72,EV=2,GATE=1,T=28,H=55` |
| `eljezi/parking/command` | `STATUS`, `GATE_OPEN`, `GATE_CLOSE` |
| `eljezi/parking/status` | `LOT=lac-nord,ONLINE=1,MODE=NORMAL,GATE=OPEN` |
| `eljezi/parking/alert` | `LOT=medina-centre,ALERT=ALMOST_FULL` |

## Demarrage

```bash
cd 05-iot-mqtt/demo-publisher && python simulator.py
cd ../../17-smart-parking/parking-api && pip install -r requirements.txt && uvicorn main:app --host 0.0.0.0 --port 5160
cd ../../04-mobile-flutter/smart_parking && flutter pub get && flutter run
```

## Branche dediee

```bash
git clone -b project/17-smart-parking --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
