// =============================================================================
//  TinkrNest Smart Switch — ULTIMATE INDUSTRIAL v7.0.3  (ESP32 DevKit)
// -----------------------------------------------------------------------------
//  PATCH v7.0.3 — BLE provisioning + always-on local control
//
//  Fix A: JSON provisioning moved out of NimBLE callback into bleTask.
//         Blocking WiFi.begin() in onWrite() starved NimBLE → disconnect.
//
//  Fix B: BLE always starts at boot (WiFi/Blynk creds or not) so the app can
//         provision AND control relays anytime after factory reset.
//
//  Fix C: STATUS JSON adds "setup":true when no credentials saved.
//
//  Fix D: scanWorkerTask registers with WDT; bleTask stack 8192 for provision.
//
//  BUTTON (GPIO 0 / BOOT):
//    Short press (≥30 ms)  → reboot
//    3 s hold              → restart BLE advertising
//    10 s hold             → factory reset → reboot → BLE setup mode
//
//  PIN MAPPING (ESP32 DevKit v1 / v4):
//    Relay 1 → GPIO 25    LED Status → GPIO 2 (onboard)
//    Relay 2 → GPIO 26    Button     → GPIO 0 (BOOT button)
//    Relay 3 → GPIO 27    IR Recv    → GPIO 32
//    Relay 4 → GPIO 14    DHT22      → GPIO 4
// =============================================================================

#define BLYNK_TEMPLATE_ID "TMPL000000000"
#define BLYNK_TEMPLATE_NAME "Placeholder"
#define BLYNK_FIRMWARE_VERSION "7.0.4-industrial"
#define BLYNK_PRINT Serial

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <ArduinoOTA.h>
#include <ArduinoJson.h>
#include <BlynkSimpleEsp32.h>
#include <NimBLEDevice.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRutils.h>
#include <DHT.h>

#include <esp_task_wdt.h>
#include <esp_system.h>
#include <esp_heap_caps.h>
#include <esp_wifi.h>
#include <soc/rtc_cntl_reg.h>
#include <soc/soc.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

namespace cfg
{
  constexpr uint8_t PIN_RELAY[4] = {25, 26, 27, 14};
  constexpr uint8_t PIN_LED = 2;
  constexpr uint8_t PIN_BTN = 33;
  constexpr uint8_t PIN_IR = 32;
  constexpr uint8_t PIN_DHT = 4;
  constexpr uint8_t DHT_TYPE = DHT22;
  constexpr uint8_t RELAY_COUNT = 4;
  constexpr bool RELAY_ACTIVE_HIGH = true;

  constexpr uint32_t WDT_TIMEOUT_S = 15;
  constexpr uint32_t NVS_DEBOUNCE_MS = 5000;
  constexpr uint32_t DHT_PERIOD_MS = 3000;
  constexpr uint32_t INET_PROBE_MS = 15000;
  constexpr uint32_t WIFI_RETRY_MS = 5000;
  constexpr uint32_t BLYNK_RETRY_MS = 5000;
  constexpr uint32_t HEAP_CHECK_MS = 10000;
  constexpr uint32_t HEALTH_REPORT_MS = 30000;
  constexpr uint32_t IR_DEBOUNCE_MS = 220;
  constexpr uint32_t BTN_DEBOUNCE_MS = 35;
  constexpr uint32_t BTN_BLE_HOLD_MS = 3000;
  constexpr uint32_t BTN_FACTORY_HOLD_MS = 10000;
  constexpr uint32_t WIFI_SCAN_TIMEOUT_MS = 15000;
  constexpr uint32_t PROVISION_WIFI_MS = 15000;

  constexpr uint32_t HEAP_CRITICAL_B = 12000;
  constexpr uint32_t HEAP_LEAK_DELTA = 40000;

  constexpr const char *BLE_DEVICE_NAME = "TinkrNest Setup";
  constexpr const char *OTA_HOSTNAME = "tinkrnest-esp32";
  constexpr const char *OTA_PASSWORD = "tinkrnest";
  constexpr const char *NVS_NAMESPACE = "tnest";

  constexpr const char *SVC_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  constexpr const char *CHR_CMD_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  constexpr const char *CHR_STATUS_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  namespace ir
  {
    constexpr uint32_t BTN_R1 = 0xFF30CF;
    constexpr uint32_t BTN_R2 = 0xFF18E7;
    constexpr uint32_t BTN_R3 = 0xFF7A85;
    constexpr uint32_t BTN_R4 = 0xFF10EF;
    constexpr uint32_t BTN_ALL_ON = 0xFF38C7;
    constexpr uint32_t BTN_ALL_OFF = 0xFF5AA5;
    constexpr uint32_t REPEAT = 0xFFFFFFFF;
  }

  constexpr int V_R0 = V0, V_R1 = V1, V_R2 = V2, V_R3 = V3;
  constexpr int V_ALL_ON = V5, V_ALL_OFF = V6;
  constexpr int V_TEMP = V10, V_HUM = V11;
  constexpr int V_STATUS = V20, V_BLE_MODE = V22, V_PERSIST = V23;
}

enum CmdSource : uint8_t
{
  SRC_LOCAL = 0,
  SRC_BLYNK,
  SRC_BLE,
  SRC_IR,
  SRC_OTA
};
enum RelayOp : uint8_t
{
  RELAY_SET = 0,
  RELAY_TOGGLE,
  RELAY_ALL,
  RELAY_PERSIST_SET,
  RELAY_FACTORY_OFF
};
struct RelayCmd
{
  RelayOp op;
  uint8_t idx;
  uint8_t val;
  CmdSource src;
};

enum SysEvt : uint8_t
{
  SE_BTN_RESTART = 0,
  SE_BTN_BLE,
  SE_BTN_FACTORY,
  SE_OTA_BUSY,
  SE_OTA_DONE,
  SE_HEAP_CRITICAL,
  SE_HEAP_LEAK,
  SE_BROWNOUT
};
struct SysEvent
{
  SysEvt type;
  uint32_t arg;
};

enum WifiEvt : uint8_t
{
  WE_WIFI_UP = 0,
  WE_WIFI_DOWN,
  WE_INET_UP,
  WE_INET_DOWN,
  WE_BLYNK_UP,
  WE_BLYNK_DOWN
};
struct WifiEvent
{
  WifiEvt type;
};

struct BleWork
{
  enum Type : uint8_t
  {
    NOTIFY = 0,
    STATUS,
    WIFI_SCAN,
    PROVISION
  };
  Type type = NOTIFY;
  char text[512]{};
};

