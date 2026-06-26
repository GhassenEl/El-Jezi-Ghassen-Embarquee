# Farm Cloud — couche cloud Smart Farm

Relais MQTT local → cloud, API REST avec historique et flux temps réel.

```
ESP32 (LAN) ──MQTT──► Mosquitto local (05-iot-mqtt)
                            │ bridge
                            ▼
                    Mosquitto Cloud (:1884)
                            │
                            ▼
                    cloud-api FastAPI (:5070)
                     ├── SQLite historique
                     ├── REST /api/v1/*
                     └── SSE /api/v1/stream
```

## Démarrage cloud (Docker)

```bash
cd farm-cloud
docker compose up -d --build
```

| Service | URL / port |
|---------|------------|
| Broker cloud MQTT | `mqtt://localhost:1884` |
| API REST | http://localhost:5070 |
| Santé | http://localhost:5070/api/v1/health |
| Docs OpenAPI | http://localhost:5070/docs |

## Pont local → cloud

1. Démarrer le cloud : `docker compose up -d`
2. Démarrer Mosquitto local : `05-iot-mqtt/mosquitto`
3. Ajouter le bridge dans la config locale :

```bash
# Copier bridge/mosquitto-bridge.conf.example
# vers 05-iot-mqtt/mosquitto/bridge.d/farm-cloud.conf
# puis redémarrer le broker local
```

Sous Windows Docker, `host.docker.internal:1884` pointe vers le broker cloud.

**Alternative sans bridge** : configurer l'ESP32 `secrets.h` avec `MQTT_BROKER` = IP du serveur cloud sur le port **1884**.

## API REST (v1)

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/api/v1/health` | État service + MQTT |
| GET | `/api/v1/telemetry/latest` | Dernier échantillon |
| GET | `/api/v1/telemetry/history?limit=100` | Historique SQLite |
| GET | `/api/v1/alerts?limit=50` | Alertes enregistrées |
| POST | `/api/v1/command` | `{"command":"PUMP_ON"}` |
| GET | `/api/v1/stream` | SSE temps réel |
| GET | `/api/v1/ai/insights` | Analyse IA (santé, risque, recommandations) |
| GET | `/api/v1/ai/history` | Historique analyses IA |
| GET | `/api/v1/ai/predict?hours=6` | Prédiction humidité sol |
| POST | `/api/v1/ai/auto-irrigate` | Irrigation assistée `{"confirm":true}` |

Voir aussi `../farm-ai/README.md`.

## Développement local (sans Docker)

```bash
# Terminal 1 — broker cloud seul
docker compose up mosquitto-cloud -d

# Terminal 2 — API
cd cloud-api
pip install -r requirements.txt
set MQTT_BROKER=localhost
set MQTT_PORT=1884
uvicorn main:app --reload --port 5070
```

## Connexion mobile / distant

- **MQTT direct** : broker `IP_SERVEUR:1884`, topics `eljezi/smartfarm/*`
- **REST** : `http://IP_SERVEUR:5070/api/v1/...` (historique, commandes)

L'app Flutter `smart_farm` peut utiliser le broker cloud en entrant l'IP publique/LAN du serveur et le port **1884**.

## Données persistées

SQLite `farm_cloud.db` :
- `telemetry` — chaque message MQTT capteurs
- `alerts` — alertes irrigation / sol sec
- `commands` — commandes envoyées via API
- `ai_insights` — snapshots analyses IA
