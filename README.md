# 03 — Affichage de données

## Projet : `dashboard-capteurs`

Tableau de bord Python affichant en temps réel :

- **Température** (°C)
- **Humidité** (%)
- **Tension** (V)

### Modes

| Mode | Commande | Description |
|------|----------|-------------|
| Simulation | `python main.py` | Données générées localement (démo sans matériel) |
| Série | `python main.py --port COM3` | Lecture lignes `T=24.5,H=60.2,V=3.30` depuis UART |

Format attendu sur le port série (compatible sortie ESP32 du projet RTOS étendu) :

```text
T=24.5,H=60.2,V=3.30
```

### Installation

```bash
cd dashboard-capteurs
pip install -r requirements.txt
python main.py
```

### Concepts couverts

- Acquisition périodique (timer matplotlib)
- Ring buffer des N derniers échantillons
- Séparation source données / affichage (préparation driver embarqué)
