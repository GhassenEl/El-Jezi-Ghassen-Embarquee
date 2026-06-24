/**
 * El Jezi Ghassen — IoT MQTT
 * Publie T/H/V sur eljezi/esp32/telemetry, écoute eljezi/esp32/command.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "secrets.h"

static const char *TOPIC_TELEMETRY = "eljezi/esp32/telemetry";
static const char *TOPIC_COMMAND = "eljezi/esp32/command";
static const char *TOPIC_STATUS = "eljezi/esp32/status";
static const char *CLIENT_ID = "ElJezi-ESP32-MQTT";

static const gpio_num_t LED_GPIO = GPIO_NUM_2;
static const gpio_num_t RELAY_GPIO = GPIO_NUM_4;
static const int PWM_GPIO = 5;
static const int PWM_CHANNEL = 0;

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);

static bool g_ledOn = false;
static bool g_relayOn = false;
static uint8_t g_pwm = 128;
static uint32_t g_tick = 0;

static void applyOutputs() {
  digitalWrite(LED_GPIO, g_ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_pwm);
}

static void publishStatus() {
  char buf[48];
  snprintf(buf, sizeof(buf), "LED=%d,RELAY=%d,PWM=%u", g_ledOn ? 1 : 0, g_relayOn ? 1 : 0, g_pwm);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void handleCommand(const String &cmdRaw) {
  String cmd = cmdRaw;
  cmd.trim();
  cmd.toUpperCase();

  if (cmd == "LED_ON") g_ledOn = true;
  else if (cmd == "LED_OFF") g_ledOn = false;
  else if (cmd == "RELAY_ON") g_relayOn = true;
  else if (cmd == "RELAY_OFF") g_relayOn = false;
  else if (cmd.startsWith("PWM_")) g_pwm = (uint8_t)cmd.substring(4).toInt();
  else if (cmd == "STATUS") {
    publishStatus();
    return;
  } else {
    Serial.printf("[MQTT] Commande inconnue: %s\n", cmd.c_str());
    return;
  }

  applyOutputs();
  publishStatus();
  Serial.printf("[MQTT] OK %s\n", cmd.c_str());
}

static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  Serial.printf("[MQTT] RX %s -> %s\n", topic, msg.c_str());
  handleCommand(msg);
}

static void connectWiFi() {
  Serial.printf("[WiFi] Connexion %s ...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.printf("\n[WiFi] OK %s\n", WiFi.localIP().toString().c_str());
}

static void connectMqtt() {
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(256);

  while (!mqtt.connected()) {
    Serial.printf("[MQTT] Connexion %s:%d ...\n", MQTT_BROKER, MQTT_PORT);
    if (mqtt.connect(CLIENT_ID)) {
      mqtt.subscribe(TOPIC_COMMAND);
      Serial.println("[MQTT] Connecte + subscribe command");
      publishStatus();
    } else {
      Serial.printf("[MQTT] Echec rc=%d\n", mqtt.state());
      delay(3000);
    }
  }
}

static void publishTelemetry() {
  const float temp = 20.0f + (float)(g_tick % 100) / 10.0f;
  const float hum = 50.0f + (float)(g_tick % 30);
  const float volt = 3.28f + (float)(g_tick % 5) * 0.01f;
  char buf[48];
  snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", temp, hum, volt);
  mqtt.publish(TOPIC_TELEMETRY, buf);
  Serial.println(buf);
  g_tick++;
}

static void taskMqtt(void *param) {
  (void)param;
  unsigned long lastPub = 0;
  for (;;) {
    if (!mqtt.connected()) connectMqtt();
    mqtt.loop();

    const unsigned long now = millis();
    if (now - lastPub >= 2000) {
      publishTelemetry();
      lastPub = now;
    }
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi Ghassen — IoT MQTT ===");

  pinMode(LED_GPIO, OUTPUT);
  pinMode(RELAY_GPIO, OUTPUT);
  ledcSetup(PWM_CHANNEL, 5000, 8);
  ledcAttachPin(PWM_GPIO, PWM_CHANNEL);
  applyOutputs();

  connectWiFi();
  xTaskCreatePinnedToCore(taskMqtt, "task_mqtt", 8192, nullptr, 1, nullptr, 1);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
