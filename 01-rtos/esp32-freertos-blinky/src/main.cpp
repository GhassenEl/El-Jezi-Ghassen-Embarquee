/**
 * El Jezi Ghassen Embarquée — RTOS
 * Deux tâches FreeRTOS : LED + capteur simulé.
 */
#include <Arduino.h>

static const gpio_num_t LED_GPIO = GPIO_NUM_2;

static void taskLed(void *param) {
  (void)param;
  pinMode(LED_GPIO, OUTPUT);
  for (;;) {
    digitalWrite(LED_GPIO, !digitalRead(LED_GPIO));
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

static void taskSensor(void *param) {
  (void)param;
  uint32_t tick = 0;
  for (;;) {
    /* Simulation température 20–30 °C (remplacer par DHT22 / I2C) */
    const float temp = 20.0f + (float)(tick % 100) / 10.0f;
    Serial.printf("[sensor] T=%.1f C  heap=%u\n", temp, ESP.getFreeHeap());
    tick++;
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== El Jezi Ghassen Embarquee — FreeRTOS ===");

  xTaskCreatePinnedToCore(taskLed, "task_led", 2048, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 1, nullptr, 1);
}

void loop() {
  vTaskDelete(nullptr);
}
