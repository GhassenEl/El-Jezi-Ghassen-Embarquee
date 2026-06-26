# Home AI — intelligence domotique

Analyse confort, sécurité et énergie intégrée au **home-cloud** et à l'app mobile `smart_home`.

## Moteur

| Fichier | Rôle |
|---------|------|
| `../home-cloud/cloud-api/ai_engine.py` | Moteur d'analyse |
| `../home-cloud/cloud-api/main.py` | Endpoints `/api/v1/ai/*` |
| `../../04-mobile-flutter/smart_home/lib/ai/home_ai_engine.dart` | IA locale (sans cloud) |

## Métriques IA

| Indicateur | Description |
|------------|-------------|
| `security_risk` | low / medium / high (mouvement AWAY, porte…) |
| `comfort_score` | 0–100 (température, humidité, lux) |
| `energy_score` | 0–100 (puissance, modes inutiles) |
| `predicted_temp_c` | Température prévue |
| `auto_mode_recommended` | HOME / AWAY / SLEEP suggéré |

Pas de GPU ni modèle externe — heuristiques + régression légère.
