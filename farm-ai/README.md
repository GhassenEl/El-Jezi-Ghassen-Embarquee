# Farm AI — Intelligence artificielle Smart Farm

Analyse prédictive et recommandations irrigation intégrées au **cloud-api**.

## Fonctionnalités IA

| Capacité | Description |
|----------|-------------|
| **Score santé** | 0–100 selon humidité sol, tendance, anomalies |
| **Prédiction sol** | Régression linéaire → humidité prévue à +6 h |
| **Risque sécheresse** | `low` / `medium` / `high` / `critical` |
| **Anomalies** | Chutes brutales, sol saturé, stress hydrique |
| **Recommandations** | Irrigation, seuil, mode AUTO/MANUEL |
| **Auto-irrigation IA** | `POST /api/v1/ai/auto-irrigate` si critique + AUTO |

## Fichiers

| Fichier | Rôle |
|---------|------|
| `../farm-cloud/cloud-api/ai_engine.py` | Moteur d'analyse |
| `../farm-cloud/cloud-api/main.py` | Endpoints `/api/v1/ai/*` |

## API

```bash
# Analyse complète
curl http://localhost:5070/api/v1/ai/insights

# Prédiction
curl "http://localhost:5070/api/v1/ai/predict?hours=6"

# Irrigation assistée par IA (confirmation)
curl -X POST http://localhost:5070/api/v1/ai/auto-irrigate \
  -H "Content-Type: application/json" \
  -d '{"confirm": true}'
```

## Exemple réponse

```json
{
  "zone": "parcelle-a",
  "risk_level": "high",
  "health_score": 62,
  "soil_trend": "declining",
  "predicted_soil_6h": 24.5,
  "hours_until_dry": 4.2,
  "irrigation_score": 72,
  "anomalies": [],
  "recommendations": ["Planifier irrigation dans les prochaines heures"],
  "suggested_threshold": 30,
  "auto_irrigate_recommended": false
}
```

## Algorithme

1. Charge les **N derniers** points SQLite (`telemetry`)
2. Calcule la **pente** humidité sol (%/h)
3. Extrapole à **+6 h** et estime **heures avant seuil**
4. Détecte **anomalies** (z-score sur deltas)
5. Génère **recommandations** contextuelles

Pas de GPU ni modèle externe — adapté à l'embarqué / edge cloud pédagogique.
