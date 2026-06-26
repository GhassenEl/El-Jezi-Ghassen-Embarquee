/**
 * El Jezi Ghassen — Smart Refrigerateur ESP32
 * Capteurs frigo/congelateur simules, porte, compresseur, consommation.
 * Queues FreeRTOS : cmdQueue, telemetryQueue, alertQueue.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef FRIGO_ZONE
#define FRIGO_ZONE "cuisine"
#endif

static const gpio_num_t COMPRESSOR_GPIO = GPIO_NUM_4;
static const int DOOR_GPIO = 34;

static const char *TOPIC_TELEMETRY = "eljezi/frigo/telemetry";
static const char *TOPIC_COMMAND = "eljezi/frigo/command";
static const char *TOPIC_STATUS = "eljezi/frigo/status";
static const char *TOPIC_ALERT = "eljezi/frigo/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartFrigo";

static const size_t CMD_QUEUE_LEN = 8;
static const size_t TELEMETRY_QUEUE_LEN = 6;
static const size_t ALERT_QUEUE_LEN = 4;

enum class FrigoMode : uint8_t { Normal = 0, Eco };

struct CommandMsg {
  char text[28];
};

struct TelemetryMsg {
  float fridgeTemp;
  float freezerTemp;
  float humidity;
  bool doorOpen;
  bool compressorOn;
  int powerW;
};

struct AlertMsg {
  char text[48];
};

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;
static QueueHandle_t g_alertQueue = nullptr;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct FrigoState {
  float fridgeTemp = 4.0f;
  float freezerTemp = -18.0f;
  float humidity = 42.0f;
  bool doorOpen = false;
  bool compressorOn = false;
  int powerW = 85;
  float targetFridge = 4.0f;
  float targetFreezer = -18.0f;
  FrigoMode mode = FrigoMode::Normal;
  bool alarmMuted = false;
  uint32_t tick = 0;
  bool mqttOk = false;
  unsigned long doorOpenSinceMs = 0;
};

static FrigoState g_frigo;

static bool enqueueCommand(const char *cmd) {
  if (!g_cmdQueue || !cmd) return false;
  CommandMsg msg{};
  strncpy(msg.text, cmd, sizeof(msg.text) - 1);
  return xQueueSend(g_cmdQueue, &msg, pdMS_TO_TICKS(50)) == pdPASS;
}

static bool enqueueTelemetry(const TelemetryMsg &t) {
  if (!g_telemetryQueue) return false;
  return xQueueSend(g_telemetryQueue, &t, pdMS_TO_TICKS(50)) == pdPASS;
}

static bool enqueueAlert(const char *alert) {
  if (!g_alertQueue || !alert) return false;
  AlertMsg msg{};
  strncpy(msg.text, alert, sizeof(msg.text) - 1);
  return xQueueSend(g_alertQueue, &msg, pdMS_TO_TICKS(50)) == pdPASS;
}

static TelemetryMsg snapshotTelemetry() {
  portENTER_CRITICAL(&g_mux);
  TelemetryMsg t{g_frigo.fridgeTemp, g_frigo.freezerTemp, g_frigo.humidity,
                 g_frigo.doorOpen, g_frigo.compressorOn, g_frigo.powerW};
  portEXIT_CRITICAL(&g_mux);
  return t;
}

static void setCompressorLocked(bool on) {
  g_frigo.compressorOn = on;
  digitalWrite(COMPRESSOR_GPIO, on ? HIGH : LOW);
  g_frigo.powerW = on ? (g_frigo.mode == FrigoMode::Eco ? 70 : 120) : 8;
}

static void publishMqttStatus() {
  if (!g_frigo.mqttOk) return;
  char buf[96];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf),
           "ZONE=%s,ONLINE=1,MODE=%s,TARGET_F=%.0f,TARGET_Z=%.0f,ALARM=%d",
           FRIGO_ZONE, g_frigo.mode == FrigoMode::Eco ? "ECO" : "NORMAL",
           g_frigo.targetFridge, g_frigo.targetFreezer, g_frigo.alarmMuted ? 0 : 1);
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void publishMqttTelemetry(const TelemetryMsg &t) {
  char buf[112];
  snprintf(buf, sizeof(buf),
           "ZONE=%s,T=%.1f,F=%.1f,H=%.0f,DOOR=%d,COMP=%d,PWR=%d",
           FRIGO_ZONE, t.fridgeTemp, t.freezerTemp, t.humidity,
           t.doorOpen ? 1 : 0, t.compressorOn ? 1 : 0, t.powerW);
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttAlert(const char *alert) {
  char buf[80];
  snprintf(buf, sizeof(buf), "ZONE=%s,ALERT=%s", FRIGO_ZONE, alert);
  mqtt.publish(TOPIC_ALERT, buf);
}

static void handleCommand(const String &cmdRaw) {
  String cmd = cmdRaw;
  cmd.trim();
  cmd.toUpperCase();

  if (cmd == "STATUS") {
    publishMqttStatus();
    enqueueTelemetry(snapshotTelemetry());
    return;
  }
  if (cmd == "ALARM_OFF") {
    portENTER_CRITICAL(&g_mux);
    g_frigo.alarmMuted = true;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "ALARM_ON") {
    portENTER_CRITICAL(&g_mux);
    g_frigo.alarmMuted = false;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "MODE_ECO") {
    portENTER_CRITICAL(&g_mux);
    g_frigo.mode = FrigoMode::Eco;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_NORMAL") {
    portENTER_CRITICAL(&g_mux);
    g_frigo.mode = FrigoMode::Normal;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd.startsWith("SET_FRIDGE_")) {
    portENTER_CRITICAL(&g_mux);
    g_frigo.targetFridge = cmd.substring(11).toFloat();
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd.startsWith("SET_FREEZE_")) {
    portENTER_CRITICAL(&g_mux);
    g_frigo.targetFreezer = cmd.substring(11).toFloat();
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "DOOR_TOGGLE") {
    portENTER_CRITICAL(&g_mux);
    g_frigo.doorOpen = !g_frigo.doorOpen;
    if (g_frigo.doorOpen) g_frigo.doorOpenSinceMs = millis();
    portEXIT_CRITICAL(&g_mux);
  } else {
    Serial.printf("[CMD] Inconnue: %s\n", cmd.c_str());
    return;
  }
  publishMqttStatus();
}

static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  enqueueCommand(msg.c_str());
}

static void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) delay(500);
  Serial.printf("[WiFi] %s\n", WiFi.localIP().toString().c_str());
}

static void connectMqtt() {
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(256);
  while (!mqtt.connected()) {
    if (mqtt.connect(MQTT_CLIENT_ID)) {
      mqtt.subscribe(TOPIC_COMMAND);
      g_frigo.mqttOk = true;
      publishMqttStatus();
    } else {
      delay(3000);
    }
  }
}

static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    g_frigo.tick++;

    if ((g_frigo.tick % 50) == 0) {
      g_frigo.doorOpen = !g_frigo.doorOpen;
      if (g_frigo.doorOpen) g_frigo.doorOpenSinceMs = millis();
    }

    const float drift = g_frigo.doorOpen ? 0.15f : -0.05f;
    g_frigo.fridgeTemp += drift + (float)(g_frigo.tick % 5) * 0.02f;
    g_frigo.freezerTemp += drift * 0.5f;
    g_frigo.humidity = g_frigo.doorOpen ? 55.0f : 42.0f + (float)(g_frigo.tick % 7);

    const bool needCool = g_frigo.fridgeTemp > g_frigo.targetFridge + 0.5f ||
                          g_frigo.freezerTemp > g_frigo.targetFreezer + 1.0f;
    if (!g_frigo.doorOpen && needCool) {
      setCompressorLocked(true);
    } else if (g_frigo.fridgeTemp < g_frigo.targetFridge - 0.3f &&
               g_frigo.freezerTemp < g_frigo.targetFreezer - 0.5f) {
      setCompressorLocked(false);
    }
    if (g_frigo.doorOpen) setCompressorLocked(false);

    portEXIT_CRITICAL(&g_mux);
    enqueueTelemetry(snapshotTelemetry());
    vTaskDelay(pdMS_TO_TICKS(3000));
  }
}

static void taskAlerts(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    const bool muted = g_frigo.alarmMuted;
    const bool door = g_frigo.doorOpen;
    const unsigned long doorMs = g_frigo.doorOpenSinceMs;
    const float ft = g_frigo.fridgeTemp;
    const float fz = g_frigo.freezerTemp;
    const int pwr = g_frigo.powerW;
    portEXIT_CRITICAL(&g_mux);

    if (!muted) {
      if (door && doorMs > 0 && (millis() - doorMs) > 60000) {
        enqueueAlert("DOOR_OPEN_LONG");
      }
      if (ft > 8.0f) {
        char buf[32];
        snprintf(buf, sizeof(buf), "FRIDGE_TEMP_HIGH,T=%.1f", ft);
        enqueueAlert(buf);
      }
      if (fz > -12.0f) {
        char buf[32];
        snprintf(buf, sizeof(buf), "FREEZER_TEMP_HIGH,F=%.1f", fz);
        enqueueAlert(buf);
      }
      if (pwr > 150) {
        enqueueAlert("POWER_HIGH");
      }
    }
    vTaskDelay(pdMS_TO_TICKS(8000));
  }
}

static void taskActuator(void *param) {
  (void)param;
  CommandMsg msg{};
  for (;;) {
    if (xQueueReceive(g_cmdQueue, &msg, portMAX_DELAY) == pdTRUE) {
      handleCommand(String(msg.text));
    }
  }
}

static void taskComms(void *param) {
  (void)param;
  TelemetryMsg tel{};
  AlertMsg alert{};
  for (;;) {
    if (xQueueReceive(g_telemetryQueue, &tel, pdMS_TO_TICKS(200)) == pdTRUE) {
      publishMqttTelemetry(tel);
    }
    if (xQueueReceive(g_alertQueue, &alert, 0) == pdTRUE) {
      publishMqttAlert(alert.text);
    }
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

static void taskMqtt(void *param) {
  (void)param;
  for (;;) {
    if (!mqtt.connected()) {
      g_frigo.mqttOk = false;
      connectMqtt();
    }
    mqtt.loop();
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi — Smart Frigo ===");

  pinMode(COMPRESSOR_GPIO, OUTPUT);
  pinMode(DOOR_GPIO, INPUT);
  setCompressorLocked(false);

  g_cmdQueue = xQueueCreate(CMD_QUEUE_LEN, sizeof(CommandMsg));
  g_telemetryQueue = xQueueCreate(TELEMETRY_QUEUE_LEN, sizeof(TelemetryMsg));
  g_alertQueue = xQueueCreate(ALERT_QUEUE_LEN, sizeof(AlertMsg));

  connectWiFi();

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(taskAlerts, "task_alerts", 4096, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(taskActuator, "task_actuator", 4096, nullptr, 2, nullptr, 1);
  xTaskCreatePinnedToCore(taskComms, "task_comms", 4096, nullptr, 2, nullptr, 1);
  xTaskCreatePinnedToCore(taskMqtt, "task_mqtt", 8192, nullptr, 1, nullptr, 1);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
