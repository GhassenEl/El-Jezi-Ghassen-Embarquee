# 04 — Mobile Flutter (IoT & embarqué)

Applications Flutter complémentaires aux projets embarqués (ESP32, capteurs, BLE, MQTT).

| Projet | Rôle | Package clé |
|--------|------|----------------|
| `sensor_dashboard` | Tableau de bord capteurs **BLE live** ou simulation + graphiques | `fl_chart`, `flutter_blue_plus` |
| `ble_scanner` | Scanner les périphériques BLE (ESP32, capteurs) | `flutter_blue_plus` |
| `iot_remote` | Télécommande LED / relais / PWM via **BLE réel** ESP32 | `flutter_blue_plus` |
| `mqtt_remote` | Télécommande LED / relais / PWM via **MQTT WiFi** | `mqtt_client` |
| `smart_farm` | **Smart Farm** — sol, irrigation, alertes via MQTT | `mqtt_client` |

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

## Prérequis

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.16+
- Téléphone Android / iOS ou émulateur
- BLE : Bluetooth + permissions (Android 12+)
- MQTT : téléphone et PC sur le même réseau WiFi

## Lancer un projet

```bash
cd sensor_dashboard   # ou ble_scanner / iot_remote / mqtt_remote / smart_farm
flutter pub get
flutter run
```

## Lien avec les projets embarqués

```
ESP32 (01-rtos)     ──BLE──────►  iot_remote / sensor_dashboard
ESP32 (05-iot-mqtt) ──MQTT─────►  mqtt_remote / dashboard web
Raspberry Pi        ──HTTP──────►  (extension future)
PC dashboard        ──série──────►  03-affichage-data
OLED SSD1306        ──I2C────────►  07-oled-ssd1306
```

## Permissions Android

- **BLE** (`ble_scanner`, `iot_remote`, `sensor_dashboard`) : `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`
- **MQTT** (`mqtt_remote`) : `INTERNET` + trafic HTTP clair local (`usesCleartextTraffic`)
