/*****************************************************************************/
//  SmartRacket IMU BLE 傳輸系統
//  Hardware:      Seeed XIAO nRF52840 Sense + LSM6DS3 6軸IMU感測器
//	Arduino IDE:   Arduino-1.8.19+
//	Author:	       DIID Term Project Team
//	Date: 	       2024
//	Version:       v2.0 (BLE版本)
//
//  Description:   智慧羽毛球拍IMU感測器系統
//                 - 讀取LSM6DS3加速度計和陀螺儀資料
//                 - 透過Bluetooth Low Energy (BLE) 即時傳輸資料
//                 - 包含IMU校正、電壓監控、充電模式控制
//                 - 支援50Hz高頻率資料傳輸
//
//  BLE服務架構:
//  - 服務UUID: 0769bb8e-b496-4fdd-b53b-87462ff423d0
//  - 特徵UUID: 8ee82f5b-76c7-4170-8f49-fff786257090
//  - 資料格式: 30 bytes (時間戳4 + 加速度12 + 陀螺儀12 + 電壓2)
//
//  硬體連接:
//  - LSM6DS3: I2C (SDA, SCL) 地址 0x6A
//  - 電壓監控: P0.31 (AIN7 / PIN_VBAT) - XIAO nRF52840 Sense 內建電池電壓分壓電路
//  - 電壓啟用: P0.14 (VBAT_ENABLE) - 設為 LOW 啟用分壓電路，HIGH 關閉省電
//  - 充電控制: P0_13 數位輸出
//  - 電池: 501230, 3.7V, 150mAh
//
//  Note:          LSM6DS3函式庫相容性修正 (LSM6DS3.cpp line 108):
//                 #if !defined(ARDUINO_ARCH_MBED)
//                     SPI.setBitOrder(MSBFIRST);
//                     SPI.setDataMode(SPI_MODE3);
//                     SPI.setClockDivider(SPI_CLOCK_DIV16);
//                 #endif
//
/*******************************************************************************/

// ============================================================================
// 函式庫引入
// ============================================================================
#include "LSM6DS3.h"      // LSM6DS3 6軸IMU感測器函式庫
#include "Wire.h"         // I2C通訊函式庫
#include "ArduinoBLE.h"   // Bluetooth Low Energy函式庫

// ============================================================================
// 硬體物件初始化
// ============================================================================
// 建立LSM6DS3感測器實例，使用I2C通訊模式，設備地址0x6A
LSM6DS3 myIMU(I2C_MODE, 0x6A);

// ============================================================================
// BLE服務與特徵定義
// ============================================================================
// 自訂IMU資料服務，使用UUID: 0769bb8e-b496-4fdd-b53b-87462ff423d0
BLEService imuService("0769bb8e-b496-4fdd-b53b-87462ff423d0");

// IMU資料特徵，支援讀取和通知功能，資料長度30 bytes
// UUID: 8ee82f5b-76c7-4170-8f49-fff786257090
BLECharacteristic imuDataChar("8ee82f5b-76c7-4170-8f49-fff786257090", 
                              BLERead | BLENotify, 30);

// ============================================================================
// IMU校正相關變數
// ============================================================================
bool imuReady = false;           // IMU感測器是否準備就緒
bool calibrationDone = false;    // 是否已完成校正

// 加速度計偏移量 (用於校正靜止狀態下的零點漂移)
float offsetAX = 0.0f, offsetAY = 0.0f, offsetAZ = 0.0f;

// 陀螺儀偏移量 (用於校正靜止狀態下的零點漂移)
float offsetGX = 0.0f, offsetGY = 0.0f, offsetGZ = 0.0f;

// ============================================================================
// 電源管理相關變數
// ============================================================================
// 電池規格：501230, 3.7V, 150mAh
// 正常工作電壓範圍：3.2V (低電量警告) ~ 4.2V (滿電)
// 充電模式切換點：3.5V (低於3.5V使用高電流充電，高於3.5V使用低電流充電)
unsigned long lastVoltageReadTime = -60000;  // 上次電壓讀取時間 (初始值設為1分鐘前)
int16_t voltageRaw = 0;                      // 原始電壓讀取值 (0-1023, ADC 10-bit)
bool isHighCurrentCharging = false;          // 是否為高電流充電模式

#define LEDR        (11u)
#define LEDB        (12u)
#define LEDG        (13u)

