# 04 — Mobile Flutter (IoT & embarqué)

Applications Flutter complémentaires aux projets embarqués (ESP32, capteurs, BLE).

| Projet | Rôle | Package clé |
|--------|------|----------------|
| `sensor_dashboard` | Tableau de bord capteurs (T°, humidité, tension) + graphiques | `fl_chart` |
| `ble_scanner` | Scanner les périphériques BLE (ESP32, capteurs) | `flutter_blue_plus` |
| `iot_remote` | Télécommande LED / relais / PWM via **BLE réel** ESP32 | `flutter_blue_plus` |

### Connexion ESP32 ↔ `iot_remote`

1. Flasher `01-rtos/esp32-freertos-blinky`
2. Ouvrir `iot_remote` → **Scanner & connecter ESP32**
3. Appareil attendu : `ElJezi-ESP32`
4. Commandes : `LED_ON/OFF`, `RELAY_ON/OFF`, `PWM_0…255`, `STATUS`
5. Notifications : `T=24.5,H=55.0,V=3.30`

## Prérequis

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.16+
- Téléphone Android / iOS ou émulateur
- Pour BLE réel : Bluetooth activé + permissions (Android 12+)

## Lancer un projet

```bash
cd sensor_dashboard   # ou ble_scanner / iot_remote
flutter pub get
flutter run
```

## Lien avec les projets embarqués

```
ESP32 (01-rtos)  ──BLE/UART──►  Flutter mobile (04)
Raspberry Pi     ──HTTP──────►  (extension future)
PC dashboard     ──série──────►  03-affichage-data
```

## Permissions Android (BLE)

Déjà configurées dans `ble_scanner` et `iot_remote` :
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`
