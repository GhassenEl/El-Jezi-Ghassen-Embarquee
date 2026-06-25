# 09 — Smart Farm (agriculture intelligente)

Ferme connectée : capteurs sol / air / lumière, irrigation automatique, dashboard web et alertes MQTT.

```
Capteurs ESP32 ──MQTT──► Mosquitto LAN ──bridge──► Mosquitto Cloud (:1884)
                              │                         │
                              │                         ▼
                              │                   cloud-api REST (:5070)
                              │                         │
                              ▼                         SQLite historique
                        farm-dashboard (web)            │
                        smart_farm (mobile) ◄───────────┘
                              │
                        farm-monitor (CLI)
```

## Composants

| Dossier | Rôle |
|---------|------|
| `esp32-smart-farm/` | Station terrain WiFi + pompe irrigation |
| `farm-dashboard/` | Dashboard Flask temps réel (port **5060**) |
| `farm-monitor/` | Moniteur Python + alertes sol sec |
| `farm-cloud/` | **Cloud** — broker MQTT :1884 + API REST :5070 + SQLite |
| `farm-ai/` | **IA** — analyse, prédiction sol, irrigation assistée |
| `../04-mobile-flutter/smart_farm/` | **App mobile Flutter** irrigation + alertes + panneau IA |

## Topics MQTT

| Topic | Direction | Exemple |
|-------|-----------|---------|
| `eljezi/smartfarm/telemetry` | ESP32 → broker | `ZONE=parcelle-a,T=24.0,H=55.0,S=32.0,L=8000,PUMP=0,MODE=AUTO` |
| `eljezi/smartfarm/command` | broker → ESP32 | `PUMP_ON`, `MODE_AUTO`, `SET_THRESH_30` |
| `eljezi/smartfarm/status` | ESP32 → broker | `ZONE=parcelle-a,PUMP=0,MODE=AUTO,THRESH=30` |
| `eljezi/smartfarm/alert` | ESP32 → broker | `ZONE=parcelle-a,ALERT=SOIL_DRY_AUTO_START` |

## Commandes

| Commande | Action |
|----------|--------|
| `PUMP_ON` / `PUMP_OFF` | Pompe irrigation (GPIO 4) — manuel |
| `MODE_AUTO` / `MODE_MANUAL` | Irrigation automatique si sol &lt; seuil |
| `SET_THRESH_30` | Seuil humidité sol 10–80 % |
| `STATUS` | Force publication télémétrie |

## Mode AUTO

1. Sol &lt; seuil → démarrage pompe + alerte `SOIL_DRY_AUTO_START`
2. Sol ≥ seuil + 8 % ou 45 s max → arrêt + alerte

## Démarrage

```bash
# 1. Broker (partagé avec 05-iot-mqtt)
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# 2. ESP32
cd esp32-smart-farm/include && copy secrets.h.example secrets.h
cd .. && pio run -t upload

# 3. Dashboard
cd ../farm-dashboard && pip install -r requirements.txt
python app.py --broker localhost --web-port 5060

# 4. Moniteur (optionnel)
cd ../farm-monitor && pip install -r requirements.txt
python monitor.py --broker localhost

# 5. Mobile Flutter
cd ../../04-mobile-flutter/smart_farm
flutter pub get && flutter run

# 6. Cloud (Docker)
cd ../../09-smart-farm/farm-cloud
docker compose up -d --build
# API : http://localhost:5070/docs
# MQTT cloud : localhost:1884
# IA : http://localhost:5070/api/v1/ai/insights
```

## Intelligence artificielle

Voir `farm-ai/README.md`. Endpoints :

| Route | Description |
|-------|-------------|
| `GET /api/v1/ai/insights` | Score santé, risque, recommandations |
| `GET /api/v1/ai/predict?hours=6` | Prédiction humidité sol |
| `POST /api/v1/ai/auto-irrigate` | Irrigation assistée (`{"confirm":true}`) |

L'app mobile affiche le panneau **IA ferme** en pointant vers `http://IP:5070`.

Ouvrir **http://127.0.0.1:5060**

## Matériel

| Élément | Brochage |
|---------|----------|
| Pompe / relais | GPIO **4** |
| Capteur sol analogique | GPIO **34** (simulé si absent) |

## FreeRTOS

| Tâche | Rôle |
|-------|------|
| `task_sensor` | Simulation capteurs → `telemetryQueue` |
| `task_actuator` | Commandes MQTT → `cmdQueue` |
| `task_irrigation` | Logique AUTO + alertes |
| `task_comms` | Publish MQTT |
| `task_mqtt` | Boucle broker |

## Branche GitHub

```bash
git clone -b project/09-smart-farm --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