// ============================================================================
// 系統初始化函數
// ============================================================================
void setup() {
    // ------------------------------------------------------------------------
    // 串列通訊初始化
    // ------------------------------------------------------------------------
    Serial.begin(9600);        // 設定串列通訊速率為9600 bps
    //while (!Serial);           // 等待串列埠準備就緒 (USB連接)
    
    // ------------------------------------------------------------------------
    // I2C通訊初始化
    // ------------------------------------------------------------------------
    Wire.begin();              // 初始化I2C通訊
    Wire.setClock(400000);     // 設定I2C時鐘頻率為400kHz (高速模式)
    
    // ------------------------------------------------------------------------
    // IMU感測器初始化
    // ------------------------------------------------------------------------
    Serial.println("Initializing LSM6DS3 IMU...");
    if (myIMU.begin() != 0) {
        // IMU初始化失敗
        imuReady = false;
        Serial.println("Device error");
        while(1);              // 停止執行，等待重啟
    } else {
        // IMU初始化成功
        imuReady = true;
        Serial.println("timestamp,aX,aY,aZ,gX,gY,gZ");  // 輸出CSV標題
    }

    // ------------------------------------------------------------------------
    // LED 初始化
    // ------------------------------------------------------------------------
    pinMode(LEDR, OUTPUT);
    pinMode(LEDB, OUTPUT);
    pinMode(LEDG, OUTPUT);
    
    // 設定電池電壓監控腳位
    // P0.14 (VBAT_ENABLE): 設為 LOW 啟用內建分壓電路，HIGH 關閉省電
    pinMode(P0_14, OUTPUT);
    digitalWrite(P0_14, HIGH);  // 初始狀態：關閉分壓電路（省電）
    
    // ------------------------------------------------------------------------
    // BLE藍牙初始化
    // ------------------------------------------------------------------------
    if (!BLE.begin()) {
        Serial.println("BLE initialization failed!");
        while(1);              // 停止執行，等待重啟
    }
    
    // 設定BLE服務和特徵
    imuService.addCharacteristic(imuDataChar);  // 將特徵加入服務
    BLE.addService(imuService);                 // 將服務加入BLE
    imuDataChar.setValue((uint8_t*)"", 0);      // 設定特徵初始值為空
    
    // 設定BLE設備名稱和廣播服務
    BLE.setLocalName("SmartRacket");            // 設定設備名稱為SmartRacket
    BLE.setAdvertisedService(imuService);       // 設定廣播的服務
    
    // 設定BLE參數以提高連接穩定性
    BLE.setConnectable(true);                   // 允許設備被連接
    BLE.setAdvertisingInterval(100);            // 設定廣播間隔為100ms
    
    // 開始BLE廣播
    BLE.advertise();
    
    // 輸出初始化完成訊息
    Serial.println("BLE advertising started...");
    Serial.println("Device name: SmartRacket");
    Serial.println("Waiting for connection...");
}

