/*****************************************************************************/
//  SmartRacket IMU Test
//  Hardware:      Seeed XIAO nRF52840 Sense + LSM6DS3
//	Arduino IDE:   Arduino-1.8.19+
//	Author:	       DIID Term Project Team
//	Date: 	       2024
//	Version:       v1.0
//
//  Description:   Basic IMU sensor test for SmartRacket project
//                 Tests LSM6DS3 accelerometer, gyroscope, and temperature
//
//  Note:          For LSM6DS3 library compatibility with nRF52840,
//                 modify LSM6DS3.cpp line 108 to use conditional compilation:
//                 #if !defined(ARDUINO_ARCH_MBED)
//                     SPI.setBitOrder(MSBFIRST);
//                     SPI.setDataMode(SPI_MODE3);
//                     SPI.setClockDivider(SPI_CLOCK_DIV16);
//                 #endif
//
/*******************************************************************************/

#include "LSM6DS3.h"
#include "Wire.h"
#include "ArduinoBLE.h"

//Create a instance of class LSM6DS3
LSM6DS3 myIMU(I2C_MODE, 0x6A);    //I2C device address 0x6A

// BLE Service & Characteristic
BLEService imuService("0769bb8e-b496-4fdd-b53b-87462ff423d0");  // 自訂服務UUID
BLECharacteristic imuDataChar("8ee82f5b-76c7-4170-8f49-fff786257090", BLERead | BLENotify, 30);  // 30 bytes資料

// 加入UART服務 (Nordic UART Service)
BLEService uartService("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");  // Nordic UART Service
BLECharacteristic uartTxChar("6E400002-B5A3-F393-E0A9-E50E24DCCA9E", BLERead | BLENotify, 20);  // TX
BLECharacteristic uartRxChar("6E400003-B5A3-F393-E0A9-E50E24DCCA9E", BLEWrite | BLEWriteWithoutResponse, 20);  // RX

// IMU校正變數
bool imuReady = false;
bool calibrationDone = false;
float offsetAX = 0.0f, offsetAY = 0.0f, offsetAZ = 0.0f;
float offsetGX = 0.0f, offsetGY = 0.0f, offsetGZ = 0.0f;

// 電壓快取用的全域變數
unsigned long lastVoltageReadTime = -60000;
int16_t voltageRaw = 0;
bool isHighCurrentCharging = false;  // 預設為低電流模式

void setup() {
    // Initialize serial communication
    Serial.begin(9600);
    while (!Serial);
    
    // Initialize I2C communication
    Wire.begin();
    Wire.setClock(400000);  // Set I2C clock to 400kHz for faster communication
    
    // Initialize IMU sensor
    Serial.println("Initializing LSM6DS3 IMU...");
    if (myIMU.begin() != 0) {
        imuReady = false;
        Serial.println("Device error");
        while(1);
    } else {
        imuReady = true;
        Serial.println("timestamp,aX,aY,aZ,gX,gY,gZ");
    }
    
    // Initialize BLE
    if (!BLE.begin()) {
        Serial.println("BLE initialization failed!");
        while(1);
    }
    
    // Setup BLE services and characteristics
    imuService.addCharacteristic(imuDataChar);
    BLE.addService(imuService);
    imuDataChar.setValue((uint8_t*)"", 0);  // 設定初始空值
    
    // 設定UART服務
    uartService.addCharacteristic(uartTxChar);
    uartService.addCharacteristic(uartRxChar);
    BLE.addService(uartService);
    uartTxChar.setValue((uint8_t*)"", 0);
    uartRxChar.setValue((uint8_t*)"", 0);
    
    // Set BLE device name and start advertising
    BLE.setLocalName("SmartRacket");
    BLE.setAdvertisedService(imuService);
    
    // 設定BLE參數以提高穩定性
    BLE.setConnectable(true);
    BLE.setAdvertisingInterval(100);  // 100ms廣播間隔
    
    BLE.advertise();
    
    Serial.println("BLE advertising started...");
    Serial.println("Device name: SmartRacket");
    Serial.println("Waiting for connection...");
}

