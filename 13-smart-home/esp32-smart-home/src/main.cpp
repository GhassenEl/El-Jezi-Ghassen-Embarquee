/**
 * El Jezi Ghassen — Smart Home ESP32
 * Salon connecte : temperature, luminosite, mouvement, porte, eclairage, chauffage.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef HOME_ZONE
#define HOME_ZONE "salon"
#endif

static const gpio_num_t LIGHT_GPIO = GPIO_NUM_4;
static const gpio_num_t HEAT_GPIO = GPIO_NUM_5;
static const int MOTION_GPIO = 34;
static const int DOOR_GPIO = 35;

static const char *TOPIC_TELEMETRY = "eljezi/home/telemetry";
static const char *TOPIC_COMMAND = "eljezi/home/command";
static const char *TOPIC_STATUS = "eljezi/home/status";
static const char *TOPIC_ALERT = "eljezi/home/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartHome";

static const size_t CMD_QUEUE_LEN = 8;
static const size_t TELEMETRY_QUEUE_LEN = 6;
static const size_t ALERT_QUEUE_LEN = 4;

enum class HomeMode : uint8_t { Home = 0, Away, Sleep };

struct CommandMsg { char text[28]; };

struct TelemetryMsg {
  float tempC;
  float humidity;
  int lux;
  bool motion;
  bool doorOpen;
  bool lightOn;
  bool heatOn;
  int powerW;
};

struct AlertMsg { char text[48]; };

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;
static QueueHandle_t g_alertQueue = nullptr;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct HomeState {
  float tempC = 22.0f;
  float humidity = 48.0f;
  int lux = 320;
  bool motion = false;
  bool doorOpen = false;
  bool lightOn = false;
  bool heatOn = false;
  bool doorLocked = true;
  int powerW = 120;
  float targetTemp = 22.0f;
  HomeMode mode = HomeMode::Home;
  bool alarmMuted = false;
  uint32_t tick = 0;
  bool mqttOk = false;
  unsigned long doorOpenSinceMs = 0;
};

static HomeState g_home;

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
  TelemetryMsg t{g_home.tempC, g_home.humidity, g_home.lux, g_home.motion,
                 g_home.doorOpen, g_home.lightOn, g_home.heatOn, g_home.powerW};
  portEXIT_CRITICAL(&g_mux);
  return t;
}

static const char *modeName(HomeMode m) {
  switch (m) {
    case HomeMode::Away: return "AWAY";
    case HomeMode::Sleep: return "SLEEP";
    default: return "HOME";
  }
}

static void setLightLocked(bool on) {
  g_home.lightOn = on;
  digitalWrite(LIGHT_GPIO, on ? HIGH : LOW);
  g_home.lux = on ? 480 + (g_home.tick % 40) : 40 + (g_home.tick % 15);
  g_home.powerW = (g_home.heatOn ? 850 : 80) + (on ? 45 : 0) + (g_home.motion ? 12 : 0);
}

static void setHeatLocked(bool on) {
  g_home.heatOn = on;
  digitalWrite(HEAT_GPIO, on ? HIGH : LOW);
  g_home.powerW = (on ? 850 : 80) + (g_home.lightOn ? 45 : 0) + (g_home.motion ? 12 : 0);
}

static void publishMqttStatus() {
  if (!g_home.mqttOk) return;
  char buf[96];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf),
           "ZONE=%s,ONLINE=1,MODE=%s,TARGET_T=%.0f,ALARM=%d,LOCK=%d",
           HOME_ZONE, modeName(g_home.mode), g_home.targetTemp,
           g_home.alarmMuted ? 0 : 1, g_home.doorLocked ? 1 : 0);
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void publishMqttTelemetry(const TelemetryMsg &t) {
  char buf[128];
  snprintf(buf, sizeof(buf),
           "ZONE=%s,T=%.1f,H=%.0f,LUX=%d,MOTION=%d,DOOR=%d,LIGHT=%d,HEAT=%d,PWR=%d",
           HOME_ZONE, t.tempC, t.humidity, t.lux, t.motion ? 1 : 0,
           t.doorOpen ? 1 : 0, t.lightOn ? 1 : 0, t.heatOn ? 1 : 0, t.powerW);
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttAlert(const char *alert) {
  char buf[80];
  snprintf(buf, sizeof(buf), "ZONE=%s,ALERT=%s", HOME_ZONE, alert);
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
    g_home.alarmMuted = true;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "ALARM_ON") {
    portENTER_CRITICAL(&g_mux);
    g_home.alarmMuted = false;
    portEXIT_CRITICAL(&g_mux);
    publishMqttStatus();
    return;
  }
  if (cmd == "LIGHT_ON") {
    portENTER_CRITICAL(&g_mux);
    setLightLocked(true);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "LIGHT_OFF") {
    portENTER_CRITICAL(&g_mux);
    setLightLocked(false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "HEAT_ON") {
    portENTER_CRITICAL(&g_mux);
    setHeatLocked(true);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "HEAT_OFF") {
    portENTER_CRITICAL(&g_mux);
    setHeatLocked(false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_HOME") {
    portENTER_CRITICAL(&g_mux);
    g_home.mode = HomeMode::Home;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_AWAY") {
    portENTER_CRITICAL(&g_mux);
    g_home.mode = HomeMode::Away;
    setLightLocked(false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "MODE_SLEEP") {
    portENTER_CRITICAL(&g_mux);
    g_home.mode = HomeMode::Sleep;
    setLightLocked(false);
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "LOCK_ON") {
    portENTER_CRITICAL(&g_mux);
    g_home.doorLocked = true;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "LOCK_OFF") {
    portENTER_CRITICAL(&g_mux);
    g_home.doorLocked = false;
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd.startsWith("SET_TEMP_")) {
    portENTER_CRITICAL(&g_mux);
    g_home.targetTemp = cmd.substring(9).toFloat();
    portEXIT_CRITICAL(&g_mux);
  } else if (cmd == "DOOR_TOGGLE") {
    portENTER_CRITICAL(&g_mux);
    g_home.doorOpen = !g_home.doorOpen;
    if (g_home.doorOpen) g_home.doorOpenSinceMs = millis();
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
      g_home.mqttOk = true;
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
    g_home.tick++;

    g_home.motion = (g_home.tick % 17) < 5 || digitalRead(MOTION_GPIO) == HIGH;
    if ((g_home.tick % 55) == 0) {
      g_home.doorOpen = !g_home.doorOpen;
      if (g_home.doorOpen) g_home.doorOpenSinceMs = millis();
    }

    const float dayCycle = sinf((float)g_home.tick * 0.08f);
    g_home.tempC = g_home.targetTemp + dayCycle * 0.8f + (g_home.heatOn ? 0.4f : -0.2f);
    g_home.humidity = 45.0f + 8.0f * cosf((float)g_home.tick * 0.05f);

    if (g_home.mode == HomeMode::Sleep && !g_home.lightOn) {
      g_home.lux = 15 + (g_home.tick % 8);
    } else if (!g_home.lightOn) {
      g_home.lux = 80 + (int)(40 * (dayCycle + 1.0f));
    }

    if (g_home.heatOn && g_home.tempC < g_home.targetTemp) {
      g_home.tempC += 0.15f;
    } else if (!g_home.heatOn && g_home.tempC > g_home.targetTemp) {
      g_home.tempC -= 0.08f;
    }

    if (g_home.mode == HomeMode::Away) {
      setLightLocked(false);
      setHeatLocked(false);
    }

    portEXIT_CRITICAL(&g_mux);
    enqueueTelemetry(snapshotTelemetry());
    vTaskDelay(pdMS_TO_TICKS(3000));
  }
}

static void taskAlerts(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    const bool muted = g_home.alarmMuted;
    const bool motion = g_home.motion;
    const bool door = g_home.doorOpen;
    const HomeMode mode = g_home.mode;
    const unsigned long doorMs = g_home.doorOpenSinceMs;
    const float temp = g_home.tempC;
    portEXIT_CRITICAL(&g_mux);

    if (!muted) {
      if (mode == HomeMode::Away && motion) {
        enqueueAlert("MOTION_AWAY");
      }
      if (door && doorMs > 0 && (millis() - doorMs) > 45000) {
        enqueueAlert("DOOR_OPEN");
      }
      if (mode == HomeMode::Away && motion && door) {
        enqueueAlert("INTRUSION");
      }
      if (temp > 30.0f) {
        char buf[32];
        snprintf(buf, sizeof(buf), "TEMP_HIGH,T=%.1f", temp);
        enqueueAlert(buf);
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
      g_home.mqttOk = false;
      connectMqtt();
    }
    mqtt.loop();
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi — Smart Home ===");

  pinMode(LIGHT_GPIO, OUTPUT);
  pinMode(HEAT_GPIO, OUTPUT);
  pinMode(MOTION_GPIO, INPUT);
  pinMode(DOOR_GPIO, INPUT);
  setLightLocked(false);
  setHeatLocked(false);

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
