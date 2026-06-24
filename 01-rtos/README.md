# 01 — RTOS (FreeRTOS)

## Projet : `esp32-freertos-blinky`

Deux tâches FreeRTOS sur ESP32 :

| Tâche | Rôle | Période |
|-------|------|---------|
| `task_led` | Clignote la LED intégrée (GPIO 2) | 500 ms |
| `task_sensor` | Lit une valeur « température » simulée et l'affiche sur le moniteur série | 1 s |

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
- Boucle superviseur vs multitâche préemptif
- Sérialisation des logs via `Serial`