struct ScanResult
{
  char payload[512];
};

struct Credentials
{
  bool valid = false;
  char ssid[33] = {0};
  char pass[65] = {0};
  char authTok[64] = {0};
  char tplId[24] = {0};
  char tplName[32] = {0};
};

struct SystemState
{
  bool wifiUp = false;
  bool inetUp = false;
  bool blynkUp = false;
  bool bleActive = false;
  bool otaBusy = false;
  uint8_t relays = 0;
  bool persistEnabled = true;
  float tempC = NAN;
  float humidity = NAN;
  uint32_t bootCount = 0;
  esp_reset_reason_t lastReset = ESP_RST_UNKNOWN;
  uint32_t minHeapSeen = UINT32_MAX;
};

static Credentials gCreds;
static SystemState gState;
static Preferences gPrefs;

static QueueHandle_t gRelayQ = nullptr;
static QueueHandle_t gBleWorkQ = nullptr;
static QueueHandle_t gScanResultQ = nullptr;
static QueueHandle_t gSysQ = nullptr;
static QueueHandle_t gWifiQ = nullptr;
static SemaphoreHandle_t gStateMtx = nullptr;
static SemaphoreHandle_t gNvsMtx = nullptr;
static SemaphoreHandle_t gScanMtx = nullptr;

static TaskHandle_t hWifi = nullptr, hBlynk = nullptr, hBle = nullptr,
                    hRelay = nullptr, hIR = nullptr, hDHT = nullptr,
                    hLed = nullptr, hSys = nullptr;

static volatile uint32_t hbWifi = 0, hbBlynk = 0, hbBle = 0,
                         hbRelay = 0, hbIR = 0, hbDHT = 0, hbLed = 0, hbSys = 0;

static volatile bool gRelayDirty = false;
static volatile uint32_t gLastNvsWrite = 0;

namespace nvs
{
  void begin()
  {
    if (!gPrefs.begin(cfg::NVS_NAMESPACE, false))
    {
      Serial.println("[NVS] mount failed — formatting");
      gPrefs.end();
      gPrefs.begin(cfg::NVS_NAMESPACE, false);
    }
    gState.bootCount = gPrefs.getUInt("boots", 0) + 1;
    gPrefs.putUInt("boots", gState.bootCount);
  }
  void loadCreds()
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gCreds.valid = gPrefs.getBool("cv", false);
    gPrefs.getString("ssid", gCreds.ssid, sizeof(gCreds.ssid));
    gPrefs.getString("pass", gCreds.pass, sizeof(gCreds.pass));
    gPrefs.getString("auth", gCreds.authTok, sizeof(gCreds.authTok));
    gPrefs.getString("tplId", gCreds.tplId, sizeof(gCreds.tplId));
    gPrefs.getString("tplName", gCreds.tplName, sizeof(gCreds.tplName));
    if (!gCreds.ssid[0] || !gCreds.authTok[0])
      gCreds.valid = false;
    xSemaphoreGive(gNvsMtx);
  }
  void saveCreds()
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gPrefs.putString("ssid", gCreds.ssid);
    gPrefs.putString("pass", gCreds.pass);
    gPrefs.putString("auth", gCreds.authTok);
    gPrefs.putString("tplId", gCreds.tplId);
    gPrefs.putString("tplName", gCreds.tplName);
    gPrefs.putBool("cv", true);
    gCreds.valid = true;
    xSemaphoreGive(gNvsMtx);
  }
  void loadSettings()
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gState.persistEnabled = gPrefs.getBool("persist", true);
    gState.relays = gState.persistEnabled ? gPrefs.getUChar("relays", 0) : 0;
    xSemaphoreGive(gNvsMtx);
  }
  void saveRelays(uint8_t bits)
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gPrefs.putUChar("relays", bits);
    xSemaphoreGive(gNvsMtx);
  }
  void savePersist(bool en)
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gPrefs.putBool("persist", en);
    xSemaphoreGive(gNvsMtx);
  }
  void factoryReset()
  {
    xSemaphoreTake(gNvsMtx, portMAX_DELAY);
    gPrefs.clear();
    xSemaphoreGive(gNvsMtx);
    gCreds.valid = false;
    gCreds.ssid[0] = gCreds.authTok[0] = 0;
    Serial.println("[NVS] factory reset complete");
  }
}

namespace relayHw
{
  inline void write(uint8_t i, bool on)
  {
    if (i >= cfg::RELAY_COUNT)
      return;
    digitalWrite(cfg::PIN_RELAY[i], (on ^ !cfg::RELAY_ACTIVE_HIGH) ? HIGH : LOW);
  }
  void initPins(uint8_t initialBits, bool persistEnabled)
  {
    for (uint8_t i = 0; i < cfg::RELAY_COUNT; i++)
    {
      pinMode(cfg::PIN_RELAY[i], OUTPUT);
      bool on = persistEnabled && ((initialBits >> i) & 1);
      write(i, on);
    }
  }
  void applyAll(uint8_t bits)
  {
    for (uint8_t i = 0; i < cfg::RELAY_COUNT; i++)
      write(i, (bits >> i) & 1);
  }
}

namespace led
{
  enum Pattern
  {
    OFF,
    SOLID,
    FAST,
    SLOW,
    DOUBLE_BLINK,
    FLASH_RELAY,
    FLASH_IR
  };
  volatile Pattern cur = FAST;
  Pattern saved = FAST;
  uint32_t tA = 0;
  uint8_t step = 0;
  uint32_t overrideUntil = 0;
  bool pinHi = false;

  inline void hw(bool on)
  {
    digitalWrite(cfg::PIN_LED, on);
    pinHi = on;
  }

