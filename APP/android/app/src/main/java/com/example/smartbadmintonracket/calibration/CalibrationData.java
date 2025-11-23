package com.example.smartbadmintonracket.calibration;

/**
 * 校正資料模型
 * 儲存各軸的偏移量
 */
public class CalibrationData {
    public float accelXOffset;
    public float accelYOffset;
    public float accelZOffset;
    public float gyroXOffset;
    public float gyroYOffset;
    public float gyroZOffset;
    public long calibrationTime; // 校正時間戳記
    
    public CalibrationData() {
        // 預設構造函數
    }
    
    public CalibrationData(float accelXOffset, float accelYOffset, float accelZOffset,
                          float gyroXOffset, float gyroYOffset, float gyroZOffset,
                          long calibrationTime) {
        this.accelXOffset = accelXOffset;
        this.accelYOffset = accelYOffset;
        this.accelZOffset = accelZOffset;
        this.gyroXOffset = gyroXOffset;
        this.gyroYOffset = gyroYOffset;
        this.gyroZOffset = gyroZOffset;
        this.calibrationTime = calibrationTime;
    }
    
    /**
     * 檢查是否有有效的校正資料
     */
    public boolean isValid() {
        // 簡單檢查：如果所有偏移量都是 0 且時間戳記為 0，則視為無效
        return calibrationTime > 0;
    }
    
    @Override
    public String toString() {
        return String.format(
            "CalibrationData{accelX=%.3f, accelY=%.3f, accelZ=%.3f, " +
            "gyroX=%.2f, gyroY=%.2f, gyroZ=%.2f, time=%d}",
            accelXOffset, accelYOffset, accelZOffset,
            gyroXOffset, gyroYOffset, gyroZOffset, calibrationTime
        );
    }
}

