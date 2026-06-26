/**
 * El Jezi Ghassen — Smart Poubelle ESP32
 * Capteurs simules : remplissage ultrason, poids, gaz, couvercle, batterie.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

#ifndef BIN_ID
#define BIN_ID "parc-lac"
#endif
#ifndef BIN_TYPE
#define BIN_TYPE "RECYCLE"
#endif

static const int LID_GPIO = 35;
static const char *TOPIC_TELEMETRY = "eljezi/poubelle/telemetry";
static const char *TOPIC_COMMAND = "eljezi/poubelle/command";
static const char *TOPIC_STATUS = "eljezi/poubelle/status";
static const char *TOPIC_ALERT = "eljezi/poubelle/alert";
static const char *MQTT_CLIENT_ID = "ElJezi-SmartPoubelle";

struct BinState {
  int fillPct = 45;
  float weightKg = 28.0f;
  bool lidOpen = false;
  int gasPpm = 60;
  int batteryPct = 95;
  float tempC = 25.0f;
  float humidity = 50.0f;
  bool collectionDue = false;
  bool alarmOn = true;
  uint32_t tick = 0;
};

static BinState g_bin;
static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);

static void publishStatus() {
  char buf[96];
  snprintf(buf, sizeof(buf),
           "BIN=%s,ONLINE=1,MODE=NORMAL,COLLECT=%d,ALARM=%d",
           BIN_ID, g_bin.collectionDue ? 1 : 0, g_bin.alarmOn ? 1 : 0);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void publishTelemetry() {
  char buf[160];
  snprintf(buf, sizeof(buf),
           "BIN=%s,TYPE=%s,FILL=%d,WEIGHT=%.1f,LID=%d,GAS=%d,BATT=%d,T=%.1f,H=%.0f",
           BIN_ID, BIN_TYPE, g_bin.fillPct, g_bin.weightKg,
           g_bin.lidOpen ? 1 : 0, g_bin.gasPpm, g_bin.batteryPct,
           g_bin.tempC, g_bin.humidity);
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishAlert(const char *alert) {
  char buf[64];
  snprintf(buf, sizeof(buf), "BIN=%s,ALERT=%s", BIN_ID, alert);
  mqtt.publish(TOPIC_ALERT, buf);
}

static void handleCommand(const String &cmdRaw) {
  String cmd = cmdRaw;
  cmd.trim();
  cmd.toUpperCase();

  if (cmd == "STATUS") {
    publishStatus();
    publishTelemetry();
    return;
  }
  if (cmd == "EMPTY_CONFIRM") {
    g_bin.fillPct = 5;
    g_bin.weightKg = 2.0f;
    g_bin.gasPpm = 40;
    g_bin.collectionDue = false;
    publishStatus();
    publishTelemetry();
    return;
  }
  if (cmd == "LID_LOCK") {
    g_bin.lidOpen = false;
    publishTelemetry();
    return;
  }
  if (cmd == "MODE_ALERT") {
    g_bin.alarmOn = true;
    publishStatus();
    return;
  }
  Serial.printf("[CMD] Inconnue: %s\n", cmd.c_str());
}

static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  handleCommand(msg);
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
      publishStatus();
    } else {
      delay(3000);
    }
  }
}

static void updateSensors() {
  g_bin.tick++;
  const float phase = sinf((float)g_bin.tick * 0.12f);

  if ((g_bin.tick % 40) == 0) {
    g_bin.lidOpen = !g_bin.lidOpen;
  } else {
    g_bin.lidOpen = digitalRead(LID_GPIO) == HIGH || (g_bin.tick % 80) < 3;
  }

  g_bin.fillPct = (int)min(100.0f, max(0.0f, g_bin.fillPct + (phase > 0.3f ? 1 : 0)));
  g_bin.weightKg = g_bin.fillPct * 0.65f + random(-2, 3) * 0.1f;
  g_bin.gasPpm = 50 + g_bin.fillPct / 2 + (g_bin.lidOpen ? 40 : 0) + (int)(20 * (phase + 1));
  g_bin.batteryPct = max(15, 100 - (int)(g_bin.tick / 120));
  g_bin.tempC = 24.0f + 4.0f * phase;
  g_bin.humidity = 48.0f + 10.0f * cosf((float)g_bin.tick * 0.07f);
  g_bin.collectionDue = g_bin.fillPct >= 85;

  if (g_bin.alarmOn) {
    if (g_bin.fillPct >= 95 && g_bin.tick % 25 == 0) publishAlert("FILL_FULL");
    else if (g_bin.fillPct >= 85 && g_bin.tick % 30 == 0) publishAlert("FILL_HIGH");
    if (g_bin.lidOpen && g_bin.tick % 35 == 0) publishAlert("LID_OPEN");
    if (g_bin.gasPpm > 250 && g_bin.tick % 40 == 0) publishAlert("ODOR_HIGH");
    if (g_bin.batteryPct < 25 && g_bin.tick % 50 == 0) publishAlert("LOW_BATTERY");
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi — Smart Poubelle ===");
  pinMode(LID_GPIO, INPUT);
  randomSeed(esp_random());
  connectWiFi();
  connectMqtt();
}

void loop() {
  if (!mqtt.connected()) connectMqtt();
  mqtt.loop();
  updateSensors();
  publishTelemetry();
  if (g_bin.tick % 10 == 0) publishStatus();
  delay(4000);
}
