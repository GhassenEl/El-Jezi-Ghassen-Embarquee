/**
 * El Jezi Ghassen Embarquée — RTOS + BLE
 * FreeRTOS : capteurs simulés + serveur BLE pour Flutter iot_remote.
 */
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const gpio_num_t LED_GPIO = GPIO_NUM_2;
static const gpio_num_t RELAY_GPIO = GPIO_NUM_4;
static const int PWM_GPIO = 5;
static const int PWM_CHANNEL = 0;
static const int PWM_FREQ = 5000;
static const int PWM_RES = 8;

/* UUIDs partagés avec Flutter (lib/ble/eljezi_ble_uuids.dart) */
static BLEUUID SERVICE_UUID("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
static BLEUUID CMD_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a8");
static BLEUUID STATUS_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a9");

static const char *DEVICE_NAME = "ElJezi-ESP32";

static BLECharacteristic *g_statusChar = nullptr;
static bool g_bleConnected = false;
static bool g_ledOn = false;
static bool g_relayOn = false;
static uint8_t g_pwm = 128;

static void applyOutputs() {
  digitalWrite(LED_GPIO, g_ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_pwm);
}

static void publishStatus(float temp, float hum, float volt) {
  char buf[48];
  snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", temp, hum, volt);
  Serial.println(buf);
  if (g_statusChar && g_bleConnected) {
    g_statusChar->setValue(buf);
    g_statusChar->notify();
  }
}

static void handleCommand(const std::string &raw) {
  if (raw.empty()) return;
  String cmd = String(raw.c_str());
  cmd.trim();
  cmd.toUpperCase();

  if (cmd == "LED_ON") {
    g_ledOn = true;
  } else if (cmd == "LED_OFF") {
    g_ledOn = false;
  } else if (cmd == "RELAY_ON") {
    g_relayOn = true;
  } else if (cmd == "RELAY_OFF") {
    g_relayOn = false;
  } else if (cmd.startsWith("PWM_")) {
    g_pwm = (uint8_t)cmd.substring(4).toInt();
  } else if (cmd == "STATUS") {
    float t = 20.0f + (float)(millis() / 1000 % 100) / 10.0f;
    publishStatus(t, 55.0f, 3.30f);
    return;
  } else {
    Serial.printf("[BLE] Commande inconnue: %s\n", cmd.c_str());
    return;
  }

  applyOutputs();
  Serial.printf("[BLE] OK %s\n", cmd.c_str());
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) {
    g_bleConnected = true;
    Serial.println("[BLE] Client connecte");
    server->getAdvertising()->stop();
  }

  void onDisconnect(BLEServer *server) {
    g_bleConnected = false;
    Serial.println("[BLE] Client deconnecte");
    server->getAdvertising()->start();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) {
    handleCommand(characteristic->getValue());
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

  g_statusChar = service->createCharacteristic(
      STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_statusChar->addDescriptor(new BLE2902());
  g_statusChar->setValue("T=0.0,H=0.0,V=0.0");

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising ElJezi-ESP32");
}

static void taskSensor(void *param) {
  (void)param;
  uint32_t tick = 0;
  for (;;) {
    const float temp = 20.0f + (float)(tick % 100) / 10.0f;
    const float hum = 50.0f + (float)(tick % 30);
    const float volt = 3.28f + (float)(tick % 5) * 0.01f;
    publishStatus(temp, hum, volt);
    tick++;
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi Ghassen Embarquee — RTOS + BLE ===");

  pinMode(LED_GPIO, OUTPUT);
  pinMode(RELAY_GPIO, OUTPUT);
  ledcSetup(PWM_CHANNEL, PWM_FREQ, PWM_RES);
  ledcAttachPin(PWM_GPIO, PWM_CHANNEL);
  applyOutputs();

  setupBle();
  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 1, nullptr, 1);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