// ============================================================================
// 主程式迴圈
// ============================================================================
void loop() {
    // ------------------------------------------------------------------------
    // 點亮藍色代表程序啟動
    // ------------------------------------------------------------------------
    digitalWrite(LEDB, HIGH);
    // ------------------------------------------------------------------------
    // 電源管理檢查
    // ------------------------------------------------------------------------
    //checkVoltageAndSleep();    // 檢查電池電壓，必要時進入省電模式
    
    // ------------------------------------------------------------------------
    // BLE事件處理
    // ------------------------------------------------------------------------
    BLE.poll();                // 必須持續呼叫來處理BLE事件 (連接、斷線、資料傳輸等)
    
    // ------------------------------------------------------------------------
    // 檢查BLE連接狀態
    // ------------------------------------------------------------------------
    BLEDevice central = BLE.central();  // 取得連接的中央設備 (手機/電腦)
    
    // 靜態變數：用於控制資料輸出頻率（無論是否連接）
    static unsigned long lastDataOutputTime = 0;
    const unsigned long dataOutputInterval = 20;  // 20ms = 50Hz
    
    // 檢查是否到達資料輸出時間（無論是否連接BLE）
    unsigned long now = millis();
    if ((long)(now - lastDataOutputTime) >= 0) {
        // --------------------------------------------------------------------
        // 讀取IMU感測器資料（無論是否連接BLE）
        // --------------------------------------------------------------------
        uint32_t timestamp = millis();  // 時間戳記
        
        // 初始化感測器資料變數
        float aX = 0, aY = 0, aZ = 0;  // 加速度 (X, Y, Z軸)
        float gX = 0, gY = 0, gZ = 0;  // 角速度 (X, Y, Z軸)
        
        if (imuReady) {
            // 讀取原始感測器資料並減去校正偏移量
            aX = myIMU.readFloatAccelX() - offsetAX;  // 加速度X軸
            aY = myIMU.readFloatAccelY() - offsetAY;  // 加速度Y軸
            aZ = myIMU.readFloatAccelZ() - offsetAZ;  // 加速度Z軸
            gX = myIMU.readFloatGyroX() - offsetGX;   // 角速度X軸
            gY = myIMU.readFloatGyroY() - offsetGY;   // 角速度Y軸
            gZ = myIMU.readFloatGyroZ() - offsetGZ;   // 角速度Z軸
        }
        
        // --------------------------------------------------------------------
        // 讀取電池電壓（使用 XIAO nRF52840 Sense 內建分壓電路）
        // --------------------------------------------------------------------
        // 1. 啟用分壓電路（P0.14 = LOW）
        digitalWrite(P0_14, LOW);
        delayMicroseconds(500);  // 等待電壓穩定（約 500µs）
        
        // 2. 讀取 ADC 值（P0.31 / AIN7 / PIN_VBAT）
        // 注意：需要確認 A0 是否對應 P0.31
        // 如果 A0 不對應，可能需要使用其他腳位編號或直接配置 SAADC
        voltageRaw = analogRead(A0);
        
        // 3. 關閉分壓電路以省電（P0.14 = HIGH）
        digitalWrite(P0_14, HIGH);
        
        // 確保 voltageRaw 在有效範圍內
        // 注意：Arduino analogRead() 通常返回 10-bit (0-1023)
        // 但 nRF52840 SAADC 實際是 12-bit (0-4095)
        // 需要將 10-bit 值轉換為 12-bit 等效值
        if (voltageRaw < 0) voltageRaw = 0;
        
        // 轉換 10-bit 到 12-bit：12bit_value = 10bit_value * 4
        // 例如：400 (10-bit) → 1600 (12-bit)
        if (voltageRaw <= 1023) {
            voltageRaw = voltageRaw * 4;  // 10-bit 轉 12-bit
        }
        
        // 記錄轉換後的原始值（用於除錯）
        // Serial.print(" [ADC原始="); Serial.print(voltageRaw/4); Serial.print(", 轉換後="); Serial.print(voltageRaw); Serial.print("]");
        
        // --------------------------------------------------------------------
        // 串列埠輸出（簡化：只輸出六軸資料和電壓）
        // --------------------------------------------------------------------
        // 計算實際電池電壓
        float calibrationConstant = 10.8f;  // 可以根據實際測量值調整
        float voltage = (float)voltageRaw * calibrationConstant / 4096.0f;
        
        // 輸出格式：aX,aY,aZ,gX,gY,gZ,voltage
        Serial.print(aX, 8);  // 加速度 X
        Serial.print(',');
        Serial.print(aY, 8);  // 加速度 Y
        Serial.print(',');
        Serial.print(aZ, 8);  // 加速度 Z
        Serial.print(',');
        Serial.print(gX, 8);  // 角速度 X
        Serial.print(',');
        Serial.print(gY, 8);  // 角速度 Y
        Serial.print(',');
        Serial.print(gZ, 8);  // 角速度 Z
        Serial.print(',');
        Serial.println(voltage, 2);  // 電壓（2位小數）
        
        // 更新輸出時間
        lastDataOutputTime += dataOutputInterval;
    }
    
    if (central && central.connected()) {
        // ====================================================================
        // BLE已連接 - 開始IMU資料傳輸
        // ====================================================================
        
        // 首次連接時進行IMU校正
        if (!calibrationDone) {
            calibrateIMUOffsets();  // 校正IMU偏移量
            calibrationDone = true;
        }
        
        static bool firstConnection = true;
        if (firstConnection) {
            Serial.println("Connected to central");
            firstConnection = false;
        }
        
        // 設定資料傳輸參數
        const unsigned long interval = 20;  // 傳輸間隔20ms = 50Hz
        static unsigned long lastSendTime = 0;
        
        // 檢查是否到達BLE傳輸時間
        if ((long)(now - lastSendTime) >= 0) {
            // --------------------------------------------------------------------
            // 資料封包化 (30 bytes二進位格式)
            // --------------------------------------------------------------------
            uint8_t buffer[30];  // 資料緩衝區
            
            // 重新讀取最新資料（確保資料是最新的）
            uint32_t timestamp = millis();
            float aX = 0, aY = 0, aZ = 0;
            float gX = 0, gY = 0, gZ = 0;
            
            if (imuReady) {
                aX = myIMU.readFloatAccelX() - offsetAX;
                aY = myIMU.readFloatAccelY() - offsetAY;
                aZ = myIMU.readFloatAccelZ() - offsetAZ;
                gX = myIMU.readFloatGyroX() - offsetGX;
                gY = myIMU.readFloatGyroY() - offsetGY;
                gZ = myIMU.readFloatGyroZ() - offsetGZ;
            }
            
            // 啟用分壓電路
            digitalWrite(P0_14, LOW);
            delayMicroseconds(500);
            
            // 讀取 ADC 值
            voltageRaw = analogRead(A0);
            
            // 關閉分壓電路
            digitalWrite(P0_14, HIGH);
            
            if (voltageRaw < 0) voltageRaw = 0;
            
            // 轉換 10-bit 到 12-bit：12bit_value = 10bit_value * 4
            if (voltageRaw <= 1023) {
                voltageRaw = voltageRaw * 4;  // 10-bit 轉 12-bit
            }
            
            // 檢測 USB 供電模式
            // 在 USB 模式下，電池可能被斷開，電壓讀值會異常低
            // 如果電壓讀值 < 200（約 < 1.3V），標記為 USB 供電模式
            // 注意：這個值可能需要根據實際硬體調整
            bool isUSBPowered = (voltageRaw < 200);
            
            // 在 USB 模式下，可以選擇：
            // 1. 發送 0 或特殊值表示 USB 供電
            // 2. 發送實際讀值（讓 Android 端判斷）
            // 這裡選擇發送實際讀值，讓 Android 端判斷
            // 如果需要，可以設置特殊標記值，例如：if (isUSBPowered) voltageRaw = 0xFFFF;
            
            // 封包結構: [時間戳4] + [加速度12] + [陀螺儀12] + [電壓2] = 30 bytes
            memcpy(buffer, &timestamp, 4);        // 0-3: 時間戳 (4 bytes)
            memcpy(buffer + 4, &aX, 4);           // 4-7: 加速度X (4 bytes)
            memcpy(buffer + 8, &aY, 4);           // 8-11: 加速度Y (4 bytes)
            memcpy(buffer + 12, &aZ, 4);          // 12-15: 加速度Z (4 bytes)
            memcpy(buffer + 16, &gX, 4);          // 16-19: 角速度X (4 bytes)
            memcpy(buffer + 20, &gY, 4);          // 20-23: 角速度Y (4 bytes)
            memcpy(buffer + 24, &gZ, 4);          // 24-27: 角速度Z (4 bytes)
            
            // 將 voltageRaw 轉換為 uint16_t 並以 Little-Endian 格式發送
            uint16_t voltageRawUint = (uint16_t)voltageRaw;
            memcpy(buffer + 28, &voltageRawUint, 2);  // 28-29: 電壓 (2 bytes, Little-Endian)
            
            // --------------------------------------------------------------------
            // 透過BLE傳送資料
            // --------------------------------------------------------------------
            bool success = imuDataChar.writeValue(buffer, 30);  // 發送30 bytes資料
            if (!success) {
                Serial.println("BLE發送失敗!");
            }
            
            // 更新傳輸時間
            lastSendTime += interval;
        }
        
    } else {
        // ====================================================================
        // 沒有BLE連接 - 省電模式（但仍會輸出串列資料）
        // ====================================================================
        static bool firstDisconnection = true;
        if (firstDisconnection) {
            Serial.println("Disconnected from central");
            firstDisconnection = false;
        }
        delay(10);  // 減少延遲，讓串列輸出更順暢
    }
}

