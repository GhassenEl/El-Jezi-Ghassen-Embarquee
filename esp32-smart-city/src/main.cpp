/**
 * El Jezi Ghassen — Smart City ESP32
 * Passerelle urbaine : air, trafic, parking, eclairage, bruit, energie.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef CITY_ZONE
#define CITY_ZONE "centre-ville"
#endif

static const gpio_num_t LIGHT_GPIO = GPIO_NUM_4;

static const char *TOPIC_TELEMETRY = "eljezi/city/telemetry";
static const char *TOPIC_COMMAND = "eljezi/city/command";
static const char *TOPIC_STATUS = "eljezi/city/status";
static const char *TOPIC_ALERT = "eljezi/city/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartCity";

static const size_t CMD_QUEUE_LEN = 8;
static const size_t TELEMETRY_QUEUE_LEN = 6;
static const size_t ALERT_QUEUE_LEN = 4;

enum class CityMode : uint8_t { Normal = 0, Event, Alert };

struct CommandMsg { char text[28]; };

struct TelemetryMsg {
  int aqi;
  int pm25;
  int co2;
  int noiseDb;
  int trafficLevel;
  int parkingSpots;
  bool lightOn;
  float tempC;
  float humidity;
  int energyW;
};

struct AlertMsg { char text[48]; };

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;
static QueueHandle_t g_alertQueue = nullptr;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct CityState {
  int aqi = 42;
  int pm25 = 18;
  int co2 = 410;
  int noiseDb = 55;
  int trafficLevel = 2;
  int parkingSpots = 28;
  bool lightOn = true;
  float tempC = 24.0f;
  float humidity = 52.0f;
  int energyW = 1200;
  CityMode mode = CityMode::Normal;
  int alertLevel = 0;
  int servicesUp = 4;
  bool alarmMuted = false;
  uint32_t tick = 0;
  bool mqttOk = false;
};

static CityState g_city;

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
  TelemetryMsg t{g_city.aqi, g_city.pm25, g_city.co2, g_city.noiseDb,
                 g_city.trafficLevel, g_city.parkingSpots, g_city.lightOn,
                 g_city.tempC, g_city.humidity, g_city.energyW};
  portEXIT_CRITICAL(&g_mux);
  return t;
}

static const char *modeName(CityMode m) {
  switch (m) {
    case CityMode::Event: return "EVENT";
    case CityMode::Alert: return "ALERT";
    default: return "NORMAL";
  }
}

static void setLightLocked(bool on, bool eco = false) {
  g_city.lightOn = on;
  digitalWrite(LIGHT_GPIO, on ? HIGH : LOW);
  g_city.energyW = (on ? (eco ? 800 : 1400) : 200) + g_city.trafficLevel * 120;
}

static void publishMqttStatus() {
  if (!g_city.mqttOk) return;
  char buf[96];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf),
           "ZONE=%s,ONLINE=1,MODE=%s,ALERT_LVL=%d,SERVICES=%d",
           CITY_ZONE, modeName(g_city.mode), g_city.alertLevel, g_city.servicesUp);
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void publishMqttTelemetry(const TelemetryMsg &t) {
  char buf[160];
  snprintf(buf, sizeof(buf),
           "ZONE=%s,AQI=%d,PM25=%d,CO2=%d,NOISE=%d,TRAFFIC=%d,PARK=%d,LIGHT=%d,T=%.1f,H=%.0f,ENERGY=%d,BUS=%d,WIFI=%d,CROWD=%d",
           CITY_ZONE, t.aqi, t.pm25, t.co2, t.noiseDb, t.trafficLevel,
           t.parkingSpots, t.lightOn ? 1 : 0, t.tempC, t.humidity, t.energyW,
           t.trafficLevel + 2, 80 + t.trafficLevel * 15, min(5, t.trafficLevel));
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttAlert(const char *alert) {
  char buf[80];
  snprintf(buf, sizeof(buf), "ZONE=%s,ALERT=%s", CITY_ZONE, alert);
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
    g_city.alarmMuted = true;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "ALARM_ON") {
    portENTER_CRITICAL(&g_mux);
    g_city.alarmMuted = false;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "LIGHT_ON") {
    portENTER_CRITICAL(&g_mux);
    setLightLocked(true, false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "LIGHT_ECO") {
    portENTER_CRITICAL(&g_mux);
    setLightLocked(true, true);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "LIGHT_OFF") {
    portENTER_CRITICAL(&g_mux);
    setLightLocked(false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_NORMAL") {
    portENTER_CRITICAL(&g_mux);
    g_city.mode = CityMode::Normal;
    g_city.alertLevel = 0;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_EVENT") {
    portENTER_CRITICAL(&g_mux);
    g_city.mode = CityMode::Event;
    g_city.alertLevel = 1;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_ALERT") {
    portENTER_CRITICAL(&g_mux);
    g_city.mode = CityMode::Alert;
    g_city.alertLevel = 2;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "TRAFFIC_SYNC") {
    portENTER_CRITICAL(&g_mux);
    g_city.trafficLevel = max(1, g_city.trafficLevel - 1);
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
  mqtt.setBufferSize(320);
  while (!mqtt.connected()) {
    if (mqtt.connect(MQTT_CLIENT_ID)) {
      mqtt.subscribe(TOPIC_COMMAND);
      g_city.mqttOk = true;
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
    g_city.tick++;

    const float phase = sinf((float)g_city.tick * 0.07f);
    g_city.tempC = 24.0f + 4.0f * phase;
    g_city.humidity = 50.0f + 10.0f * cosf((float)g_city.tick * 0.05f);
    g_city.pm25 = 15 + (int)(8 * (phase + 1.0f));
    g_city.co2 = 400 + (int)(30 * (phase + 1.0f));
    g_city.aqi = 35 + g_city.pm25 + (g_city.trafficLevel * 8);
    g_city.noiseDb = 50 + g_city.trafficLevel * 6 + (g_city.tick % 5);
    g_city.trafficLevel = 1 + (g_city.tick / 20) % 4;
    g_city.parkingSpots = max(0, 35 - (g_city.tick % 40));

    if (g_city.mode == CityMode::Event) {
      g_city.trafficLevel = min(4, g_city.trafficLevel + 1);
      g_city.noiseDb += 5;
    }

    setLightLocked(g_city.lightOn, g_city.mode == CityMode::Normal);
    portEXIT_CRITICAL(&g_mux);
    enqueueTelemetry(snapshotTelemetry());
    vTaskDelay(pdMS_TO_TICKS(3000));
  }
}

static void taskAlerts(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    const bool muted = g_city.alarmMuted;
    const int aqi = g_city.aqi;
    const int traffic = g_city.trafficLevel;
    const int noise = g_city.noiseDb;
    const int park = g_city.parkingSpots;
    portEXIT_CRITICAL(&g_mux);

    if (!muted) {
      if (aqi > 100) enqueueAlert("AIR_QUALITY_BAD");
      if (traffic >= 4) enqueueAlert("TRAFFIC_JAM");
      if (noise > 75) enqueueAlert("NOISE_HIGH");
      if (park < 5) enqueueAlert("PARKING_FULL");
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
      g_city.mqttOk = false;
      connectMqtt();
    }
    mqtt.loop();
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi — Smart City ===");

  pinMode(LIGHT_GPIO, OUTPUT);
  setLightLocked(true);

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