void loop() {
    checkVoltageAndSleep();
    
    // 必須持續呼叫BLE.poll()來處理BLE事件
    BLE.poll();
    
    BLEDevice central = BLE.central();
    
    if (central && central.connected()) {
        if (!calibrationDone) {
            calibrateIMUOffsets();
            calibrationDone = true;
        }
        
        Serial.println("Connected to central");
        
        // 初始化時間記錄 - 降低頻率避免Windows斷線
        const unsigned long interval = 100; // 每 100ms 傳一次 (10Hz)
        unsigned long lastSendTime = millis();
        unsigned long lastKeepAlive = millis();
        
        while (central.connected()) {
            unsigned long now = millis();
            
            if ((long)(now - lastSendTime) >= 0) {
        
                uint32_t timestamp = millis();
                
                float aX = 0, aY = 0, aZ = 0, gX = 0, gY = 0, gZ = 0;
                if (imuReady) {
                    aX = myIMU.readFloatAccelX() - offsetAX;
                    aY = myIMU.readFloatAccelY() - offsetAY;
                    aZ = myIMU.readFloatAccelZ() - offsetAZ;
                    gX = myIMU.readFloatGyroX() - offsetGX;
                    gY = myIMU.readFloatGyroY() - offsetGY;
                    gZ = myIMU.readFloatGyroZ() - offsetGZ;
                } else {
                    Serial.println("IMU not ready, skipping data read.");
                }
                
                // 藍牙傳送資料
                // 打包資料
                uint8_t buffer[30];
                memcpy(buffer, &timestamp, 4);
                memcpy(buffer + 4, &aX, 4);
                memcpy(buffer + 8, &aY, 4);
                memcpy(buffer + 12, &aZ, 4);
                memcpy(buffer + 16, &gX, 4);
                memcpy(buffer + 20, &gY, 4);
                memcpy(buffer + 24, &gZ, 4);
                memcpy(buffer + 28, &voltageRaw, 2);
                
                // 傳送資料 via BLE notify
                if (central.connected()) {
                    bool success = imuDataChar.writeValue(buffer, 30);
                    if (!success) {
                        Serial.println("BLE發送失敗!");
                    }
                }
                
                // 輸出到串列監視器
                Serial.print(timestamp);
                Serial.print(',');
                Serial.print(aX, 8);
                Serial.print(',');
                Serial.print(aY, 8);
                Serial.print(',');
                Serial.print(aZ, 8);
                Serial.print(',');
                Serial.print(gX, 8);
                Serial.print(',');
                Serial.print(gY, 8);
                Serial.print(',');
                Serial.print(gZ, 8);
                Serial.print(',');
                Serial.println(voltageRaw);
                
                // 同時透過UART服務發送CSV資料（降低精度減少大小）
                String csvData = String(timestamp) + "," + 
                               String(aX, 4) + "," + 
                               String(aY, 4) + "," + 
                               String(aZ, 4) + "," + 
                               String(gX, 4) + "," + 
                               String(gY, 4) + "," + 
                               String(gZ, 4) + "," + 
                               String(voltageRaw) + "\n";
                
                if (central.connected()) {
                    uartTxChar.writeValue(csvData.c_str(), csvData.length());
                }
                
                // 固定用 += interval，避免節奏往後推延
                lastSendTime += interval;
            }
            
            // 每5秒發送一次保活信號
            if (now - lastKeepAlive > 5000) {
                if (central.connected()) {
                    // 發送一個簡單的保活信號
                    uint8_t keepAlive[30] = {0};
                    uint32_t keepAliveTime = millis();
                    memcpy(keepAlive, &keepAliveTime, 4);
                    imuDataChar.writeValue(keepAlive, 30);
                    Serial.println("發送保活信號");
                }
                lastKeepAlive = now;
            }
            
            // 檢查連接狀態
            if (!central.connected()) {
                Serial.println("檢測到連接中斷!");
                break;
            }
        }
        Serial.println("Disconnected from central");
        BLE.advertise();
    } else {
        // 沒有連線 → 省電掛機
        delay(500);
        return;
    }
}

// IMU校正函數
void calibrateIMUOffsets() {
    Serial.println("Starting IMU calibration...");
    float sumAX = 0, sumAY = 0, sumAZ = 0;
    float sumGX = 0, sumGY = 0, sumGZ = 0;
    
    for (int i = 0; i < 100; i++) {
        sumAX += myIMU.readFloatAccelX();
        sumAY += myIMU.readFloatAccelY();
        sumAZ += myIMU.readFloatAccelZ();
        sumGX += myIMU.readFloatGyroX();
        sumGY += myIMU.readFloatGyroY();
        sumGZ += myIMU.readFloatGyroZ();
        delay(10);
    }
    
    offsetAX = sumAX / 100.0;
    offsetAY = sumAY / 100.0;
    offsetAZ = (sumAZ / 100.0) - 1.0;  // 減去重力
    offsetGX = sumGX / 100.0;
    offsetGY = sumGY / 100.0;
    offsetGZ = sumGZ / 100.0;
    
    Serial.println("IMU calibration completed");
}

//電壓偵測及電量過小啟動低耗電
void checkVoltageAndSleep() {
    unsigned long now = millis();

    if (now - lastVoltageReadTime >= 60000) {  // 每分鐘檢查一次
        voltageRaw = analogRead(A0);
        lastVoltageReadTime = now;

        float voltage = voltageRaw * (3.3 / 1023.0) * 2.0;

        updateChargingMode(voltage);

        if (voltage < 3.2) {
            Serial.println("Voltage too low! Entering sleep mode.");
            // 嘗試通知手機（即使沒連線也無妨）
            if (BLE.connected()) {
                const char* warning = "LowPowerSleep";
                uint8_t buffer[30] = {0};
                memcpy(buffer, warning, strlen(warning));
                // 改用最後 2 bytes 做為 type code
                uint16_t type = 0xABCD;  // or 0x1234
                memcpy(buffer + 28, &type, 2);
                imuDataChar.writeValue(buffer, 30);

                delay(50);
                BLE.disconnect();       //強制斷線，讓手機收到
                delay(300);
                BLE.advertise();
            }

            // 掛機直到重新連線
            while (!BLE.central().connected()) {
                delay(1000);   // 簡單省電，等手機重新連
            }

            Serial.println("BLE reconnected. Wake up.");
            BLE.advertise();
        }
    }
}

//高低電流切換
void updateChargingMode(float batteryVoltage) {
    if (batteryVoltage < 3.7) {
        if (!isHighCurrentCharging) {
            pinMode(P0_13, OUTPUT);
            digitalWrite(P0_13, LOW);  // 切換到高電流充電
            isHighCurrentCharging = true;
            Serial.println("Switched to HIGH current charging.");
        }
    } else {
        if (isHighCurrentCharging) {
            pinMode(P0_13, OUTPUT);
            digitalWrite(P0_13, HIGH);  // 切換回低電流充電
            isHighCurrentCharging = false;
            Serial.println("Switched to LOW current charging.");
        }
    }
}
