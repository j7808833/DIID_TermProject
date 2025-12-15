#include <ArduinoBLE.h> // 引入 BLE (低功耗藍牙) 函式庫
#include <LSM6DS3.h>    // 引入 IMU 函式庫
#include <Wire.h>       // 引入 Wire 函式庫

// --- 設定區 ---
#define IMU_RATE 50 

// --- LED 腳位設定 (根據最終測試結果強制定義) ---
// 測試結果：12=紅, 13=綠, 14=藍
const int PIN_LED_RED   = 12;
const int PIN_LED_GREEN = 13;
const int PIN_LED_BLUE  = 14; 

// --- 藍牙 UUID 設定 ---
const char* DEVICE_NAME = "SmartRacket"; 
const char* SERVICE_UUID = "0769bb8e-b496-4fdd-b53b-87462ff423d0"; 
const char* CHAR_IMU_UUID = "8ee82f5b-76c7-4170-8f49-fff786257090"; 
const char* CHAR_TIME_UUID = "8ee82f5b-76c7-4170-8f49-fff786257091"; 

// --- 硬體與藍牙物件 ---
LSM6DS3 myIMU(I2C_MODE, 0x6A);
BLEService racketService(SERVICE_UUID);
BLECharacteristic imuChar(CHAR_IMU_UUID, BLERead | BLENotify, 34); 
BLECharacteristic timeChar(CHAR_TIME_UUID, BLEWrite, 4);      

// --- 資料結構 ---
struct DataPacket {
  uint32_t timestamp;  
  uint16_t ms;         
  float ax, ay, az;    
  float gx, gy, gz;    
  uint16_t voltage;    
  uint16_t checksum;   
} __attribute__((packed));

DataPacket packet;

// --- 時間同步變數 ---
// --- 全域變數 ---
uint16_t g_lastVoltage = 0; // 儲存最後一次讀到的電壓
unsigned long offsetUnixTime = 0; // 手機傳來的基準時間 (秒)
unsigned long millisAtSync = 0;   // 收到基準時間當下的 Arduino 系統時間 (毫秒)

void setup() {
  Serial.begin(115200); 
  
  // --- LED 初始化 ---
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_BLUE, OUTPUT);
  
  // 預設全滅 (Active LOW: HIGH=滅)
  digitalWrite(PIN_LED_RED, HIGH);
  digitalWrite(PIN_LED_GREEN, HIGH);
  digitalWrite(PIN_LED_BLUE, HIGH);

  // --- 充電功能設定 (針對 Seeed XIAO nRF52840) ---
  pinMode(P0_13, OUTPUT); digitalWrite(P0_13, LOW); // High Charge Current
  pinMode(P0_17, INPUT_PULLUP); // Charge Status

  // --- 電壓讀取腳位設定 ---
  pinMode(P0_14, INPUT);
  
  // 1. 初始化 IMU
  if (myIMU.begin() != 0) {
    Serial.println("IMU Error");
    while(1) { 
      digitalWrite(PIN_LED_RED, LOW); delay(100); 
      digitalWrite(PIN_LED_RED, HIGH); delay(100); 
    }
  }
  
  // 2. 初始化藍牙模組
  if (!BLE.begin()) {
    Serial.println("BLE Error");
    while(1) { 
        digitalWrite(PIN_LED_RED, LOW); delay(500); 
        digitalWrite(PIN_LED_RED, HIGH); delay(500); 
    } 
  }

  // 設定藍牙參數
  BLE.setLocalName(DEVICE_NAME); 
  BLE.setAdvertisedService(racketService); 
  racketService.addCharacteristic(imuChar);
  racketService.addCharacteristic(timeChar);
  BLE.addService(racketService);
  timeChar.setEventHandler(BLEWritten, onTimeWritten);

  BLE.advertise();
  Serial.println("Bluetooth Device Active, waiting for connections...");
}

