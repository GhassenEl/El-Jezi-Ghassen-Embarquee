# Home Cloud — couche cloud Smart Home

Relais MQTT local → cloud, API REST avec historique, flux temps réel (SSE) et IA domotique.

```
ESP32 / Simulateur ──MQTT──► Mosquitto local (05-iot-mqtt)
                                    │ bridge
                                    ▼
                            Mosquitto Cloud (:1885)
                                    │
                                    ▼
                            cloud-api FastAPI (:8120)
                             ├── SQLite historique
                             ├── REST /api/v1/*
                             ├── SSE /api/v1/stream
                             └── IA /api/v1/ai/*
```

## Démarrage cloud (Docker)

```bash
cd home-cloud
docker compose up -d --build
```

| Service | URL / port |
|---------|------------|
| Broker cloud MQTT | `mqtt://localhost:1885` |
| API REST | http://localhost:8120 |
| Santé | http://localhost:8120/api/v1/health |
| Docs OpenAPI | http://localhost:8120/docs |

## Pont local → cloud

1. Démarrer le cloud : `docker compose up -d`
2. Démarrer Mosquitto local : `05-iot-mqtt/mosquitto`
3. Copier `bridge/mosquitto-bridge.conf.example` vers `05-iot-mqtt/mosquitto/bridge.d/home-cloud.conf`
4. Redémarrer le broker local

Sous Windows Docker, `host.docker.internal:1885` pointe vers le broker cloud.

## API REST (v1)

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/api/v1/health` | État service + MQTT |
| GET | `/api/v1/zones` | 5 zones domotique |
| GET | `/api/v1/telemetry/latest` | Dernier échantillon |
| GET | `/api/v1/telemetry/history` | Historique SQLite |
| GET | `/api/v1/alerts` | Alertes enregistrées |
| POST | `/api/v1/command` | `{"command":"LIGHT_ON"}` |
| GET | `/api/v1/stream` | SSE temps réel |
| GET | `/api/v1/ai/insights` | Analyse IA (confort, sécurité, énergie) |
| GET | `/api/v1/ai/history` | Historique analyses IA |
| GET | `/api/v1/ai/overview` | Vue réseau maison |
| POST | `/api/v1/ai/auto-mode` | Mode domotique assisté `{"confirm":true}` |

Voir aussi `../home-ai/README.md`.

## Développement local (sans Docker)

```bash
docker compose up mosquitto-cloud -d
cd cloud-api
pip install -r requirements.txt
set MQTT_BROKER=localhost
set MQTT_PORT=1885
uvicorn main:app --reload --port 8120
```

## Connexion mobile

- **MQTT direct** : broker `IP_SERVEUR:1885`, topics `eljezi/home/*`
- **REST / IA** : `http://IP_SERVEUR:8120/api/v1/...`

L'app Flutter `smart_home` utilise l'onglet **IA** avec l'URL cloud-api.

## Données persistées

SQLite `home_cloud.db` :
- `telemetry` — chaque message MQTT capteurs
- `alerts` — alertes sécurité / température
- `commands` — commandes envoyées via API
- `ai_insights` — snapshots analyses IA

## Différence avec `home-api/`

| | `home-api/` | `home-cloud/` |
|---|-------------|---------------|
| Usage | Dev rapide (`uvicorn` seul) | Production Docker |
| MQTT broker | Local :1883 | Cloud dédié :1885 |
| SSE / commandes REST | Non | Oui |
| Pont bridge | Non | Oui |