  void choose()
  {
    if (millis() < overrideUntil)
      return;
    Pattern n;
    if (!gCreds.valid)
      n = FAST;
    else if (!gState.wifiUp)
      n = SLOW;
    else if (!gState.inetUp)
      n = SLOW;
    else if (!gState.blynkUp)
      n = DOUBLE_BLINK;
    else
      n = SOLID;
    if (n != cur)
    {
      cur = n;
      step = 0;
      tA = millis();
    }
  }
  void flash(Pattern p, uint32_t ms)
  {
    if (millis() >= overrideUntil)
      saved = cur;
    cur = p;
    step = 0;
    tA = millis();
    overrideUntil = millis() + ms;
    if (hLed)
      xTaskNotifyGive(hLed);
  }
  void tick()
  {
    uint32_t now = millis();
    if (overrideUntil && now >= overrideUntil)
    {
      overrideUntil = 0;
      cur = saved;
      step = 0;
      tA = now;
    }
    switch (cur)
    {
    case OFF:
      if (pinHi)
        hw(false);
      break;
    case SOLID:
      if (!pinHi)
        hw(true);
      break;
    case FAST:
      if (now - tA >= 150)
      {
        tA = now;
        hw(!pinHi);
      }
      break;
    case SLOW:
      if (now - tA >= 900)
      {
        tA = now;
        hw(!pinHi);
      }
      break;
    case DOUBLE_BLINK:
    {
      static const uint16_t S[] = {80, 100, 80, 900};
      if (now - tA >= S[step])
      {
        tA = now;
        hw(!(step & 1));
        step = (step + 1) & 3;
      }
      break;
    }
    case FLASH_RELAY:
    {
      static const uint16_t S[] = {50, 50, 50, 50};
      if (now - tA >= S[step])
      {
        tA = now;
        hw(!pinHi);
        if (++step >= 4)
          overrideUntil = now;
      }
      break;
    }
    case FLASH_IR:
      if (step == 0)
      {
        hw(true);
        step = 1;
        tA = now;
      }
      else if (now - tA >= 30)
      {
        hw(false);
        overrideUntil = now;
      }
      break;
    }
  }
}

namespace irmgr
{
  IRrecv *recv = nullptr;
  decode_results res;
  uint32_t lastCode = 0;
  uint32_t lastMs = 0;

  void begin()
  {
    recv = new IRrecv(cfg::PIN_IR, 1024, 50, true);
    recv->enableIRIn();
  }
  void poll()
  {
    if (!recv || !recv->decode(&res))
      return;
    uint32_t code = res.value;
    recv->resume();
    uint32_t now = millis();
    if (code == cfg::ir::REPEAT)
      code = lastCode;
    else
      lastCode = code;
    if (now - lastMs < cfg::IR_DEBOUNCE_MS)
      return;
    lastMs = now;

    RelayCmd c{};
    c.src = SRC_IR;
    switch (code)
    {
    case cfg::ir::BTN_R1:
      c.op = RELAY_TOGGLE;
      c.idx = 0;
      break;
    case cfg::ir::BTN_R2:
      c.op = RELAY_TOGGLE;
      c.idx = 1;
      break;
    case cfg::ir::BTN_R3:
      c.op = RELAY_TOGGLE;
      c.idx = 2;
      break;
    case cfg::ir::BTN_R4:
      c.op = RELAY_TOGGLE;
      c.idx = 3;
      break;
    case cfg::ir::BTN_ALL_ON:
      c.op = RELAY_ALL;
      c.val = 1;
      break;
    case cfg::ir::BTN_ALL_OFF:
      c.op = RELAY_ALL;
      c.val = 0;
      break;
    default:
      return;
    }
    xQueueSend(gRelayQ, &c, 0);
    led::flash(led::FLASH_IR, 60);
  }
}

namespace dhtmgr
{
  DHT *sensor = nullptr;
  uint8_t failStreak = 0;
  bool warned = false;
  void begin()
  {
    sensor = new DHT(cfg::PIN_DHT, cfg::DHT_TYPE);
    sensor->begin();
  }
  void sample()
  {
    float h = sensor->readHumidity();
    float t = sensor->readTemperature();
    if (isnan(h) || isnan(t) || h < 0 || h > 100 || t < -40 || t > 85)
    {
      if (++failStreak >= 5 && !warned)
      {
        Serial.println("[DHT] sensor unavailable — further warnings suppressed");
        warned = true;
      }
      return;
    }
    failStreak = 0;
    warned = false;
    xSemaphoreTake(gStateMtx, portMAX_DELAY);
    gState.tempC = t;
    gState.humidity = h;
    xSemaphoreGive(gStateMtx);
  }
}

namespace btnmgr
{
  bool prev = true;
  uint32_t pressMs = 0, lastEdge = 0;
  bool fired3s = false, fired10s = false;
  void poll()
  {
    bool now = digitalRead(cfg::PIN_BTN);
    uint32_t t = millis();
    if (now != prev && (t - lastEdge) > cfg::BTN_DEBOUNCE_MS)
    {
      lastEdge = t;
      if (now == LOW)
      {
        pressMs = t;
        fired3s = false;
        fired10s = false;
      }
      else
      {
        uint32_t held = t - pressMs;
        SysEvent e{};
        if (held >= cfg::BTN_FACTORY_HOLD_MS)
          e.type = SE_BTN_FACTORY;
        else if (held >= cfg::BTN_BLE_HOLD_MS)
          e.type = SE_BTN_BLE;
        else if (held >= 30)
          e.type = SE_BTN_RESTART;
        else
        {
          prev = now;
          return;
        }
        xQueueSend(gSysQ, &e, 0);
      }
      prev = now;
    }
    if (now == LOW)
    {
      uint32_t held = t - pressMs;
      if (!fired3s && held >= cfg::BTN_BLE_HOLD_MS)
      {
        fired3s = true;
        led::flash(led::FLASH_RELAY, 300);
      }
      if (!fired10s && held >= cfg::BTN_FACTORY_HOLD_MS)
      {
        fired10s = true;
        led::flash(led::FAST, 1000);
      }
    }
  }
}

namespace blemgr
{
  NimBLEServer *server = nullptr;
  NimBLECharacteristic *chrCmd = nullptr;
  NimBLECharacteristic *chrStatus = nullptr;
  volatile bool advertising = false;

  bool enqueueWork(BleWork::Type type, const char *text = nullptr)
  {
    BleWork w{};
    w.type = type;
    if (text)
      strlcpy(w.text, text, sizeof(w.text));
    if (xQueueSend(gBleWorkQ, &w, pdMS_TO_TICKS(200)) != pdTRUE)
    {
      Serial.println("[BLE] work queue full — dropped");
      return false;
    }
    return true;
  }

  void enqueueStatus(const char *s)
  {
    if (!s)
      return;
    enqueueWork(BleWork::NOTIFY, s);
  }

  void notifyNow(const char *s)
  {
    if (!chrStatus || !s)
      return;
    const size_t len = strlen(s);
    chrStatus->setValue((uint8_t *)s, len);
    chrStatus->notify();
    Serial.printf("[BLE] notify sent (%u bytes)\n", (unsigned)len);
  }

