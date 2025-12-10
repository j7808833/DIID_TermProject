#include <ArduinoBLE.h>
#include <LSM6DS3.h>
#include <Wire.h>

// --- Configuration ---
#define IMU_RATE 50 // Hz (Send rate)
#define LED_PIN 13 // Built-in LED

// Device & Service UUIDs
const char* DEVICE_NAME = "SmartRacket";
const char* SERVICE_UUID = "0769bb8e-b496-4fdd-b53b-87462ff423d0";
const char* CHAR_IMU_UUID = "8ee82f5b-76c7-4170-8f49-fff786257090";
const char* CHAR_TIME_UUID = "8ee82f5b-76c7-4170-8f49-fff786257091";

// HW Sensors
LSM6DS3 myIMU(I2C_MODE, 0x6A);

// BLE
BLEService racketService(SERVICE_UUID);
BLECharacteristic imuChar(CHAR_IMU_UUID, BLERead | BLENotify, 34); // 34 bytes
BLECharacteristic timeChar(CHAR_TIME_UUID, BLEWrite, 4);      // 4 bytes (timestamp)

// State
struct DataPacket {
  uint32_t timestamp;  // 0-3
  uint16_t ms;         // 4-5
  float ax, ay, az;    // 6-17
  float gx, gy, gz;    // 18-29
  uint16_t voltage;    // 30-31
  uint16_t checksum;   // 32-33
} __attribute__((packed));

DataPacket packet;

// Time Sync
unsigned long offsetUnixTime = 0; // The synced unix timestamp (at boot/sync)
unsigned long millisAtSync = 0;   // The millis() when sync happened

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  
  // Init Voltage Read Pin
  pinMode(P0_14, OUTPUT);
  digitalWrite(P0_14, HIGH); // Disable by default
  
  // 1. Init IMU
  if (myIMU.begin() != 0) {
    Serial.println("IMU Error");
    while(1) { blink(100); }
  }
  
  // 2. Init BLE
  if (!BLE.begin()) {
    Serial.println("BLE Error");
    while(1) { blink(500); }
  }

  BLE.setLocalName(DEVICE_NAME);
  BLE.setAdvertisedService(racketService);
  
  racketService.addCharacteristic(imuChar);
  racketService.addCharacteristic(timeChar);
  BLE.addService(racketService);

  // Event Handlers
  timeChar.setEventHandler(BLEWritten, onTimeWritten);

  BLE.advertise();
  Serial.println("Bluetooth Device Active, waiting for connections...");
}

void loop() {
  BLEDevice central = BLE.central();

  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());
    digitalWrite(LED_PIN, LOW); // LED ON (Inverted on XIAO usually? No, HIGH is usually ON or OFF depending on board. Let's assume LOW is ON for nRF52)

    unsigned long lastSend = 0;
    const unsigned long interval = 1000 / IMU_RATE;

    while (central.connected()) {
      unsigned long now = millis();
      if (now - lastSend >= interval) {
        lastSend = now;
        readAndSendSensor();
      }
      
      // Need to poll for BLE events (like Write)
      // ArduinoBLE handles this in background usually, but check just in case
      // BLE.poll(); // usually not needed for nRF52 mbed
    }

    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
    digitalWrite(LED_PIN, HIGH); // LED OFF
  }
}

void readAndSendSensor() {
  // 1. Time Calculation
  unsigned long currentMillis = millis();
  unsigned long elapsedSinceSync = currentMillis - millisAtSync;
  
  packet.timestamp = offsetUnixTime + (elapsedSinceSync / 1000);
  packet.ms = elapsedSinceSync % 1000;
  
  // 2. Read IMU
  packet.ax = myIMU.readFloatAccelX();
  packet.ay = myIMU.readFloatAccelY();
  packet.az = myIMU.readFloatAccelZ();
  
  packet.gx = myIMU.readFloatGyroX();
  packet.gy = myIMU.readFloatGyroY();
  packet.gz = myIMU.readFloatGyroZ();
  
  // 3. Read Voltage
  // High impedance source (1M+510k) requires longer acquisition time.
  // We use dummy read + averaging to help cap settle.
  
  digitalWrite(P0_14, LOW); // Enable
  delayMicroseconds(50);
  
  analogRead(P0_31); // Dummy read to switch mux and charge cap
  delayMicroseconds(10);
  
  uint32_t rawSum = 0;
  int samples = 5;
  for(int i=0; i<samples; i++) {
    rawSum += analogRead(P0_31);
    delayMicroseconds(10);
  }
  
  digitalWrite(P0_14, HIGH); // Disable
  
  float raw = rawSum / (float)samples;
  
  // Calc: V = Raw * (3.6 / 1023.0) * (1510.0 / 510.0)
  // Theoretical Factor = ~10.42
  
  float v = raw * (3600.0f / 1023.0f) * (1510.0f / 510.0f);

  // Calibration:
  // User measured 3.53V when App showed 3.79V.
  // Ratio = 3.53 / 3.79 = 0.9314
  // We apply this correction factor.
  v *= 0.9314f;

  packet.voltage = (uint16_t)v;

  // 4. Checksum (XOR)
  // Cast struct to byte array
  uint8_t* ptr = (uint8_t*)&packet;
  uint16_t chk = 0;
  for(int i=0; i<32; i++) { // First 32 bytes
     chk ^= ptr[i];
  }
  packet.checksum = chk;

  // 5. Send
  imuChar.writeValue((uint8_t*)&packet, sizeof(packet));
}

void onTimeWritten(BLEDevice central, BLECharacteristic characteristic) {
  // User sent 4 bytes of Unix Timestamp
  if (characteristic.valueLength() == 4) {
     const uint8_t* data = characteristic.value();
     uint32_t ts = 0;
     // Little Endian
     ts |= data[0];
     ts |= data[1] << 8;
     ts |= data[2] << 16;
     ts |= data[3] << 24;
     
     offsetUnixTime = ts;
     millisAtSync = millis();
     
     Serial.print("Time Synced: ");
     Serial.println(ts);
  }
}

void blink(int delayMs) {
  digitalWrite(LED_PIN, HIGH);
  delay(delayMs);
  digitalWrite(LED_PIN, LOW);
  delay(delayMs);
}
