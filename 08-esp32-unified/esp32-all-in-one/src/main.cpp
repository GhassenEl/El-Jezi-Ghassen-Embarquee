/**
 * El Jezi Ghassen — ESP32 unifié : BLE + MQTT + OLED SSD1306
 * Un seul firmware : Flutter BLE, Flutter MQTT, dashboard web, écran local.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <Wire.h>
#include <PubSubClient.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "secrets.h"

/* GPIO */
static const gpio_num_t LED_GPIO = GPIO_NUM_2;
static const gpio_num_t RELAY_GPIO = GPIO_NUM_4;
static const int PWM_GPIO = 5;
static const int PWM_CHANNEL = 0;

/* OLED I2C */
static const int OLED_W = 128;
static const int OLED_H = 64;
static const int OLED_SDA = 21;
static const int OLED_SCL = 22;
static const uint8_t OLED_ADDR = 0x3C;

/* BLE — UUIDs partagés Flutter */
static BLEUUID SERVICE_UUID("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
static BLEUUID CMD_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a8");
static BLEUUID STATUS_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a9");
static const char *DEVICE_NAME = "ElJezi-ESP32";

/* MQTT */
static const char *TOPIC_TELEMETRY = "eljezi/esp32/telemetry";
static const char *TOPIC_COMMAND = "eljezi/esp32/command";
static const char *TOPIC_STATUS = "eljezi/esp32/status";
static const char *MQTT_CLIENT_ID = "ElJezi-ESP32-Unified";

static Adafruit_SSD1306 display(OLED_W, OLED_H, &Wire, -1);
static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);
static BLECharacteristic *g_bleStatusChar = nullptr;

static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

struct DeviceState {
  bool ledOn = false;
  bool relayOn = false;
  uint8_t pwm = 128;
  float temp = 24.0f;
  float hum = 55.0f;
  float volt = 3.30f;
  uint32_t tick = 0;
  bool bleConnected = false;
  bool mqttConnected = false;
  bool wifiConnected = false;
  bool oledOk = false;
};

static DeviceState g_state;

static void applyOutputsLocked() {
  digitalWrite(LED_GPIO, g_state.ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_state.relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_state.pwm);
}

static void formatTelemetry(char *buf, size_t len) {
  snprintf(buf, len, "T=%.1f,H=%.1f,V=%.2f", g_state.temp, g_state.hum, g_state.volt);
}

static void formatMqttStatus(char *buf, size_t len) {
  snprintf(buf, len, "LED=%d,RELAY=%d,PWM=%u",
           g_state.ledOn ? 1 : 0, g_state.relayOn ? 1 : 0, g_state.pwm);
}

static void publishBleTelemetry() {
  if (!g_bleStatusChar || !g_state.bleConnected) return;
  char buf[48];
  formatTelemetry(buf, sizeof(buf));
  g_bleStatusChar->setValue(buf);
  g_bleStatusChar->notify();
}

static void publishMqttTelemetry() {
  if (!g_state.mqttConnected) return;
  char buf[48];
  formatTelemetry(buf, sizeof(buf));
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttStatus() {
  if (!g_state.mqttConnected) return;
  char buf[48];
  formatMqttStatus(buf, sizeof(buf));
  mqtt.publish(TOPIC_STATUS, buf);
}

static void broadcastTelemetry(const char *source) {
  char buf[48];
  formatTelemetry(buf, sizeof(buf));
  Serial.printf("[%s] %s\n", source, buf);
  publishBleTelemetry();
  publishMqttTelemetry();
}

static bool handleCommand(const String &cmdRaw, const char *source) {
  String cmd = cmdRaw;
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.isEmpty()) return false;

  bool changed = false;
  bool statusOnly = false;

  portENTER_CRITICAL(&g_mux);
  if (cmd == "LED_ON") {
    g_state.ledOn = true;
    changed = true;
  } else if (cmd == "LED_OFF") {
    g_state.ledOn = false;
    changed = true;
  } else if (cmd == "RELAY_ON") {
    g_state.relayOn = true;
    changed = true;
  } else if (cmd == "RELAY_OFF") {
    g_state.relayOn = false;
    changed = true;
  } else if (cmd.startsWith("PWM_")) {
    g_state.pwm = (uint8_t)cmd.substring(4).toInt();
    changed = true;
  } else if (cmd == "STATUS") {
    statusOnly = true;
  } else {
    portEXIT_CRITICAL(&g_mux);
    Serial.printf("[%s] Commande inconnue: %s\n", source, cmd.c_str());
    return false;
  }

  if (changed) applyOutputsLocked();
  portEXIT_CRITICAL(&g_mux);

  if (changed) {
    publishMqttStatus();
    Serial.printf("[%s] OK %s\n", source, cmd.c_str());
  }
  if (statusOnly) {
    broadcastTelemetry(source);
    publishMqttStatus();
  } else if (changed) {
    broadcastTelemetry(source);
  }
  return true;
}

/* --- BLE --- */
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) {
    portENTER_CRITICAL(&g_mux);
    g_state.bleConnected = true;
    portEXIT_CRITICAL(&g_mux);
    Serial.println("[BLE] Client connecte");
    server->getAdvertising()->stop();
  }

  void onDisconnect(BLEServer *server) {
    portENTER_CRITICAL(&g_mux);
    g_state.bleConnected = false;
    portEXIT_CRITICAL(&g_mux);
    Serial.println("[BLE] Client deconnecte");
    server->getAdvertising()->start();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) {
    handleCommand(String(characteristic->getValue().c_str()), "BLE");
  }
};

