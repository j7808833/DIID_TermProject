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

//Create a instance of class LSM6DS3
LSM6DS3 myIMU(I2C_MODE, 0x6A);    //I2C device address 0x6A

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
        Serial.println("IMU Device error - Check connections!");
        while(1); // Stop execution if IMU fails to initialize
    } else {
        Serial.println("IMU Device OK!");
        Serial.println("Starting data collection...");
        Serial.println("Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ,TempC");
    }
}

void loop() {
    // Read IMU data
    float accelX = myIMU.readFloatAccelX();
    float accelY = myIMU.readFloatAccelY();
    float accelZ = myIMU.readFloatAccelZ();
    float gyroX = myIMU.readFloatGyroX();
    float gyroY = myIMU.readFloatGyroY();
    float gyroZ = myIMU.readFloatGyroZ();
    float tempC = myIMU.readTempC();
    
    // Get timestamp
    unsigned long timestamp = millis();
    
    // Output data in CSV format for easy analysis
    Serial.print(timestamp);
    Serial.print(",");
    Serial.print(accelX, 4);
    Serial.print(",");
    Serial.print(accelY, 4);
    Serial.print(",");
    Serial.print(accelZ, 4);
    Serial.print(",");
    Serial.print(gyroX, 4);
    Serial.print(",");
    Serial.print(gyroY, 4);
    Serial.print(",");
    Serial.print(gyroZ, 4);
    Serial.print(",");
    Serial.println(tempC, 2);
    
    // Delay for 20ms (50Hz sampling rate - same as BLE version)
    delay(20);
}
