/**
 * El Jezi Ghassen — Affichage OLED SSD1306 (I2C)
 * Capteurs simulés + sorties GPIO (même protocole que BLE/MQTT).
 *
 * Câblage I2C (ESP32 devkit) :
 *   OLED SDA → GPIO 21
 *   OLED SCL → GPIO 22
 *   OLED VCC → 3.3V, GND → GND
 */
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

static const int OLED_W = 128;
static const int OLED_H = 64;
static const int OLED_SDA = 21;
static const int OLED_SCL = 22;
static const uint8_t OLED_ADDR = 0x3C;

static const gpio_num_t LED_GPIO = GPIO_NUM_2;
static const gpio_num_t RELAY_GPIO = GPIO_NUM_4;
static const int PWM_GPIO = 5;
static const int PWM_CHANNEL = 0;

static Adafruit_SSD1306 display(OLED_W, OLED_H, &Wire, -1);

static bool g_ledOn = false;
static bool g_relayOn = false;
static uint8_t g_pwm = 128;
static uint32_t g_tick = 0;
static float g_temp = 24.0f;
static float g_hum = 55.0f;
static float g_volt = 3.30f;

static void applyOutputs() {
  digitalWrite(LED_GPIO, g_ledOn ? HIGH : LOW);
  digitalWrite(RELAY_GPIO, g_relayOn ? HIGH : LOW);
  ledcWrite(PWM_CHANNEL, g_pwm);
}

static void readSensors() {
  g_temp = 20.0f + (float)(g_tick % 100) / 10.0f;
  g_hum = 50.0f + (float)(g_tick % 30);
  g_volt = 3.28f + (float)(g_tick % 5) * 0.01f;
  g_tick++;
}

static void drawDashboard() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println(F("El Jezi Ghassen"));
  display.drawLine(0, 10, 127, 10, SSD1306_WHITE);

  display.setTextSize(2);
  display.setCursor(0, 14);
  display.print(g_temp, 1);
  display.println(F(" C"));

  display.setTextSize(1);
  display.setCursor(0, 36);
  display.printf("H: %.0f%%  V: %.2fV", g_hum, g_volt);

  display.setCursor(0, 48);
  display.printf("LED:%s REL:%s PWM:%u",
                 g_ledOn ? "ON" : "OFF",
                 g_relayOn ? "ON" : "OFF",
                 g_pwm);

  display.setCursor(0, 58);
  display.print(F("I2C SSD1306"));
  display.display();
}

static void taskSensor(void *param) {
  (void)param;
  for (;;) {
    readSensors();
    char buf[48];
    snprintf(buf, sizeof(buf), "T=%.1f,H=%.1f,V=%.2f", g_temp, g_hum, g_volt);
    Serial.println(buf);
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

static void taskDisplay(void *param) {
  (void)param;
  for (;;) {
    drawDashboard();
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

static void taskSerialCmd(void *param) {
  (void)param;
  String line;
  for (;;) {
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '\n' || c == '\r') {
        if (line.length() == 0) continue;
        line.trim();
        line.toUpperCase();

        if (line == "LED_ON") g_ledOn = true;
        else if (line == "LED_OFF") g_ledOn = false;
        else if (line == "RELAY_ON") g_relayOn = true;
        else if (line == "RELAY_OFF") g_relayOn = false;
        else if (line.startsWith("PWM_")) g_pwm = (uint8_t)line.substring(4).toInt();
        else if (line == "STATUS") {
          Serial.printf("LED=%d,RELAY=%d,PWM=%u\n", g_ledOn ? 1 : 0, g_relayOn ? 1 : 0, g_pwm);
        } else {
          Serial.printf("[CMD] Inconnue: %s\n", line.c_str());
          line = "";
          continue;
        }

        applyOutputs();
        Serial.printf("[CMD] OK %s\n", line.c_str());
        line = "";
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
  Serial.println("\n=== El Jezi Ghassen — OLED SSD1306 ===");

  pinMode(LED_GPIO, OUTPUT);
  pinMode(RELAY_GPIO, OUTPUT);
  ledcSetup(PWM_CHANNEL, 5000, 8);
  ledcAttachPin(PWM_GPIO, PWM_CHANNEL);
  applyOutputs();

  Wire.begin(OLED_SDA, OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
    Serial.println(F("[OLED] Echec init — verifiez SDA/SCL"));
    for (;;) delay(1000);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 20);
  display.println(F("Demarrage..."));
  display.display();

  xTaskCreatePinnedToCore(taskSensor, "task_sensor", 4096, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(taskDisplay, "task_display", 4096, nullptr, 1, nullptr, 1);
  xTaskCreatePinnedToCore(taskSerialCmd, "task_serial", 4096, nullptr, 1, nullptr, 1);

  Serial.println("[OK] Commandes serie : LED_ON, LED_OFF, RELAY_ON, RELAY_OFF, PWM_0..255, STATUS");
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
