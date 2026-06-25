# 04 — Mobile Flutter (IoT & embarqué)

Applications Flutter complémentaires aux projets embarqués (ESP32, capteurs, BLE, MQTT).

| Projet | Rôle | Package clé |
|--------|------|----------------|
| `sensor_dashboard` | Tableau de bord capteurs **BLE live** ou simulation + graphiques | `fl_chart`, `flutter_blue_plus` |
| `ble_scanner` | Scanner les périphériques BLE (ESP32, capteurs) | `flutter_blue_plus` |
| `iot_remote` | Télécommande LED / relais / PWM via **BLE réel** ESP32 | `flutter_blue_plus` |
| `mqtt_remote` | Télécommande LED / relais / PWM via **MQTT WiFi** | `mqtt_client` |
| `smart_farm` | **Smart Farm** — sol, irrigation, alertes via MQTT | `mqtt_client` |
| `smart_meteo` | **Smart Meteo** — station meteo T/vent/pluie/UV via MQTT | `mqtt_client` |
| `smart_frigo` | **Smart Frigo** — refrigerateur T/porte/compresseur via MQTT | `mqtt_client` |
| `smart_home` | **Smart Home** — domotique + securite + **IA** (locale + cloud) | `mqtt_client`, `http` |
| `smart_station` | **Smart Station** — transport public ETA/affluence/alertes + **IA** (locale + cloud) | `mqtt_client`, `http` |

### Connexion ESP32 ↔ `iot_remote` (BLE)

1. Flasher `01-rtos/esp32-freertos-blinky`
2. Ouvrir `iot_remote` → **Scanner & connecter ESP32**
3. Appareil attendu : `ElJezi-ESP32`
4. Commandes : `LED_ON/OFF`, `RELAY_ON/OFF`, `PWM_0…255`, `STATUS`

### Connexion ESP32 ↔ `mqtt_remote` (MQTT)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Flasher `05-iot-mqtt/esp32-mqtt-sensors` (fichier `secrets.h`)
3. Ouvrir `mqtt_remote` → entrer l'**IP LAN du PC** (ex. `192.168.1.100:1883`)
4. Mêmes commandes et topics `eljezi/esp32/*`

### Connexion Smart Farm ↔ `smart_farm` (MQTT)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Flasher `09-smart-farm/esp32-smart-farm` (`secrets.h`)
3. Ouvrir `smart_farm` → IP broker (ex. `192.168.1.100`)
4. Topics `eljezi/smartfarm/*` — pompe, mode AUTO, seuil sol

### Connexion Smart Meteo ↔ `smart_meteo` (MQTT)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Flasher `10-smart-meteo/esp32-smart-meteo` (`secrets.h` — même IP broker)
3. Ouvrir `smart_meteo` → IP broker (ex. `192.168.1.100:1883`)
4. Topics `eljezi/meteo/*` — télémétrie, alertes, reset pluie, mode AUTO

```
Téléphone (smart_meteo)
    │ publish  eljezi/meteo/command
    │ subscribe eljezi/meteo/telemetry|status|alert
    ▼
Mosquitto (:1883)
    ▲
    │ MQTT
ESP32 esp32-smart-meteo
```

### Connexion Smart Frigo ↔ `smart_frigo` (MQTT)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Flasher `11-smart-frigo/esp32-smart-frigo` (`secrets.h`)
3. Ouvrir `smart_frigo` → IP broker (ex. `192.168.1.100:1883`)
4. Topics `eljezi/frigo/*` — temperatures, porte, compresseur, mode ECO

4. Topics `eljezi/frigo/*` — temperatures, porte, compresseur, mode ECO

### Connexion Smart Home ↔ `smart_home` (MQTT + IA)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Simulateur ou ESP32 : topics `eljezi/home/*` (5 zones)
3. Ouvrir `smart_home` → IP broker (ex. `192.168.1.100:1883`)
4. **Onglet IA** : confort, securite, energie (analyse locale)
5. **Optionnel** — API cloud IA (port **8120**) :

```bash
cd 13-smart-home/home-api
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8120
```

### Connexion Smart Station ↔ `smart_station` (MQTT + IA)

1. Lancer Mosquitto : `05-iot-mqtt/mosquitto`
2. Simulateur ou ESP32 : topics `eljezi/station/*`
3. Ouvrir `smart_station` → IP broker (ex. `192.168.1.100:1883`)
4. **Onglet IA** : analyse locale instantanee (retards, confort, alternatives)
5. **Optionnel** — API cloud IA (port **8130**) :

```bash
cd 15-smart-station/station-api
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8130
```

Dans l'app : URL `http://<IP_PC>:8130` → **Analyser via cloud**

## Prérequis

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.16+
- Téléphone Android / iOS ou émulateur
- BLE : Bluetooth + permissions (Android 12+)
- MQTT : téléphone et PC sur le même réseau WiFi

## Lancer un projet

```bash
cd sensor_dashboard   # ou ble_scanner / iot_remote / mqtt_remote / smart_farm / smart_meteo / smart_frigo / smart_home / smart_station
flutter pub get
flutter run
```

## Lien avec les projets embarqués

```
ESP32 (01-rtos)     ──BLE──────►  iot_remote / sensor_dashboard
ESP32 (05-iot-mqtt) ──MQTT─────►  mqtt_remote / dashboard web
ESP32 (09-smart-farm) ──MQTT───►  smart_farm / farm-dashboard
ESP32 (10-smart-meteo) ──MQTT──►  smart_meteo / meteo-dashboard
ESP32 (11-smart-frigo) ──MQTT──►  smart_frigo / frigo-dashboard
Raspberry Pi        ──HTTP──────►  (extension future)
PC dashboard        ──série──────►  03-affichage-data
OLED SSD1306        ──I2C────────►  07-oled-ssd1306
```

## Permissions Android

- **BLE** (`ble_scanner`, `iot_remote`, `sensor_dashboard`) : `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`
- **MQTT** (`mqtt_remote`, `smart_farm`, `smart_meteo`, `smart_frigo`, `smart_home`, `smart_station`) : `INTERNET` + trafic HTTP clair local (`usesCleartextTraffic`)
