/**
 * El Jezi Ghassen Embarquée — RTOS + BLE + queues FreeRTOS
 *
 * cmdQueue       — BLE write  →  task_actuator (GPIO)
 * telemetryQueue — task_sensor  →  task_comms (BLE notify + série)
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

static BLEUUID SERVICE_UUID("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
static BLEUUID CMD_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a8");
static BLEUUID STATUS_UUID("beb5483e-36e1-4688-b7f5-ea07361b26a9");

static const char *DEVICE_NAME = "ElJezi-ESP32";

static const size_t CMD_QUEUE_LEN = 6;
static const size_t TELEMETRY_QUEUE_LEN = 4;

struct CommandMsg {
  char text[24];
};

struct TelemetryMsg {
  float temp;
  float hum;
  float volt;
};

static QueueHandle_t g_cmdQueue = nullptr;
static QueueHandle_t g_telemetryQueue = nullptr;

static BLECharacteristic *g_statusChar = nullptr;
static bool g_bleConnected = false;
static bool g_ledOn = false;
static bool g_relayOn = false;
static uint8_t g_pwm = 128;
static uint32_t g_tick = 0;

static void applyOutputs() {
  digitalWrite(LED_GPIO, g_ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_pwm);
}

static bool enqueueCommand(const char *cmd) {
  if (!g_cmdQueue || !cmd) return false;
  CommandMsg msg{};
  strncpy(msg.text, cmd, sizeof(msg.text) - 1);
  if (xQueueSend(g_cmdQueue, &msg, pdMS_TO_TICKS(50)) != pdPASS) {
    Serial.printf("[QUEUE] cmd pleine — drop (%s)\n", cmd);
    return false;
  }
  return true;
}

static bool enqueueTelemetry(const TelemetryMsg &sample) {
  if (!g_telemetryQueue) return false;
  return xQueueSend(g_telemetryQueue, &sample, pdMS_TO_TICKS(50)) == pdPASS;
}

static void processCommand(const CommandMsg &incoming) {
  String cmd = String(incoming.text);
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.isEmpty()) return;

  bool publish = false;

  if (cmd == "LED_ON") {
    g_ledOn = true;
    publish = true;
  } else if (cmd == "LED_OFF") {
    g_ledOn = false;
    publish = true;
  } else if (cmd == "RELAY_ON") {
    g_relayOn = true;
    publish = true;
  } else if (cmd == "RELAY_OFF") {
    g_relayOn = false;
    publish = true;
  } else if (cmd.startsWith("PWM_")) {
    g_pwm = (uint8_t)cmd.substring(4).toInt();
    publish = true;
  } else if (cmd == "STATUS") {
    publish = true;
  } else {
    Serial.printf("[BLE] Commande inconnue: %s\n", cmd.c_str());
    return;
  }

  if (publish && cmd != "STATUS") {
    applyOutputs();
    Serial.printf("[ACTUATOR] OK %s\n", cmd.c_str());
  }

  if (publish) {
    const float temp = 20.0f + (float)(g_tick % 100) / 10.0f;
    enqueueTelemetry({temp, 50.0f + (float)(g_tick % 30), 3.30f});
  }
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
    enqueueCommand(characteristic->getValue().c_str());
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
  for (;;) {
    const float temp = 20.0f + (float)(g_tick % 100) / 10.0f;
    const float hum = 50.0f + (float)(g_tick % 30);
    const float volt = 3.28f + (float)(g_tick % 5) * 0.01f;
    g_tick++;
    enqueueTelemetry({temp, hum, volt});
    vTaskDelay(pdMS_TO_TICKS(2000));
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

static void taskComms(void *param) {
  (void)param;
  TelemetryMsg sample;
  for (;;) {
    if (xQueueReceive(g_telemetryQueue, &sample, portMAX_DELAY) == pdPASS) {
      char buf[48];
      snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", sample.temp, sample.hum, sample.volt);
      Serial.printf("[COMMS] %s\n", buf);
      if (g_statusChar && g_bleConnected) {
        g_statusChar->setValue(buf);
        g_statusChar->notify();
      }
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== El Jezi Ghassen — RTOS + BLE + Queues ===");

  g_cmdQueue = xQueueCreate(CMD_QUEUE_LEN, sizeof(CommandMsg));
  g_telemetryQueue = xQueueCreate(TELEMETRY_QUEUE_LEN, sizeof(TelemetryMsg));
  if (!g_cmdQueue || !g_telemetryQueue) {
    Serial.println("[FATAL] Queues non creees");
    for (;;) delay(1000);
  }

  pinMode(LED_GPIO, OUTPUT);
  pinMode(RELAY_GPIO, OUTPUT);
  ledcSetup(PWM_CHANNEL, PWM_FREQ, PWM_RES);
  ledcAttachPin(PWM_GPIO, PWM_CHANNEL);
  applyOutputs();

  setupBle();

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 2, nullptr, 0);
  xTaskCreatePinnedToCore(taskActuator, "task_actuator", 4096, nullptr, 3, nullptr, 0);
  xTaskCreatePinnedToCore(taskComms, "task_comms", 4096, nullptr, 2, nullptr, 1);

  Serial.printf("[QUEUE] cmd=%u telemetry=%u\n",
                (unsigned)CMD_QUEUE_LEN, (unsigned)TELEMETRY_QUEUE_LEN);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