static void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *cmdChar = service->createCharacteristic(
      CMD_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  cmdChar->setCallbacks(new CommandCallbacks());

  g_bleStatusChar = service->createCharacteristic(
      STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_bleStatusChar->addDescriptor(new BLE2902());
  g_bleStatusChar->setValue("T=0.0,H=0.0,V=0.0");

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("[BLE] Advertising ElJezi-ESP32");
}

/* --- MQTT --- */
static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  Serial.printf("[MQTT] RX %s -> %s\n", topic, msg.c_str());
  handleCommand(msg, "MQTT");
}

static void connectWiFi() {
  Serial.printf("[WiFi] Connexion %s ...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  uint8_t retries = 0;
  while (WiFi.status() != WL_CONNECTED && retries < 60) {
    delay(500);
    Serial.print('.');
    retries++;
  }
  const bool ok = WiFi.status() == WL_CONNECTED;
  portENTER_CRITICAL(&g_mux);
  g_state.wifiConnected = ok;
  portEXIT_CRITICAL(&g_mux);
  if (ok) {
    Serial.printf("\n[WiFi] OK %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\n[WiFi] Echec — MQTT desactive, BLE+OLED actifs");
  }
}

static void connectMqtt() {
  if (!g_state.wifiConnected) return;

  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(256);

  if (mqtt.connected()) return;

  Serial.printf("[MQTT] Connexion %s:%d ...\n", MQTT_BROKER, MQTT_PORT);
  if (mqtt.connect(MQTT_CLIENT_ID)) {
    mqtt.subscribe(TOPIC_COMMAND);
    portENTER_CRITICAL(&g_mux);
    g_state.mqttConnected = true;
    portEXIT_CRITICAL(&g_mux);
    Serial.println("[MQTT] Connecte");
    publishMqttStatus();
  } else {
    portENTER_CRITICAL(&g_mux);
    g_state.mqttConnected = false;
    portEXIT_CRITICAL(&g_mux);
    Serial.printf("[MQTT] Echec rc=%d\n", mqtt.state());
  }
}

/* --- OLED --- */
static void drawDashboard() {
  if (!g_state.oledOk) return;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println(F("El Jezi Unified"));

  display.setCursor(0, 10);
  display.printf("B:%s M:%s W:%s",
                   g_state.bleConnected ? "ON" : "--",
                   g_state.mqttConnected ? "ON" : "--",
                   g_state.wifiConnected ? "ON" : "--");

  display.drawLine(0, 18, 127, 18, SSD1306_WHITE);

  display.setTextSize(2);
  display.setCursor(0, 22);
  display.print(g_state.temp, 1);
  display.println(F(" C"));

  display.setTextSize(1);
  display.setCursor(0, 44);
  display.printf("H:%.0f%% V:%.2fV", g_state.hum, g_state.volt);

  display.setCursor(0, 54);
  display.printf("L:%s R:%s P:%u",
                 g_state.ledOn ? "1" : "0",
                 g_state.relayOn ? "1" : "0",
                 g_state.pwm);
  display.display();
}

static void setupOled() {
  Wire.begin(OLED_SDA, OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
    Serial.println("[OLED] Echec init — continue sans ecran");
    portENTER_CRITICAL(&g_mux);
    g_state.oledOk = false;
    portEXIT_CRITICAL(&g_mux);
    return;
  }
  portENTER_CRITICAL(&g_mux);
  g_state.oledOk = true;
  portEXIT_CRITICAL(&g_mux);
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 24);
  display.println(F("Demarrage..."));
  display.display();
  Serial.println("[OLED] OK SSD1306");
}

/* --- FreeRTOS tasks --- */
static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    portENTER_CRITICAL(&g_mux);
    g_state.temp = 20.0f + (float)(g_state.tick % 100) / 10.0f;
    g_state.hum = 50.0f + (float)(g_state.tick % 30);
    g_state.volt = 3.28f + (float)(g_state.tick % 5) * 0.01f;
    g_state.tick++;
    portEXIT_CRITICAL(&g_mux);

    broadcastTelemetry("SENSOR");
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

static void taskMqtt(void *param) {
  (void)param;
  for (;;) {
    if (g_state.wifiConnected) {
      if (!mqtt.connected()) connectMqtt();
      if (mqtt.connected()) mqtt.loop();
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

static void taskDisplay(void *param) {
  (void)param;
  for (;;) {
    drawDashboard();
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

static void taskSerial(void *param) {
  (void)param;
  String line;
  for (;;) {
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '\n' || c == '\r') {
        if (line.length() > 0) {
          handleCommand(line, "SERIAL");
          line = "";
        }
      } else {
        line += c;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi Ghassen — ESP32 Unified BLE+MQTT+OLED ===");

  pinMode(LED_GPIO, OUTPUT);
  pinMode(RELAY_GPIO, OUTPUT);
  ledcSetup(PWM_CHANNEL, 5000, 8);
  ledcAttachPin(PWM_GPIO, PWM_CHANNEL);
  portENTER_CRITICAL(&g_mux);
  applyOutputsLocked();
  portEXIT_CRITICAL(&g_mux);

  setupOled();
  setupBle();
  connectWiFi();
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(taskMqtt, "task_mqtt", 8192, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(taskDisplay, "task_display", 4096, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(taskSerial, "task_serial", 4096, nullptr, 1, nullptr, 0);

  Serial.println("[OK] Protocole: LED_ON/OFF RELAY_ON/OFF PWM_0..255 STATUS");
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(2000));
}