  void sendStatusResponse()
  {
    Serial.println("[BLE] STATUS request");
    JsonDocument d;
    d["fw"] = BLYNK_FIRMWARE_VERSION;
    d["wifi"] = gState.wifiUp;
    d["inet"] = gState.inetUp;
    d["blynk"] = gState.blynkUp;
    d["setup"] = !gCreds.valid;
    d["ble"] = gState.bleActive;
    d["t"] = gState.tempC;
    d["h"] = gState.humidity;
    d["persist"] = gState.persistEnabled;
    d["relays"] = gState.relays;
    char out[256];
    serializeJson(d, out, sizeof(out));
    Serial.printf("[BLE] STATUS response sent: %s\n", out);
    notifyNow(out);
  }

  static void scanWorkerTask(void *)
  {
    esp_task_wdt_add(NULL);
    Serial.println("[SCAN] worker started");

    ScanResult result{};
    bool driverStartedHere = false;

    wifi_mode_t currentMode = WIFI_MODE_NULL;
    esp_err_t modeErr = esp_wifi_get_mode(&currentMode);

    Serial.printf("[SCAN] WiFi driver mode check: mode=%d err=%d\n",
                  (int)currentMode, (int)modeErr);

    if (modeErr != ESP_OK || currentMode == WIFI_MODE_NULL)
    {
      Serial.println("[SCAN] WiFi driver not started — calling WiFi.mode(WIFI_STA)");
      WiFi.mode(WIFI_STA);
      vTaskDelay(pdMS_TO_TICKS(500));

      modeErr = esp_wifi_get_mode(&currentMode);
      if (modeErr != ESP_OK || currentMode == WIFI_MODE_NULL)
      {
        Serial.println("[SCAN] WiFi driver failed to start");
        strlcpy(result.payload, "ERR:WIFI_NOT_READY", sizeof(result.payload));
        goto done;
      }
      driverStartedHere = true;
    }

    WiFi.scanDelete();
    WiFi.setAutoReconnect(false);
    WiFi.disconnect(true, false);
    vTaskDelay(pdMS_TO_TICKS(100));

    {
      Serial.println("[SCAN] starting async WiFi scan");
      int asyncRet = WiFi.scanNetworks(true, true);
      Serial.printf("[SCAN] async scan started: %d\n", asyncRet);
      if (asyncRet != WIFI_SCAN_RUNNING && asyncRet < 0)
      {
        WiFi.scanDelete();
        strlcpy(result.payload, "ERR:SCAN_FAILED", sizeof(result.payload));
        goto done;
      }

      const uint32_t workerDeadline = millis() + cfg::WIFI_SCAN_TIMEOUT_MS;
      int n = (asyncRet > 0 ? asyncRet : WIFI_SCAN_RUNNING);

      while (n == WIFI_SCAN_RUNNING && millis() < workerDeadline)
      {
        esp_task_wdt_reset();
        n = WiFi.scanComplete();
        if (n != WIFI_SCAN_RUNNING)
          break;
        vTaskDelay(pdMS_TO_TICKS(250));
      }

      if (n == WIFI_SCAN_RUNNING)
      {
        Serial.println("[SCAN] async scan timed out, retrying sync scan");
        WiFi.scanDelete();
        n = WiFi.scanNetworks(false, true);
        Serial.printf("[SCAN] sync scan result: %d\n", n);
      }

      if (n == WIFI_SCAN_RUNNING)
      {
        WiFi.scanDelete();
        strlcpy(result.payload, "ERR:SCAN_TIMEOUT", sizeof(result.payload));
        goto done;
      }
      if (n < 0)
      {
        WiFi.scanDelete();
        strlcpy(result.payload, "ERR:SCAN_FAILED", sizeof(result.payload));
        goto done;
      }

      Serial.printf("[SCAN] scan complete count=%d\n", n);

      JsonDocument d;
      JsonArray arr = d["networks"].to<JsonArray>();

      for (int i = 0; i < n; i++)
      {
        String ssid = WiFi.SSID(i);
        if (ssid.length() == 0)
          continue;
        int rssi = WiFi.RSSI(i);
        bool secure = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;

        bool merged = false;
        for (JsonObject existing : arr)
        {
          const char *ex = existing["ssid"] | "";
          if (strcmp(ex, ssid.c_str()) != 0)
            continue;
          merged = true;
          if (rssi > (existing["rssi"] | -999))
          {
            existing["rssi"] = rssi;
            existing["sec"] = secure ? 1 : 0;
          }
          break;
        }
        if (!merged && arr.size() < 15)
        {
          JsonObject net = arr.add<JsonObject>();
          net["ssid"] = ssid;
          net["rssi"] = rssi;
          net["sec"] = secure ? 1 : 0;
        }
      }
      d["count"] = arr.size();
      serializeJson(d, result.payload, sizeof(result.payload));
      WiFi.scanDelete();
    }

  done:
    if (driverStartedHere && !gCreds.valid)
    {
      WiFi.mode(WIFI_MODE_NULL);
    }

    if (xQueueSend(gScanResultQ, &result, 0) != pdTRUE)
    {
      Serial.println("[SCAN] result queue full — discarding");
    }
    else
    {
      Serial.printf("[SCAN] result posted: %s\n", result.payload);
    }

    xSemaphoreGive(gScanMtx);
    esp_task_wdt_delete(NULL);
    vTaskDelete(NULL);
  }

  void sendWifiScanResponse()
  {
    if (xSemaphoreTake(gScanMtx, 0) != pdTRUE)
    {
      notifyNow("ERR:SCAN_BUSY");
      return;
    }

    ScanResult stale{};
    while (xQueueReceive(gScanResultQ, &stale, 0) == pdTRUE)
    {
    }

    BaseType_t ok = xTaskCreatePinnedToCore(
        scanWorkerTask, "scanW", 7168, NULL, 3, NULL, 1);

    if (ok != pdPASS)
    {
      xSemaphoreGive(gScanMtx);
      notifyNow("ERR:SCAN_OOM");
      return;
    }

    const uint32_t deadline = millis() + cfg::WIFI_SCAN_TIMEOUT_MS;
    ScanResult result{};
    bool gotResult = false;

    while (millis() < deadline)
    {
      esp_task_wdt_reset();
      if (xQueueReceive(gScanResultQ, &result, pdMS_TO_TICKS(200)) == pdTRUE)
      {
        gotResult = true;
        break;
      }
    }

    if (!gotResult)
    {
      notifyNow("ERR:SCAN_TIMEOUT");
      return;
    }

    notifyNow(result.payload);
  }

