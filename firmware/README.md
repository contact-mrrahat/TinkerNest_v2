# TinkrNest ESP32 Firmware

Flash `tinkrnest_smart_switch/tinkrnest_smart_switch.ino` to an **ESP32 DevKit (WROOM-32)**.

## Required Arduino libraries

- Blynk (BlynkSimpleEsp32)
- NimBLE-Arduino
- ArduinoJson (v7+)
- IRremoteESP8266
- DHT sensor library

## Button (GPIO 0 / BOOT)

| Action | Result |
|--------|--------|
| Short press | Reboot |
| Hold 3 s | Restart BLE advertising |
| Hold 10 s | Factory reset → reboot → BLE setup mode |

After factory reset the LED blinks **fast**. Use the TinkrNest Flutter app → **Find Device** → connect → WiFi + Blynk wizard.

## BLE protocol

Matches `lib/core/constants/ble_constants.dart` in the Flutter app.

- **Write** commands to `6e400002-…` (text or JSON provisioning)
- **Subscribe** to `6e400003-…` for notifications

Commands: `STATUS`, `WIFI_SCAN`, `R1:0`…`R4:1`, `ALL:0/1`, `PERSIST:0/1`, `REBOOT`

Provisioning JSON: `{"ssid":"…","pass":"…","auth":"Blynk token","tplId":"…","tplName":"…"}`

## Version

Current: **7.0.4-industrial**

**Important:** v7.0.4 saves credentials without WiFi test during BLE (fixes provisioning disconnect). Flash this before using the app wizard.
