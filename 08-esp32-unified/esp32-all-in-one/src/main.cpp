/**
 * El Jezi Ghassen — ESP32 unifié : BLE + MQTT + OLED + queues FreeRTOS
 *
 * Files :
 *   cmdQueue       — BLE / MQTT / Série  →  task_actuator (GPIO)
 *   telemetryQueue — task_sensor / actuator  →  task_comms (BLE + MQTT + log)
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

/* BLE */
static BLEUUID SERVICE_UUID("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
static BLEUUID CMD_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a8");
static BLEUUID STATUS_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a9");
static const char *DEVICE_NAME = "ElJezi-ESP32";

/* MQTT */
static const char *TOPIC_TELEMETRY = "eljezi/esp32/telemetry";
static const char *TOPIC_COMMAND = "eljezi/esp32/command";
static const char *TOPIC_STATUS = "eljezi/esp32/status";
static const char *MQTT_CLIENT_ID = "ElJezi-ESP32-Unified";

/* Queues FreeRTOS */
static const size_t CMD_QUEUE_LEN = 8;
static const size_t TELEMETRY_QUEUE_LEN = 6;

enum class CommandSource : uint8_t { Ble = 0, Mqtt, Serial };

struct CommandMsg {
  char text[24];
  CommandSource source;
};

struct TelemetryMsg {
  float temp;
  float hum;
  float volt;
};

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;

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

static const char *sourceName(CommandSource src) {
  switch (src) {
    case CommandSource::Ble: return "BLE";
    case CommandSource::Mqtt: return "MQTT";
    case CommandSource::Serial: return "SERIAL";
  }
  return "?";
}

static void applyOutputsLocked() {
  digitalWrite(LED_GPIO, g_state.ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_state.relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_state.pwm);
}

static bool enqueueCommand(const char *cmd, CommandSource src) {
  if (!g_cmdQueue || !cmd) return false;
  CommandMsg msg{};
  strncpy(msg.text, cmd, sizeof(msg.text) - 1);
  msg.source = src;
  if (xQueueSend(g_cmdQueue, &msg, pdMS_TO_TICKS(50)) != pdPASS) {
    Serial.printf("[QUEUE] cmd pleine — drop (%s)\n", cmd);
    return false;
  }
  return true;
}

static bool enqueueTelemetry(const TelemetryMsg &sample) {
  if (!g_telemetryQueue) return false;
  if (xQueueSend(g_telemetryQueue, &sample, pdMS_TO_TICKS(50)) != pdPASS) {
    Serial.println("[QUEUE] telemetry pleine — drop");
    return false;
  }
  return true;
}

static TelemetryMsg readTelemetrySnapshot() {
  portENTER_CRITICAL(&g_mux);
  TelemetryMsg m{g_state.temp, g_state.hum, g_state.volt};
  portEXIT_CRITICAL(&g_mux);
  return m;
}

static void publishBle(const TelemetryMsg &m) {
  if (!g_bleStatusChar || !g_state.bleConnected) return;
  char buf[48];
  snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", m.temp, m.hum, m.volt);
  g_bleStatusChar->setValue(buf);
  g_bleStatusChar->notify();
}

static void publishMqttTelemetry(const TelemetryMsg &m) {
  if (!g_state.mqttConnected) return;
  char buf[48];
  snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", m.temp, m.hum, m.volt);
  mqtt.publish(TOPIC_TELEMETRY, buf);
}

static void publishMqttStatus() {
  if (!g_state.mqttConnected) return;
  char buf[48];
  portENTER_CRITICAL(&g_mux);
  snprintf(buf, sizeof(buf), "LED=%d,RELAY=%d,PWM=%u",
           g_state.ledOn ? 1 : 0, g_state.relayOn ? 1 : 0, g_state.pwm);
  portEXIT_CRITICAL(&g_mux);
  mqtt.publish(TOPIC_STATUS, buf);
}

static void processCommand(const CommandMsg &incoming) {
  String cmd = String(incoming.text);
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.isEmpty()) return;

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
    Serial.printf("[%s] Commande inconnue: %s\n", sourceName(incoming.source), cmd.c_str());
    return;
  }

  if (changed) applyOutputsLocked();
  portEXIT_CRITICAL(&g_mux);

  if (changed) {
    publishMqttStatus();
    Serial.printf("[%s] OK %s\n", sourceName(incoming.source), cmd.c_str());
  }

  if (statusOnly || changed) {
    enqueueTelemetry(readTelemetrySnapshot());
  }
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
    enqueueCommand(characteristic->getValue().c_str(), CommandSource::Ble);
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
  char buf[32];
  size_t n = length < sizeof(buf) - 1 ? length : sizeof(buf) - 1;
  memcpy(buf, payload, n);
  buf[n] = '\0';
  Serial.printf("[MQTT] RX %s -> %s\n", topic, buf);
  enqueueCommand(buf, CommandSource::Mqtt);
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

  const UBaseType_t cmdQ = g_cmdQueue ? uxQueueMessagesWaiting(g_cmdQueue) : 0;
  const UBaseType_t telQ = g_telemetryQueue ? uxQueueMessagesWaiting(g_telemetryQueue) : 0;

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

  display.setCursor(90, 0);
  display.printf("Q%c/%u T%u",
                 cmdQ > 0 ? '!' : ' ',
                 (unsigned)cmdQ,
                 (unsigned)telQ);
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

