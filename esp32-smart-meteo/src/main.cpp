/**
 * El Jezi Ghassen — Smart Meteo ESP32
 * Station meteo simulee : T, HR, pression, vent, pluie, UV.
 * Queues FreeRTOS : cmdQueue, telemetryQueue, alertQueue.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef METEO_STATION
#define METEO_STATION "jardin"
#endif

static const char *TOPIC_TELEMETRY = "eljezi/meteo/telemetry";
static const char *TOPIC_COMMAND = "eljezi/meteo/command";
static const char *TOPIC_STATUS = "eljezi/meteo/status";
static const char *TOPIC_ALERT = "eljezi/meteo/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartMeteo";

static const size_t CMD_QUEUE_LEN = 6;
static const size_t TELEMETRY_QUEUE_LEN = 6;
static const size_t ALERT_QUEUE_LEN = 4;

enum class MeteoMode : uint8_t { Auto = 0, Manual };

struct CommandMsg {
  char text[24];
};

struct TelemetryMsg {
  float temp;
  float hum;
  float pressure;
  float windKmh;
  float rainMm;
  int uvIndex;
};

struct AlertMsg {
  char text[40];
};

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;
static QueueHandle_t g_alertQueue = nullptr;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct MeteoState {
  float temp = 22.0f;
  float hum = 60.0f;
  float pressure = 1013.0f;
  float windKmh = 8.0f;
  float rainMm = 0.0f;
  int uvIndex = 3;
  MeteoMode mode = MeteoMode::Auto;
  uint32_t tick = 0;
  bool mqttOk = false;
};

static MeteoState g_meteo;

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
  TelemetryMsg t{g_meteo.temp, g_meteo.hum, g_meteo.pressure, g_meteo.windKmh, g_meteo.rainMm, g_meteo.uvIndex};
  portEXIT_CRITICAL(&g_mux);
  return t;
}

static void publishMqttStatus() {
  if (!g_meteo.mqttOk) return;
  char buf[64];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf), "STATION=%s,ONLINE=1,MODE=%s",
           METEO_STATION, g_meteo.mode == MeteoMode::Auto ? "AUTO" : "MANUAL");
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void publishMqttTelemetry(const TelemetryMsg &t) {
  char buf[96];
  snprintf(buf, sizeof(buf), "STATION=%s,T=%.1f,H=%.1f,P=%.1f,W=%.1f,R=%.2f,UV=%d",
           METEO_STATION, t.temp, t.hum, t.pressure, t.windKmh, t.rainMm, t.uvIndex);
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttAlert(const char *alert) {
  char buf[80];
  snprintf(buf, sizeof(buf), "STATION=%s,ALERT=%s", METEO_STATION, alert);
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
  if (cmd == "RESET_RAIN") {
    portENTER_CRITICAL(&g_mux);
    g_meteo.rainMm = 0.0f;
    portEXIT_CRITICAL(&g_mux);
    Serial.println("[CMD] Pluviometre remis a zero");
    return;
  }
  if (cmd == "MODE_AUTO") {
    portENTER_CRITICAL(&g_mux);
    g_meteo.mode = MeteoMode::Auto;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_MANUAL") {
    portENTER_CRITICAL(&g_mux);
    g_meteo.mode = MeteoMode::Manual;
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
  Serial.printf("[MQTT] RX %s -> %s\n", topic, msg.c_str());
  handleCommand(msg);
}

static void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.printf("\n[WiFi] %s\n", WiFi.localIP().toString().c_str());
}

static void connectMqtt() {
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(256);
  while (!mqtt.connected()) {
    if (mqtt.connect(MQTT_CLIENT_ID)) {
      mqtt.subscribe(TOPIC_COMMAND);
      g_meteo.mqttOk = true;
      publishMqttStatus();
      Serial.println("[MQTT] Connecte");
    } else {
      delay(3000);
    }
  }
}

static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    g_meteo.tick++;
    const float phase = (float)(g_meteo.tick % 360) * 0.0174533f;
    g_meteo.temp = 20.0f + 6.0f * sinf(phase) + (float)(g_meteo.tick % 7) * 0.1f;
    g_meteo.hum = 55.0f + 15.0f * cosf(phase * 0.7f);
    g_meteo.pressure = 1013.0f + 4.0f * sinf(phase * 0.3f);
    g_meteo.windKmh = 5.0f + 12.0f * fabsf(sinf(phase * 1.2f));
    if (g_meteo.mode == MeteoMode::Auto && (g_meteo.tick % 40) < 3) {
      g_meteo.rainMm += 0.15f;
    }
    g_meteo.uvIndex = constrain((int)(3 + 4 * sinf(phase * 0.5f + 1.0f)), 0, 11);
    portEXIT_CRITICAL(&g_mux);

    enqueueTelemetry(snapshotTelemetry());
    vTaskDelay(pdMS_TO_TICKS(3000));
  }
}

static void taskAlerts(void *param) {
  (void)param;
  for (;;) {
    TelemetryMsg t = snapshotTelemetry();
    if (t.windKmh > 40.0f) {
      char buf[32];
      snprintf(buf, sizeof(buf), "WIND_HIGH,W=%.1f", t.windKmh);
      enqueueAlert(buf);
    }
    if (t.rainMm > 5.0f && (g_meteo.tick % 20) == 0) {
      char buf[32];
      snprintf(buf, sizeof(buf), "RAIN_HEAVY,R=%.2f", t.rainMm);
      enqueueAlert(buf);
    }
    if (t.temp > 35.0f) {
      char buf[32];
      snprintf(buf, sizeof(buf), "HEAT_WAVE,T=%.1f", t.temp);
      enqueueAlert(buf);
    }
    if (t.uvIndex >= 8) {
      enqueueAlert("UV_HIGH");
    }
    vTaskDelay(pdMS_TO_TICKS(5000));
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
      g_meteo.mqttOk = false;
      connectMqtt();
    }
    mqtt.loop();
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi — Smart Meteo ===");

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