// ============================================================================
// IMU感測器校正函數
// ============================================================================
void calibrateIMUOffsets() {
    Serial.println("Starting IMU calibration...");
    
    // 初始化累加變數
    float sumAX = 0, sumAY = 0, sumAZ = 0;  // 加速度累加
    float sumGX = 0, sumGY = 0, sumGZ = 0;  // 陀螺儀累加
    
    // 進行100次採樣來計算偏移量
    for (int i = 0; i < 100; i++) {
        // 累加原始感測器讀值
        sumAX += myIMU.readFloatAccelX();  // 加速度X軸
        sumAY += myIMU.readFloatAccelY();  // 加速度Y軸
        sumAZ += myIMU.readFloatAccelZ();  // 加速度Z軸
        sumGX += myIMU.readFloatGyroX();   // 陀螺儀X軸
        sumGY += myIMU.readFloatGyroY();   // 陀螺儀Y軸
        sumGZ += myIMU.readFloatGyroZ();   // 陀螺儀Z軸
        
        delay(10);  // 10ms間隔採樣
    }
    
    // 計算平均偏移量
    offsetAX = sumAX / 100.0;                    // 加速度X軸偏移
    offsetAY = sumAY / 100.0;                    // 加速度Y軸偏移
    offsetAZ = (sumAZ / 100.0) - 1.0;           // 加速度Z軸偏移 (減去重力加速度1g)
    offsetGX = sumGX / 100.0;                    // 陀螺儀X軸偏移
    offsetGY = sumGY / 100.0;                    // 陀螺儀Y軸偏移
    offsetGZ = sumGZ / 100.0;                    // 陀螺儀Z軸偏移
    
    Serial.println("IMU calibration completed");
}

