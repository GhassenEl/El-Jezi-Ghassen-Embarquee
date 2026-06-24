# 01 — RTOS (FreeRTOS)

## Projet : `esp32-freertos-blinky`

Deux files FreeRTOS + trois tâches sur ESP32 :

```
BLE write ──► cmdQueue ──► task_actuator ──► GPIO
task_sensor ──► telemetryQueue ──► task_comms ──► BLE notify + série
```

| Tâche | Rôle | Queue |
|-------|------|-------|
| `task_sensor` | Capteurs simulés (producteur) | → `telemetryQueue` |
| `task_actuator` | Commandes LED / relais / PWM | ← `cmdQueue` |
| `task_comms` | Notification BLE STATUS | ← `telemetryQueue` |

| File | Taille |
|------|--------|
| `cmdQueue` | 6 messages |
| `telemetryQueue` | 4 messages |

### BLE — protocole Flutter `iot_remote`

| Élément | Valeur |
|---------|--------|
| Nom appareil | `ElJezi-ESP32` |
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Commande (write) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Status (notify) | `beb5483e-36e1-4688-b7f5-ea07361b26a9` |

**Commandes :** `LED_ON`, `LED_OFF`, `RELAY_ON`, `RELAY_OFF`, `PWM_0`…`PWM_255`, `STATUS`  
**Status :** `T=24.5,H=55.0,V=3.30`

GPIO : LED **2**, relais **4**, PWM **5**.

### Matériel

- Carte **ESP32 DevKit** (LED sur GPIO 2 par défaut)

### Commandes

```bash
cd esp32-freertos-blinky
pio run              # compilation
pio run -t upload    # flash USB
pio device monitor   # console série 115200
```

### Concepts couverts

- `xTaskCreate`, priorités, `vTaskDelay`
- **Queues FreeRTOS** : `xQueueCreate`, `xQueueSend`, `xQueueReceive`
- Découplage producteur / consommateur (capteur ↔ comms, BLE ↔ GPIO)