  // Runs in bleTask. WiFi is NOT tested here — starting WiFi while BLE is
  // connected causes ESP32 coex LINK_SUPERVISION_TIMEOUT. Credentials are
  // saved to NVS, OK:SAVED is sent, then the device reboots and connects.
  void runProvisioning(const char *jsonText)
  {
    Serial.println("[BLE] PROVISION started");

    JsonDocument doc;
    if (deserializeJson(doc, jsonText))
    {
      notifyNow("ERR:JSON");
      return;
    }

    const char *ssid = doc["ssid"] | "";
    const char *pass = doc["pass"] | "";
    const char *auth = doc["auth"] | "";
    const char *tid = doc["tplId"] | "";
    const char *tnm = doc["tplName"] | "";

    if (!ssid[0] || !auth[0])
    {
      notifyNow("ERR:MISSING");
      return;
    }
    if (strlen(auth) < 20)
    {
      notifyNow("ERR:MISSING");
      return;
    }

    notifyNow("TESTING");
    vTaskDelay(pdMS_TO_TICKS(200));
    esp_task_wdt_reset();

    strlcpy(gCreds.ssid, ssid, sizeof(gCreds.ssid));
    strlcpy(gCreds.pass, pass, sizeof(gCreds.pass));
    strlcpy(gCreds.authTok, auth, sizeof(gCreds.authTok));
    strlcpy(gCreds.tplId, tid, sizeof(gCreds.tplId));
    strlcpy(gCreds.tplName, tnm, sizeof(gCreds.tplName));
    nvs::saveCreds();

    Serial.printf("[BLE] PROVISION saved ssid=%s — notifying client\n", gCreds.ssid);
    notifyNow("OK:SAVED");

    // Give the phone time to receive OK:SAVED before reboot drops BLE.
    vTaskDelay(pdMS_TO_TICKS(1200));
    esp_task_wdt_reset();

    Serial.println("[BLE] PROVISION complete — rebooting");
    esp_restart();
  }

  void handleCmd(const std::string &v)
  {
    String s(v.c_str());
    s.trim();
    if (s.length() == 0)
      return;

    if (s.startsWith("{"))
    {
      Serial.println("[BLE] Command received: {json provisioning}");
      if (!enqueueWork(BleWork::PROVISION, s.c_str()))
      {
        enqueueStatus("ERR:BUSY");
      }
      return;
    }

    Serial.printf("[BLE] Command received: %s\n", s.c_str());

    RelayCmd c{};
    c.src = SRC_BLE;
    if (s == "R1:1")
    {
      c.op = RELAY_SET;
      c.idx = 0;
      c.val = 1;
    }
    else if (s == "R1:0")
    {
      c.op = RELAY_SET;
      c.idx = 0;
      c.val = 0;
    }
    else if (s == "R2:1")
    {
      c.op = RELAY_SET;
      c.idx = 1;
      c.val = 1;
    }
    else if (s == "R2:0")
    {
      c.op = RELAY_SET;
      c.idx = 1;
      c.val = 0;
    }
    else if (s == "R3:1")
    {
      c.op = RELAY_SET;
      c.idx = 2;
      c.val = 1;
    }
    else if (s == "R3:0")
    {
      c.op = RELAY_SET;
      c.idx = 2;
      c.val = 0;
    }
    else if (s == "R4:1")
    {
      c.op = RELAY_SET;
      c.idx = 3;
      c.val = 1;
    }
    else if (s == "R4:0")
    {
      c.op = RELAY_SET;
      c.idx = 3;
      c.val = 0;
    }
    else if (s == "ALL:1")
    {
      c.op = RELAY_ALL;
      c.val = 1;
    }
    else if (s == "ALL:0")
    {
      c.op = RELAY_ALL;
      c.val = 0;
    }
    else if (s == "PERSIST:1")
    {
      c.op = RELAY_PERSIST_SET;
      c.val = 1;
    }
    else if (s == "PERSIST:0")
    {
      c.op = RELAY_PERSIST_SET;
      c.val = 0;
    }
    else if (s == "REBOOT")
    {
      SysEvent e{SE_BTN_RESTART, 0};
      xQueueSend(gSysQ, &e, 0);
      enqueueStatus("OK");
      return;
    }
    else if (s == "STATUS")
    {
      enqueueWork(BleWork::STATUS);
      return;
    }
    else if (s == "WIFI_SCAN")
    {
      enqueueWork(BleWork::WIFI_SCAN);
      return;
    }
    else
    {
      enqueueStatus("ERR:UNKNOWN");
      return;
    }

    xQueueSend(gRelayQ, &c, 0);
    enqueueStatus("OK");
  }

