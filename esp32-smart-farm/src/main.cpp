/**
 * El Jezi Ghassen — Smart Farm ESP32
 * Capteurs sol / air / lumière simulés, irrigation MQTT, mode AUTO/MANUAL.
 *
 * Queues FreeRTOS :
 *   cmdQueue       → task_actuator (pompe, seuils, mode)
 *   telemetryQueue → task_comms (publish MQTT)
 *   alertQueue     → task_comms (alertes irrigation)
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef FARM_ZONE
#define FARM_ZONE "parcelle-a"
#endif

static const gpio_num_t PUMP_GPIO = GPIO_NUM_4;
static const int SOIL_ADC_GPIO = 34;

static const char *TOPIC_TELEMETRY = "eljezi/smartfarm/telemetry";
static const char *TOPIC_COMMAND = "eljezi/smartfarm/command";
static const char *TOPIC_STATUS = "eljezi/smartfarm/status";
static const char *TOPIC_ALERT = "eljezi/smartfarm/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartFarm";

static const size_t CMD_QUEUE_LEN = 8;
static const size_t TELEMETRY_QUEUE_LEN = 6;
static const size_t ALERT_QUEUE_LEN = 4;

enum class FarmMode : uint8_t { Auto = 0, Manual };

struct CommandMsg {
  char text[24];
};

struct TelemetryMsg {
  float airTemp;
  float airHum;
  float soilMoist;
  int lightLux;
  bool pumpOn;
  FarmMode mode;
};

struct AlertMsg {
  char text[32];
};

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;
static QueueHandle_t g_alertQueue = nullptr;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct FarmState {
  float airTemp = 24.0f;
  float airHum = 55.0f;
  float soilMoist = 45.0f;
  int lightLux = 8000;
  bool pumpOn = false;
  FarmMode mode = FarmMode::Auto;
  uint8_t soilThresh = 30;
  uint32_t tick = 0;
  bool wifiOk = false;
  bool mqttOk = false;
  unsigned long pumpStartedMs = 0;
};

static FarmState g_farm;
static unsigned long g_lastDryWarnMs = 0;

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
  TelemetryMsg t{
      g_farm.airTemp, g_farm.airHum, g_farm.soilMoist, g_farm.lightLux,
      g_farm.pumpOn, g_farm.mode};
  portEXIT_CRITICAL(&g_mux);
  return t;
}

static void setPumpLocked(bool on) {
  g_farm.pumpOn = on;
  digitalWrite(PUMP_GPIO, on ? HIGH : LOW);
  if (on) g_farm.pumpStartedMs = millis();
}

static void publishMqttStatus() {
  if (!g_farm.mqttOk) return;
  char buf[64];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf), "ZONE=%s,PUMP=%d,MODE=%s,THRESH=%u",
           FARM_ZONE, g_farm.pumpOn ? 1 : 0,
           g_farm.mode == FarmMode::Auto ? "AUTO" : "MANUAL", g_farm.soilThresh);
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void processCommand(const CommandMsg &incoming) {
  String cmd = String(incoming.text);
  cmd.trim();
  cmd.toUpperCase();

  bool changed = false;
  bool publishTel = false;

  portENTER_CRITICAL(&g_mux);
  if (cmd == "PUMP_ON") {
    if (g_farm.mode == FarmMode::Manual) {
      setPumpLocked(true);
      changed = true;
    }
  } else if (cmd == "PUMP_OFF") {
    setPumpLocked(false);
    changed = true;
  } else if (cmd == "MODE_AUTO") {
    g_farm.mode = FarmMode::Auto;
    changed = true;
  } else if (cmd == "MODE_MANUAL") {
    g_farm.mode = FarmMode::Manual;
  } else if (cmd.startsWith("SET_THRESH_")) {
    int v = cmd.substring(11).toInt();
    if (v >= 10 && v <= 80) {
      g_farm.soilThresh = (uint8_t)v;
      changed = true;
    }
  } else if (cmd == "STATUS") {
    publishTel = true;
  } else {
    portEXIT_CRITICAL(&g_mux);
    Serial.printf("[CMD] Inconnue: %s\n", cmd.c_str());
    return;
  }
  portEXIT_CRITICAL(&g_mux);

  if (changed) {
    publishMqttStatus();
    Serial.printf("[CMD] OK %s\n", cmd.c_str());
    if (cmd == "PUMP_ON") enqueueAlert("IRRIGATION_START");
    if (cmd == "PUMP_OFF") enqueueAlert("IRRIGATION_STOP");
  }
  if (publishTel || changed) enqueueTelemetry(snapshotTelemetry());
}

static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  char buf[32];
  size_t n = length < sizeof(buf) - 1 ? length : sizeof(buf) - 1;
  memcpy(buf, payload, n);
  buf[n] = '\0';
  enqueueCommand(buf);
}

static void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("[WiFi] Connexion %s ...\n", WIFI_SSID);
  uint8_t n = 0;
  while (WiFi.status() != WL_CONNECTED && n < 60) {
    delay(500);
    Serial.print('.');
    n++;
  }
  const bool ok = WiFi.status() == WL_CONNECTED;
  portENTER_CRITICAL(&g_mux);
  g_farm.wifiOk = ok;
  portEXIT_CRITICAL(&g_mux);
  if (ok) Serial.printf("\n[WiFi] OK %s\n", WiFi.localIP().toString().c_str());
  else Serial.println("\n[WiFi] Echec");
}

static void connectMqtt() {
  if (!g_farm.wifiOk || mqtt.connected()) return;
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(384);
  if (mqtt.connect(MQTT_CLIENT_ID)) {
    mqtt.subscribe(TOPIC_COMMAND);
    portENTER_CRITICAL(&g_mux);
    g_farm.mqttOk = true;
    portEXIT_CRITICAL(&g_mux);
    Serial.println("[MQTT] Connecte smartfarm");
    publishMqttStatus();
  }
}

static void simulateSensors() {
  portENTER_CRITICAL(&g_mux);
  g_farm.airTemp = 18.0f + (float)(g_farm.tick % 120) / 10.0f;
  g_farm.airHum = 45.0f + (float)(g_farm.tick % 35);
  const int hour = (g_farm.tick / 30) % 24;
  g_farm.lightLux = (hour >= 6 && hour < 20) ? 6000 + (g_farm.tick % 4000) : 120 + (g_farm.tick % 80);

  if (g_farm.pumpOn) {
    g_farm.soilMoist += 1.2f;
    if (g_farm.soilMoist > 85.0f) g_farm.soilMoist = 85.0f;
  } else {
    g_farm.soilMoist -= 0.4f;
    if (g_farm.soilMoist < 8.0f) g_farm.soilMoist = 8.0f;
  }
  g_farm.tick++;
  portEXIT_CRITICAL(&g_mux);
}

static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    simulateSensors();
    enqueueTelemetry(snapshotTelemetry());
    vTaskDelay(pdMS_TO_TICKS(3000));
  }
}

static void taskActuator(void *param) {
  (void)param;
  CommandMsg msg;
  for (;;) {
    if (xQueueReceive(g_cmdQueue, &msg, portMAX_DELAY) == pdPASS) {
      processCommand(msg);
    }
  }
}

static void taskIrrigation(void *param) {
  (void)param;
  for (;;) {
    bool autoMode = false;
    bool pumpOn = false;
    float soil = 0;
    uint8_t thresh = 0;
    unsigned long pumpStart = 0;

    portENTER_CRITICAL(&g_mux);
    autoMode = g_farm.mode == FarmMode::Auto;
    pumpOn = g_farm.pumpOn;
    soil = g_farm.soilMoist;
    thresh = g_farm.soilThresh;
    pumpStart = g_farm.pumpStartedMs;
    portEXIT_CRITICAL(&g_mux);

    if (autoMode) {
      if (!pumpOn && soil < (float)thresh) {
        portENTER_CRITICAL(&g_mux);
        setPumpLocked(true);
        portEXIT_CRITICAL(&g_mux);
        enqueueAlert("SOIL_DRY_AUTO_START");
        publishMqttStatus();
        enqueueTelemetry(snapshotTelemetry());
      } else if (pumpOn) {
        const bool maxTime = (millis() - pumpStart) > 45000;
        const bool soilOk = soil >= (float)thresh + 8.0f;
        if (maxTime || soilOk) {
          portENTER_CRITICAL(&g_mux);
          setPumpLocked(false);
          portEXIT_CRITICAL(&g_mux);
          enqueueAlert(soilOk ? "SOIL_OK_AUTO_STOP" : "IRRIGATION_TIMEOUT");
          publishMqttStatus();
          enqueueTelemetry(snapshotTelemetry());
        }
      }
    }

    if (!pumpOn && soil < (float)thresh - 5) {
      const unsigned long now = millis();
      if (now - g_lastDryWarnMs > 30000) {
        enqueueAlert("SOIL_DRY_WARNING");
        g_lastDryWarnMs = now;
      }
    }

    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

static void taskComms(void *param) {
  (void)param;
  for (;;) {
    TelemetryMsg tel;
    if (xQueueReceive(g_telemetryQueue, &tel, pdMS_TO_TICKS(500)) == pdPASS) {
      char buf[96];
      snprintf(buf, sizeof(buf),
               "ZONE=%s,T=%.1f,H=%.1f,S=%.1f,L=%d,PUMP=%d,MODE=%s",
               FARM_ZONE, tel.airTemp, tel.airHum, tel.soilMoist, tel.lightLux,
               tel.pumpOn ? 1 : 0, tel.mode == FarmMode::Auto ? "AUTO" : "MANUAL");
      Serial.printf("[TELEM] %s\n", buf);
      if (g_farm.mqttOk) mqtt.publish(TOPIC_TELEMETRY, buf);
    }

    AlertMsg alert;
    if (xQueueReceive(g_alertQueue, &alert, 0) == pdPASS) {
      char buf[64];
      snprintf(buf, sizeof(buf), "ZONE=%s,ALERT=%s", FARM_ZONE, alert.text);
      Serial.printf("[ALERT] %s\n", buf);
      if (g_farm.mqttOk) mqtt.publish(TOPIC_ALERT, buf);
    }
  }
}

static void taskMqtt(void *param) {
  (void)param;
  for (;;) {
    if (g_farm.wifiOk) {
      if (!mqtt.connected()) connectMqtt();
      else mqtt.loop();
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi Ghassen — Smart Farm ===");
  Serial.printf("[FARM] Zone: %s\n", FARM_ZONE);

  g_cmdQueue = xQueueCreate(CMD_QUEUE_LEN, sizeof(CommandMsg));
  g_telemetryQueue = xQueueCreate(TELEMETRY_QUEUE_LEN, sizeof(TelemetryMsg));
  g_alertQueue = xQueueCreate(ALERT_QUEUE_LEN, sizeof(AlertMsg));

  pinMode(PUMP_GPIO, OUTPUT);
  pinMode(SOIL_ADC_GPIO, INPUT);
  digitalWrite(PUMP_GPIO, LOW);

  connectWiFi();

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 2, nullptr, 0);
  xTaskCreatePinnedToCore(taskActuator, "task_actuator", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(taskIrrigation, "task_irrigation", 4096, nullptr, 2, nullptr, 0);
  xTaskCreatePinnedToCore(taskComms, "task_comms", 6144, nullptr, 2, nullptr, 1);
  xTaskCreatePinnedToCore(taskMqtt, "task_mqtt", 8192, nullptr, 1, nullptr, 1);

  Serial.println("[OK] PUMP_ON/OFF MODE_AUTO/MANUAL SET_THRESH_30 STATUS");
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(5000));
}
