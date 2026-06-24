# El Jezi Ghassen — Embarquée

Espace de projets simples autour du **système embarqué** : RTOS, Linux embarqué et affichage de données capteurs.

## Structure

| Dossier | Thème | Projet | Cible |
|---------|--------|--------|--------|
| `01-rtos/` | Temps réel | `esp32-freertos-blinky` | ESP32 + FreeRTOS (PlatformIO) |
| `02-linux-embarque/` | Linux embarqué | `gpio-sysfs` | Raspberry Pi / board Linux (sysfs GPIO) |
| `03-affichage-data/` | Affichage data | `dashboard-capteurs` | PC (Python) — simulation + port série |

## Prérequis globaux

- **RTOS** : [PlatformIO](https://platformio.org/) + carte ESP32 (ex. DevKit)
- **Linux** : toolchain `gcc` sur la cible ARM (ou cross-compile)
- **Affichage** : Python 3.10+ (`pip install -r requirements.txt`)

## Démarrage rapide

```bash
# RTOS — compiler et flasher l'ESP32
cd 01-rtos/esp32-freertos-blinky
pio run -t upload && pio device monitor

# Linux embarqué — sur Raspberry Pi
cd 02-linux-embarque/gpio-sysfs
make && sudo ./build/gpio-blink 17

# Affichage data — sur PC
cd 03-affichage-data/dashboard-capteurs
pip install -r requirements.txt
python main.py
```

## Auteur

**Ghassen El Jezi** — projets pédagogiques embarqué (RTOS, Linux, IHM data).
