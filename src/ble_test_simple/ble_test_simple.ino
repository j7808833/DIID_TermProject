#include "ArduinoBLE.h"

// BLE Service & Characteristic
BLEService imuService("0769bb8e-b496-4fdd-b53b-87462ff423d0");
BLECharacteristic imuDataChar("8ee82f5b-76c7-4170-8f49-fff786257090", BLERead | BLENotify, 30);

void setup() {
    Serial.begin(9600);
    while (!Serial);
    
    // Initialize BLE
    if (!BLE.begin()) {
        Serial.println("BLE initialization failed!");
        while(1);
    }
    
    // Setup BLE service and characteristic
    imuService.addCharacteristic(imuDataChar);
    BLE.addService(imuService);
    imuDataChar.setValue((uint8_t*)"", 0);
    
    // Set BLE device name and start advertising
    BLE.setLocalName("SmartRacket");
    BLE.setAdvertisedService(imuService);
    BLE.advertise();
    
    Serial.println("BLE advertising started...");
    Serial.println("Device name: SmartRacket");
    Serial.println("Waiting for connection...");
}

void loop() {
    BLEDevice central = BLE.central();
    
    if (central && central.connected()) {
        static unsigned long lastSendTime = 0;
        static int counter = 0;
        
        // 每2秒發送一次測試資料
        if (millis() - lastSendTime > 2000) {
            counter++;
            
            // 準備測試資料
            uint8_t buffer[30];
            uint32_t timestamp = millis();
            float testData = counter * 0.1;
            
            memcpy(buffer, &timestamp, 4);
            memcpy(buffer + 4, &testData, 4);
            memcpy(buffer + 8, &testData, 4);
            memcpy(buffer + 12, &testData, 4);
            memcpy(buffer + 16, &testData, 4);
            memcpy(buffer + 20, &testData, 4);
            memcpy(buffer + 24, &testData, 4);
            memcpy(buffer + 28, &testData, 2);
            
            // 發送資料
            bool success = imuDataChar.writeValue(buffer, 30);
            
            Serial.print("發送測試資料 #");
            Serial.print(counter);
            Serial.print(" - BLE: ");
            Serial.println(success ? "成功" : "失敗");
            
            lastSendTime = millis();
        }
    } else {
        // 沒有連接，重新開始廣播
        static unsigned long lastAdvertiseTime = 0;
        if (millis() - lastAdvertiseTime > 1000) {
            BLE.advertise();
            lastAdvertiseTime = millis();
            Serial.println("重新開始BLE廣播...");
        }
    }
    
    delay(100);
}