// ============================================================================
// 電壓監控與省電管理函數
// ============================================================================
void checkVoltageAndSleep() {
    unsigned long now = millis();

    // 每60秒檢查一次電壓 (避免頻繁讀取)
    if (now - lastVoltageReadTime >= 60000) {
        // 啟用分壓電路（P0.14 = LOW）
        digitalWrite(P0_14, LOW);
        delayMicroseconds(500);  // 等待電壓穩定
        
        // 讀取 ADC 值（P0.31 / AIN7 / PIN_VBAT）
        voltageRaw = analogRead(A0);
        
        // 關閉分壓電路以省電（P0.14 = HIGH）
        digitalWrite(P0_14, HIGH);
        
        lastVoltageReadTime = now;

        // 轉換 10-bit 到 12-bit（如果需要的話）
        if (voltageRaw <= 1023) {
            voltageRaw = voltageRaw * 4;  // 10-bit 轉 12-bit
        }

        // 將數位值轉換為實際電池電壓
        // 使用 nRF52840 SAADC 公式：
        // V_BAT = RESULT × K / 4096
        // 其中：
        // - RESULT: 12-bit ADC 值（0-4095）
        // - K: 校準常數（理論值 10.8，但可能需要根據實際硬體調整）
        // 建議：用萬用表測量實際電池電壓，然後調整 K 值以匹配
        float calibrationConstant = 10.8f;  // 可以根據實際測量值調整
        float voltage = (float)voltageRaw * calibrationConstant / 4096.0f;

        // 根據電壓調整充電模式
        updateChargingMode(voltage);

        // 檢查是否電壓過低 (低於3.2V，電池低電量警告)
        if (voltage < 3.2) {
            Serial.println("Voltage too low! Entering sleep mode.");
            
            // 嘗試通知手機低電量警告
            if (BLE.connected()) {
                const char* warning = "LowPowerSleep";  // 低電量警告訊息
                uint8_t buffer[30] = {0};               // 初始化緩衝區
                memcpy(buffer, warning, strlen(warning)); // 複製警告訊息
                
                // 使用最後2 bytes作為訊息類型代碼
                uint16_t type = 0xABCD;  // 低電量警告類型
                memcpy(buffer + 28, &type, 2);
                
                // 發送警告訊息
                imuDataChar.writeValue(buffer, 30);

                delay(50);
                BLE.disconnect();       // 強制斷線，確保手機收到警告
                delay(300);
                BLE.advertise();        // 重新開始廣播
            }

            // 進入省電模式 - 等待重新連接
            while (!BLE.central().connected()) {
                delay(1000);   // 每秒檢查一次連接狀態
            }

            Serial.println("BLE reconnected. Wake up.");
            BLE.advertise();  // 重新開始廣播
        }
    }
}

// ============================================================================
// 充電模式控制函數
// ============================================================================
void updateChargingMode(float batteryVoltage) {
    // 電池規格：501230, 3.7V, 150mAh
    // 當電池電壓低於3.5V時，切換到高電流充電模式（快速充電）
    // 當電池電壓高於3.5V時，切換回低電流充電模式（保護電池）
    if (batteryVoltage < 3.5) {
        if (!isHighCurrentCharging) {
            pinMode(P0_13, OUTPUT);           // 設定P0_13為輸出模式
            digitalWrite(P0_13, LOW);         // 輸出LOW信號，啟用高電流充電
            isHighCurrentCharging = true;     // 更新充電模式狀態
            Serial.println("Switched to HIGH current charging.");
        }
    } else {
        // 當電池電壓高於3.5V時，切換回低電流充電模式（保護電池）
        if (isHighCurrentCharging) {
            pinMode(P0_13, OUTPUT);           // 設定P0_13為輸出模式
            digitalWrite(P0_13, HIGH);        // 輸出HIGH信號，啟用低電流充電
            isHighCurrentCharging = false;    // 更新充電模式狀態
            Serial.println("Switched to LOW current charging.");
        }
    }
}