/** Producteur : lit les capteurs simulés et pousse dans telemetryQueue. */
static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    TelemetryMsg sample;
    portENTER_CRITICAL(&g_mux);
    g_state.temp = 20.0f + (float)(g_state.tick % 100) / 10.0f;
    g_state.hum = 50.0f + (float)(g_state.tick % 30);
    g_state.volt = 3.28f + (float)(g_state.tick % 5) * 0.01f;
    g_state.tick++;
    sample = {g_state.temp, g_state.hum, g_state.volt};
    portEXIT_CRITICAL(&g_mux);

    enqueueTelemetry(sample);
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

/** Consommateur cmdQueue : applique GPIO et relance une télémétrie si besoin. */
static void taskActuator(void *param) {
  (void)param;
  CommandMsg msg;
  for (;;) {
    if (xQueueReceive(g_cmdQueue, &msg, portMAX_DELAY) == pdPASS) {
      processCommand(msg);
    }
  }
}

/** Consommateur telemetryQueue : BLE notify + MQTT publish + log série. */
static void taskComms(void *param) {
  (void)param;
  TelemetryMsg sample;
  for (;;) {
    if (xQueueReceive(g_telemetryQueue, &sample, portMAX_DELAY) == pdPASS) {
      portENTER_CRITICAL(&g_mux);
      g_state.temp = sample.temp;
      g_state.hum = sample.hum;
      g_state.volt = sample.volt;
      portEXIT_CRITICAL(&g_mux);

      Serial.printf("[COMMS] T=%.1f,H=%.1f,V=%.2f\n", sample.temp, sample.hum, sample.volt);
      publishBle(sample);
      publishMqttTelemetry(sample);
    }
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

/** Producteur cmdQueue : commandes saisies sur USB. */
static void taskSerial(void *param) {
  (void)param;
  String line;
  for (;;) {
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '\n' || c == '\r') {
        if (line.length() > 0) {
          enqueueCommand(line.c_str(), CommandSource::Serial);
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
  Serial.println("\n=== El Jezi Ghassen — Unified + FreeRTOS Queues ===");

  g_cmdQueue = xQueueCreate(CMD_QUEUE_LEN, sizeof(CommandMsg));
  g_telemetryQueue = xQueueCreate(TELEMETRY_QUEUE_LEN, sizeof(TelemetryMsg));
  if (!g_cmdQueue || !g_telemetryQueue) {
    Serial.println("[FATAL] Impossible de creer les queues");
    for (;;) delay(1000);
  }

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

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 2, nullptr, 0);
  xTaskCreatePinnedToCore(taskActuator, "task_actuator", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(taskComms, "task_comms", 6144, nullptr, 2, nullptr, 1);
  xTaskCreatePinnedToCore(taskMqtt, "task_mqtt", 8192, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(taskDisplay, "task_display", 4096, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(taskSerial, "task_serial", 4096, nullptr, 1, nullptr, 0);

  Serial.printf("[QUEUE] cmd=%u slots, telemetry=%u slots\n",
                (unsigned)CMD_QUEUE_LEN, (unsigned)TELEMETRY_QUEUE_LEN);
  Serial.println("[OK] LED_ON/OFF RELAY_ON/OFF PWM_0..255 STATUS");
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(2000));
}