  class CmdCb : public NimBLECharacteristicCallbacks
  {
    void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &connInfo) override
    {
      handleCmd(c->getValue());
    }
  };
  class SrvCb : public NimBLEServerCallbacks
  {
    void onConnect(NimBLEServer *, NimBLEConnInfo &connInfo) override
    {
      Serial.println("[BLE] Connected");
    }
    void onDisconnect(NimBLEServer *s, NimBLEConnInfo &connInfo, int reason) override
    {
      Serial.println("[BLE] client disconnected");
      if (advertising)
        s->startAdvertising();
    }
  };

  void start()
  {
    if (advertising)
    {
      NimBLEDevice::getAdvertising()->start();
      return;
    }

    NimBLEDevice::init(cfg::BLE_DEVICE_NAME);
    NimBLEDevice::setMTU(517);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setSecurityAuth(false, false, false);

    server = NimBLEDevice::createServer();
    server->setCallbacks(new SrvCb());

    auto *svc = server->createService(cfg::SVC_UUID);

    chrCmd = svc->createCharacteristic(cfg::CHR_CMD_UUID,
                                       NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    chrCmd->setCallbacks(new CmdCb());

    chrStatus = svc->createCharacteristic(cfg::CHR_STATUS_UUID,
                                          NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    chrStatus->createDescriptor("2902",
                                NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE);

    svc->start();

    auto *adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(cfg::SVC_UUID);
    adv->setName(cfg::BLE_DEVICE_NAME);
    adv->setScanResponseData(NimBLEAdvertisementData());
    adv->start();

    advertising = true;
    gState.bleActive = true;
    led::choose();
    Serial.println("[BLE] advertising as 'TinkrNest Setup'");
  }

  void restartAdvertising()
  {
    if (!advertising)
    {
      start();
      return;
    }
    auto *adv = NimBLEDevice::getAdvertising();
    adv->stop();
    vTaskDelay(pdMS_TO_TICKS(50));
    adv->start();
    Serial.println("[BLE] advertising restarted");
  }
}

namespace wifimgr
{
  uint32_t lastRetry = 0;
  void onEvent(WiFiEvent_t ev)
  {
    WifiEvent e{};
    switch (ev)
    {
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      e.type = WE_WIFI_UP;
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      e.type = WE_WIFI_DOWN;
      break;
    default:
      return;
    }
    xQueueSend(gWifiQ, &e, 0);
  }
  void begin()
  {
    WiFi.onEvent(onEvent);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.persistent(false);
    WiFi.setSleep(WIFI_PS_MIN_MODEM);
    if (gCreds.valid && gCreds.ssid[0])
    {
      WiFi.begin(gCreds.ssid, gCreds.pass);
      lastRetry = millis();
    }
  }
  void retryIfNeeded()
  {
    if (!gCreds.valid)
      return;
    if (WiFi.status() == WL_CONNECTED)
      return;
    if (millis() - lastRetry < cfg::WIFI_RETRY_MS)
      return;
    lastRetry = millis();
    WiFi.disconnect(false, false);
    WiFi.begin(gCreds.ssid, gCreds.pass);
    Serial.println("[WiFi] retry");
  }
}

namespace inet
{
  uint32_t lastMs = 0;
  IPAddress probeIP;
  void tick()
  {
    if (!gState.wifiUp)
    {
      if (gState.inetUp)
      {
        WifiEvent e{WE_INET_DOWN};
        xQueueSend(gWifiQ, &e, 0);
      }
      return;
    }
    if (millis() - lastMs < cfg::INET_PROBE_MS)
      return;
    lastMs = millis();
    bool ok = WiFi.hostByName("blynk.cloud", probeIP) == 1;
    if (ok != gState.inetUp)
    {
      WifiEvent e{ok ? WE_INET_UP : WE_INET_DOWN};
      xQueueSend(gWifiQ, &e, 0);
    }
  }
}

namespace blynkmgr
{
  bool configured = false;
  uint32_t lastTry = 0;
  void configure()
  {
    if (configured || !gCreds.valid || strlen(gCreds.authTok) < 20)
      return;
    Blynk.config(gCreds.authTok, "blynk.cloud", 80);
    configured = true;
  }
  void tick()
  {
    if (!configured || !gState.wifiUp || !gState.inetUp)
      return;
    if (Blynk.connected())
    {
      Blynk.run();
      return;
    }
    if (millis() - lastTry < cfg::BLYNK_RETRY_MS)
      return;
    lastTry = millis();
    Blynk.connect(0);
  }
  void pushAll()
  {
    if (!Blynk.connected())
      return;
    for (uint8_t i = 0; i < cfg::RELAY_COUNT; i++)
      Blynk.virtualWrite(V0 + i, (gState.relays >> i) & 1 ? 1 : 0);
    Blynk.virtualWrite(cfg::V_TEMP, gState.tempC);
    Blynk.virtualWrite(cfg::V_HUM, gState.humidity);
    Blynk.virtualWrite(cfg::V_STATUS, "online");
    Blynk.virtualWrite(cfg::V_BLE_MODE, gState.bleActive ? 1 : 0);
    Blynk.virtualWrite(cfg::V_PERSIST, gState.persistEnabled ? 1 : 0);
  }
}

#define BLYNK_RELAY_CB(VP, IDX)                                              \
  BLYNK_WRITE(VP)                                                            \
  {                                                                          \
    RelayCmd c{RELAY_SET, IDX, (uint8_t)(param.asInt() ? 1 : 0), SRC_BLYNK}; \
    xQueueSend(gRelayQ, &c, 0);                                              \
  }
BLYNK_RELAY_CB(V0, 0)
BLYNK_RELAY_CB(V1, 1)
BLYNK_RELAY_CB(V2, 2)
BLYNK_RELAY_CB(V3, 3)

BLYNK_WRITE(V5)
{
  if (param.asInt())
  {
    RelayCmd c{RELAY_ALL, 0, 1, SRC_BLYNK};
    xQueueSend(gRelayQ, &c, 0);
  }
}
BLYNK_WRITE(V6)
{
  if (param.asInt())
  {
    RelayCmd c{RELAY_ALL, 0, 0, SRC_BLYNK};
    xQueueSend(gRelayQ, &c, 0);
  }
}
BLYNK_WRITE(V22)
{
  if (param.asInt())
  {
    SysEvent e{SE_BTN_BLE, 0};
    xQueueSend(gSysQ, &e, 0);
  }
}
BLYNK_WRITE(V23)
{
  RelayCmd c{RELAY_PERSIST_SET, 0, (uint8_t)(param.asInt() ? 1 : 0), SRC_BLYNK};
  xQueueSend(gRelayQ, &c, 0);
}

BLYNK_CONNECTED()
{
  WifiEvent e{WE_BLYNK_UP};
  xQueueSend(gWifiQ, &e, 0);
}

BLYNK_DISCONNECTED()
{
  WifiEvent e{WE_BLYNK_DOWN};
  xQueueSend(gWifiQ, &e, 0);
}

namespace otamgr
{
  void begin()
  {
    ArduinoOTA.setHostname(cfg::OTA_HOSTNAME);
    ArduinoOTA.setPassword(cfg::OTA_PASSWORD);
    ArduinoOTA.onStart([]
                       {
      SysEvent e{SE_OTA_BUSY,0}; xQueueSend(gSysQ,&e,0); });
    ArduinoOTA.onEnd([]
                     {
      SysEvent e{SE_OTA_DONE,0}; xQueueSend(gSysQ,&e,0); });
    ArduinoOTA.onProgress([](unsigned p, unsigned t)
                          {
      static uint8_t lastPct = 255;
      uint8_t pct = (p * 100) / t;
      if (pct != lastPct && (pct % 5 == 0)) { lastPct = pct; Serial.printf("[OTA] %u%%\n", pct); } });
    ArduinoOTA.onError([](ota_error_t err)
                       {
      Serial.printf("[OTA] error %u\n", err);
      SysEvent e{SE_OTA_DONE,0}; xQueueSend(gSysQ,&e,0); });
    ArduinoOTA.begin();
  }
  void tick()
  {
    if (gState.wifiUp)
      ArduinoOTA.handle();
  }
}

static void broadcastRelay(uint8_t idx, bool on, CmdSource src)
{
  if (src != SRC_BLYNK && Blynk.connected())
    Blynk.virtualWrite(V0 + idx, on ? 1 : 0);
  if (src != SRC_BLE && blemgr::chrStatus)
  {
    char buf[16];
    snprintf(buf, sizeof(buf), "R%u:%u", idx + 1, on ? 1 : 0);
    blemgr::enqueueStatus(buf);
  }
}
static void applyRelaySet(uint8_t idx, bool on, CmdSource src)
{
  if (idx >= cfg::RELAY_COUNT)
    return;
  uint8_t newR = on ? (gState.relays | (1 << idx))
                    : (gState.relays & ~(1 << idx));
  if (newR == gState.relays)
    return;
  xSemaphoreTake(gStateMtx, portMAX_DELAY);
  gState.relays = newR;
  xSemaphoreGive(gStateMtx);
  relayHw::write(idx, on);
  gRelayDirty = true;
  led::flash(led::FLASH_RELAY, 250);
  broadcastRelay(idx, on, src);
}
static void applyAll(bool on, CmdSource src)
{
  uint8_t target = on ? 0x0F : 0x00;
  if (target == gState.relays)
    return;
  for (uint8_t i = 0; i < cfg::RELAY_COUNT; i++)
  {
    bool s = (target >> i) & 1;
    if (((gState.relays >> i) & 1) != s)
      relayHw::write(i, s);
  }
  xSemaphoreTake(gStateMtx, portMAX_DELAY);
  gState.relays = target;
  xSemaphoreGive(gStateMtx);
  gRelayDirty = true;
  led::flash(led::FLASH_RELAY, 250);
  if (src != SRC_BLYNK && Blynk.connected())
    blynkmgr::pushAll();
  if (src != SRC_BLE && blemgr::chrStatus)
    blemgr::enqueueStatus(on ? "ALL:1" : "ALL:0");
}

static void relayTask(void *)
{
  esp_task_wdt_add(NULL);
  RelayCmd c;
  for (;;)
  {
    esp_task_wdt_reset();
    hbRelay = millis();
    if (xQueueReceive(gRelayQ, &c, pdMS_TO_TICKS(100)) == pdTRUE)
    {
      switch (c.op)
      {
      case RELAY_SET:
        applyRelaySet(c.idx, c.val, c.src);
        break;
      case RELAY_TOGGLE:
        applyRelaySet(c.idx, !((gState.relays >> c.idx) & 1), c.src);
        break;
      case RELAY_ALL:
        applyAll(c.val != 0, c.src);
        break;
      case RELAY_PERSIST_SET:
      {
        bool on = c.val != 0;
        if (on != gState.persistEnabled)
        {
          gState.persistEnabled = on;
          nvs::savePersist(on);
          if (!on)
          {
            applyAll(false, SRC_LOCAL);
            nvs::saveRelays(0);
          }
          if (Blynk.connected())
          {
            Blynk.virtualWrite(cfg::V_PERSIST, on ? 1 : 0);
            blynkmgr::pushAll();
          }
          if (blemgr::chrStatus)
            blemgr::enqueueStatus(on ? "PERSIST:1" : "PERSIST:0");
        }
        break;
      }
      case RELAY_FACTORY_OFF:
        applyAll(false, SRC_LOCAL);
        break;
      }
    }
    if (gRelayDirty && gState.persistEnabled &&
        (millis() - gLastNvsWrite) >= cfg::NVS_DEBOUNCE_MS)
    {
      nvs::saveRelays(gState.relays);
      gRelayDirty = false;
      gLastNvsWrite = millis();
    }
  }
}

static void irTask(void *)
{
  esp_task_wdt_add(NULL);
  for (;;)
  {
    esp_task_wdt_reset();
    hbIR = millis();
    irmgr::poll();
    btnmgr::poll();
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

static void dhtTask(void *)
{
  esp_task_wdt_add(NULL);
  for (;;)
  {
    esp_task_wdt_reset();
    hbDHT = millis();
    dhtmgr::sample();
    vTaskDelay(pdMS_TO_TICKS(cfg::DHT_PERIOD_MS));
  }
}

static void ledTask(void *)
{
  esp_task_wdt_add(NULL);
  for (;;)
  {
    esp_task_wdt_reset();
    hbLed = millis();
    led::choose();
    led::tick();
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(40));
  }
}

static void wifiTask(void *)
{
  esp_task_wdt_add(NULL);
  WifiEvent ev;
  for (;;)
  {
    esp_task_wdt_reset();
    hbWifi = millis();
    if (xQueueReceive(gWifiQ, &ev, pdMS_TO_TICKS(100)) == pdTRUE)
    {
      switch (ev.type)
      {
      case WE_WIFI_UP:
        gState.wifiUp = true;
        Serial.printf("[WiFi] up, IP=%s\n", WiFi.localIP().toString().c_str());
        break;
      case WE_WIFI_DOWN:
        gState.wifiUp = false;
        gState.inetUp = false;
        gState.blynkUp = false;
        break;
      case WE_INET_UP:
        gState.inetUp = true;
        break;
      case WE_INET_DOWN:
        gState.inetUp = false;
        gState.blynkUp = false;
        break;
      case WE_BLYNK_UP:
        gState.blynkUp = true;
        blynkmgr::pushAll();
        break;
      case WE_BLYNK_DOWN:
        gState.blynkUp = false;
        break;
      }
      led::choose();
    }
    wifimgr::retryIfNeeded();
    inet::tick();
    otamgr::tick();
  }
}

static void blynkTask(void *)
{
  esp_task_wdt_add(NULL);
  for (;;)
  {
    esp_task_wdt_reset();
    hbBlynk = millis();
    blynkmgr::tick();
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

static void bleTask(void *)
{
  esp_task_wdt_add(NULL);
  BleWork w;
  for (;;)
  {
    esp_task_wdt_reset();
    hbBle = millis();
    if (xQueueReceive(gBleWorkQ, &w, pdMS_TO_TICKS(150)) != pdTRUE)
      continue;
    switch (w.type)
    {
    case BleWork::STATUS:
      blemgr::sendStatusResponse();
      break;
    case BleWork::WIFI_SCAN:
      blemgr::sendWifiScanResponse();
      break;
    case BleWork::PROVISION:
      blemgr::runProvisioning(w.text);
      break;
    case BleWork::NOTIFY:
    default:
      if (blemgr::chrStatus)
        blemgr::notifyNow(w.text);
      break;
    }
  }
}

static void sysTask(void *)
{
  esp_task_wdt_add(NULL);
  uint32_t lastHeap = millis();
  uint32_t lastHealth = millis();
  uint32_t baselineHeap = 0;
  SysEvent ev;

  for (;;)
  {
    esp_task_wdt_reset();
    hbSys = millis();

    if (xQueueReceive(gSysQ, &ev, pdMS_TO_TICKS(100)) == pdTRUE)
    {
      switch (ev.type)
      {
      case SE_BTN_RESTART:
        Serial.println("[Btn] short press → restart");
        vTaskDelay(pdMS_TO_TICKS(200));
        esp_restart();
        break;
      case SE_BTN_BLE:
        Serial.println("[Btn] 3s hold → restart BLE advertising");
        blemgr::restartAdvertising();
        break;
      case SE_BTN_FACTORY:
      {
        Serial.println("[Btn] 10s hold → FACTORY RESET");
        Serial.println("[Btn] Device will reboot into BLE setup mode");
        RelayCmd c{RELAY_FACTORY_OFF, 0, 0, SRC_LOCAL};
        xQueueSend(gRelayQ, &c, 0);
        vTaskDelay(pdMS_TO_TICKS(300));
        nvs::factoryReset();
        vTaskDelay(pdMS_TO_TICKS(300));
        esp_restart();
        break;
      }
      case SE_OTA_BUSY:
        gState.otaBusy = true;
        led::flash(led::FAST, 60000);
        break;
      case SE_OTA_DONE:
        gState.otaBusy = false;
        led::choose();
        break;
      case SE_HEAP_CRITICAL:
        Serial.println("[Sys] CRITICAL heap — restarting");
        vTaskDelay(pdMS_TO_TICKS(200));
        esp_restart();
        break;
      case SE_HEAP_LEAK:
        Serial.printf("[Sys] heap leak suspected: drop=%lu\n", (unsigned long)ev.arg);
        break;
      case SE_BROWNOUT:
        Serial.println("[Sys] brownout signaled — relays off");
        {
          RelayCmd c{RELAY_FACTORY_OFF, 0, 0, SRC_LOCAL};
          xQueueSend(gRelayQ, &c, 0);
        }
        break;
      }
    }

    if (millis() - lastHeap >= cfg::HEAP_CHECK_MS)
    {
      lastHeap = millis();
      uint32_t h = ESP.getFreeHeap();
      if (h < gState.minHeapSeen)
        gState.minHeapSeen = h;
      if (baselineHeap == 0)
        baselineHeap = h;
      if (h < cfg::HEAP_CRITICAL_B)
      {
        SysEvent e{SE_HEAP_CRITICAL, h};
        xQueueSend(gSysQ, &e, 0);
      }
      else if (baselineHeap > h && (baselineHeap - h) > cfg::HEAP_LEAK_DELTA)
      {
        SysEvent e{SE_HEAP_LEAK, baselineHeap - h};
        xQueueSend(gSysQ, &e, 0);
        baselineHeap = h;
      }
    }

    if (millis() - lastHealth >= cfg::HEALTH_REPORT_MS)
    {
      lastHealth = millis();
      uint32_t now = millis();
      struct
      {
        const char *n;
        volatile uint32_t *hb;
        uint32_t limit;
      } tasks[] = {
          {"wifi", &hbWifi, 10000},
          {"blynk", &hbBlynk, 10000},
          {"ble", &hbBle, cfg::WIFI_SCAN_TIMEOUT_MS + 4000},
          {"relay", &hbRelay, 10000},
          {"ir", &hbIR, 10000},
          {"dht", &hbDHT, 10000},
          {"led", &hbLed, 10000},
          {"sys", &hbSys, 10000},
      };
      bool stuck = false;
      for (auto &t : tasks)
      {
        if (now - *t.hb > t.limit)
        {
          Serial.printf("[Health] STUCK task '%s' age=%lums\n", t.n, (unsigned long)(now - *t.hb));
          stuck = true;
        }
      }
      if (stuck)
      {
        Serial.println("[Health] task hang → restart");
        vTaskDelay(pdMS_TO_TICKS(200));
        esp_restart();
      }
    }
  }
}

void setup()
{
  Serial.begin(115200);
  delay(50);
  Serial.printf("\n== TinkrNest Smart Switch v%s (ESP32 DevKit) ==\n",
                BLYNK_FIRMWARE_VERSION);

  gState.lastReset = esp_reset_reason();
  Serial.printf("[Boot] reset reason = %d\n", (int)gState.lastReset);

  {
    const esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms = cfg::WDT_TIMEOUT_S * 1000U,
        .idle_core_mask = 0,
        .trigger_panic = true};
    esp_task_wdt_init(&wdt_cfg);
  }

  pinMode(cfg::PIN_LED, OUTPUT);
  pinMode(cfg::PIN_BTN, INPUT_PULLUP);

  gStateMtx = xSemaphoreCreateMutex();
  gNvsMtx = xSemaphoreCreateMutex();
  gScanMtx = xSemaphoreCreateBinary();
  xSemaphoreGive(gScanMtx);

  gRelayQ = xQueueCreate(32, sizeof(RelayCmd));
  gBleWorkQ = xQueueCreate(16, sizeof(BleWork));
  gScanResultQ = xQueueCreate(1, sizeof(ScanResult));
  gSysQ = xQueueCreate(16, sizeof(SysEvent));
  gWifiQ = xQueueCreate(16, sizeof(WifiEvent));

  nvs::begin();
  nvs::loadCreds();
  nvs::loadSettings();
  relayHw::initPins(gState.relays, gState.persistEnabled);

  irmgr::begin();
  dhtmgr::begin();

  // BLE always on — provisioning + local control without WiFi.
  blemgr::start();

  if (gCreds.valid)
  {
    Serial.println("[Boot] credentials found — starting WiFi/Blynk");
    wifimgr::begin();
    blynkmgr::configure();
    otamgr::begin();
  }
  else
  {
    Serial.println("[Boot] no credentials — BLE setup mode (fast LED blink)");
    Serial.println("[Boot] Use the TinkrNest app to scan and configure WiFi + Blynk");
  }

  xTaskCreatePinnedToCore(wifiTask, "wifi", 6144, NULL, 5, &hWifi, 0);
  xTaskCreatePinnedToCore(blynkTask, "blynk", 8192, NULL, 4, &hBlynk, 0);
  xTaskCreatePinnedToCore(bleTask, "ble", 8192, NULL, 4, &hBle, 0);
  xTaskCreatePinnedToCore(sysTask, "sys", 4096, NULL, 3, &hSys, 0);

  xTaskCreatePinnedToCore(relayTask, "relay", 4096, NULL, 6, &hRelay, 1);
  xTaskCreatePinnedToCore(irTask, "ir", 4096, NULL, 6, &hIR, 1);
  xTaskCreatePinnedToCore(dhtTask, "dht", 3072, NULL, 3, &hDHT, 1);
  xTaskCreatePinnedToCore(ledTask, "led", 2560, NULL, 4, &hLed, 1);

  Serial.println("[Boot] all tasks online — industrial 24/7 mode");
}

void loop()
{
  vTaskDelay(pdMS_TO_TICKS(1000));
}
