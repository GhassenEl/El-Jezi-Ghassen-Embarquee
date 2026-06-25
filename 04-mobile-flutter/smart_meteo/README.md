# smart_meteo — App mobile Smart Meteo

Application Flutter pour piloter et surveiller la station **10-smart-meteo** via MQTT.

## Lien avec le projet embarqué

```
ESP32 (esp32-smart-meteo) ──MQTT──► Mosquitto ──► smart_meteo (mobile)
                         topics eljezi/meteo/*
```

| Topic MQTT | Rôle mobile |
|------------|-------------|
| `eljezi/meteo/telemetry` | Affichage T°, HR, pression, vent, pluie, UV |
| `eljezi/meteo/status` | Station en ligne, mode AUTO/MANUEL |
| `eljezi/meteo/alert` | Liste alertes vent / pluie / chaleur / UV |
| `eljezi/meteo/command` | Envoi STATUS, RESET_RAIN, MODE_AUTO… |

## Prérequis

- Flutter 3.16+
- Téléphone et PC sur le **même réseau WiFi**
- Mosquitto lancé : `05-iot-mqtt/mosquitto`
- ESP32 flashé : `10-smart-meteo/esp32-smart-meteo`

## Démarrage

```bash
# 1. Broker + ESP32 (sur PC)
cd ../../05-iot-mqtt/mosquitto && docker compose up -d
cd ../../10-smart-meteo/esp32-smart-meteo && pio run -t upload

# 2. App mobile
cd ../../04-mobile-flutter/smart_meteo
flutter pub get
flutter run
```

## Connexion dans l'app

1. Ouvrir **smart_meteo**
2. Entrer l'**IP LAN du PC** Mosquitto (ex. `192.168.1.100`)
3. Port **1883**
4. Appuyer sur **Connecter à la station**
5. Les mesures arrivent toutes les ~3 s depuis l'ESP32

## Commandes disponibles

| Bouton | Commande MQTT |
|--------|---------------|
| Rafraîchir | `STATUS` |
| Reset pluie | `RESET_RAIN` |
| Mode AUTO | `MODE_AUTO` |
| Mode MANUEL | `MODE_MANUAL` |

## Android

`AndroidManifest.xml` inclut `INTERNET` et `usesCleartextTraffic` pour MQTT local sans TLS.

## Voir aussi

- [10-smart-meteo/README.md](../../10-smart-meteo/README.md) — projet complet
- [meteo-dashboard](../../10-smart-meteo/meteo-dashboard/) — dashboard web port 5080