// --- LED 狀態更新函式 ---
void updateLedState(bool connected) {
  // 1. 檢查是否在充電 (P0.17 LOW = Charging)
  bool isCharging = (digitalRead(P0_17) == LOW);

  if (isCharging) {
    // --- 充電模式：綠燈呼吸燈 ---
    // 關閉其他燈
    digitalWrite(PIN_LED_RED, HIGH);
    digitalWrite(PIN_LED_BLUE, HIGH);
    
    // 計算呼吸亮度 (0~255)
    // 使用 millis 產生三角波：週期約 2.5 秒
    int val = (millis() / 5) % 512; 
    if (val > 255) val = 511 - val;
    
    // 因為 LED 是 Active LOW，所以 PWM 值要反過來 (255-val)
    // 但 analogWrite 在 nRF52 上對應的是 Duty Cycle，通常也要看實作
    // 先假設 0=Full OFF, 255=Full ON for analogWrite? 
    // 不，digitalWrite LOW 是亮。analogWrite(pin, 0) 通常是 0% Duty Cycle (LOW if non-inverted?)
    // 讓我們用簡單的實驗: analogWrite(pin, 255) 是全亮還是全滅?
    // 為了保險，我們假設 analogWrite(pin, val) 其中 val=0 是 LOW (全亮), 255 是 HIGH (全滅)
    
    analogWrite(PIN_LED_GREEN, 255 - val); 
    return;
  } 
  
  // 如果沒充電，就要看有沒有連線
  if (!connected) {
    // --- 待機模式：藍燈慢閃 ---
    // 清除 PWM 狀態 (切回 digital 模式)
    digitalWrite(PIN_LED_GREEN, HIGH);
    digitalWrite(PIN_LED_RED, HIGH);

    static unsigned long lastBlink = 0;
    static bool ledState = HIGH; 
    if (millis() - lastBlink >= 500) { 
      lastBlink = millis();
      ledState = !ledState; 
      digitalWrite(PIN_LED_BLUE, ledState);   
    }
  } else {
    // --- 連線模式：顯示電量 (恆亮) ---
    // 清除 PWM 狀態 / 關掉不相關的燈
    // 注意：用 analogWrite 之後要用 digitalWrite 蓋過去可能需要小心
    // 這裡我們 explicit 關閉所有燈，再開啟對應的
    
    // 判斷電量顏色
    // > 3.8V : 綠
    // 3.6 - 3.8V : 藍
    // < 3.6V : 紅
    
    // 為避免閃爍，可以加一點點遲滯 (Hysteresis)，但這裡先做簡單版
    
    if (g_lastVoltage > 3800) {
      // 亮綠
      digitalWrite(PIN_LED_RED, HIGH);
      digitalWrite(PIN_LED_BLUE, HIGH);
      digitalWrite(PIN_LED_GREEN, LOW); 
    } else if (g_lastVoltage >= 3600) {
      // 亮藍
      digitalWrite(PIN_LED_RED, HIGH);
      digitalWrite(PIN_LED_GREEN, HIGH);
      digitalWrite(PIN_LED_BLUE, LOW); 
    } else {
      // 亮紅 (如果電壓是0，可能還沒讀到，先預設紅或者藍？先紅吧)
      digitalWrite(PIN_LED_GREEN, HIGH);
      digitalWrite(PIN_LED_BLUE, HIGH);
      digitalWrite(PIN_LED_RED, LOW); 
    }
  }
}

void loop() {
  BLEDevice central = BLE.central();

  // 更新 LED (傳入連線狀態)
  updateLedState((bool)central);

  if (central) {
    static bool connectedLog = false;
    if (!connectedLog) {
       Serial.print("Connected to central: ");
       Serial.println(central.address());
       connectedLog = true;
    }

    unsigned long lastSend = 0; 
    const unsigned long interval = 1000 / IMU_RATE;

    while (central.connected()) {
      // 雖然在 while 裡面，但我們也需要更新充電燈號
      // 這裡每 20ms 跑一次，更新 LED 頻率夠高，會有呼吸效果
      unsigned long now = millis();
      if (now - lastSend >= interval) {
        lastSend = now; 
        readAndSendSensor(); 
        
        // 讀完 Sensor 後 g_lastVoltage 會更新
        // 順便更新 LED
        updateLedState(true);
      }
    }

    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
    connectedLog = false;
    
    // 斷線後，LED 狀態會在下一次 loop() 開頭的 updateLedState(false) 被修正
  }
}

// --- 讀取並傳送感測器資料 ---
void readAndSendSensor() {
  unsigned long currentMillis = millis();
  unsigned long elapsedSinceSync = currentMillis - millisAtSync;
  
  packet.timestamp = offsetUnixTime + (elapsedSinceSync / 1000);
  packet.ms = elapsedSinceSync % 1000;
  
  packet.ax = myIMU.readFloatAccelX();
  packet.ay = myIMU.readFloatAccelY();
  packet.az = myIMU.readFloatAccelZ();
  
  packet.gx = myIMU.readFloatGyroX();
  packet.gy = myIMU.readFloatGyroY();
  packet.gz = myIMU.readFloatGyroZ();
  
  // 讀取電池電壓
  pinMode(P0_14, OUTPUT);
  digitalWrite(P0_14, LOW); 
  delayMicroseconds(50);    
  
  analogRead(P0_31); 
  delayMicroseconds(10);
  
  uint32_t rawSum = 0;
  int samples = 5; 
  for(int i=0; i<samples; i++) {
    rawSum += analogRead(P0_31); 
    delayMicroseconds(10);
  }
  
  digitalWrite(P0_14, HIGH); 
  pinMode(P0_14, INPUT); 
  
  float raw = rawSum / (float)samples; 
  float v = raw * (3600.0f / 1023.0f) * (1510.0f / 510.0f);
  v *= 0.9314f; // 校正係數

  packet.voltage = (uint16_t)v; 
  
  // 更新全域變數，供 LED 判斷使用
  g_lastVoltage = packet.voltage;

  // Checksum
  uint8_t* ptr = (uint8_t*)&packet;
  uint16_t chk = 0;
  for(int i=0; i<32; i++) { 
    chk ^= ptr[i];
  }
  packet.checksum = chk;

  imuChar.writeValue((uint8_t*)&packet, sizeof(packet));
}

// --- 事件：收到時間同步 ---
void onTimeWritten(BLEDevice central, BLECharacteristic characteristic) {
  if (characteristic.valueLength() == 4) {
     const uint8_t* data = characteristic.value();
     uint32_t ts = 0;
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
