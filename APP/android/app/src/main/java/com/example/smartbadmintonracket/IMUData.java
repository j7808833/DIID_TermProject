package com.example.smartbadmintonracket;

/**
 * IMU 資料模型類
 * 儲存從 nRF52840 接收到的感測器資料
 */
public class IMUData {
    public long timestamp;        // 時間戳記（毫秒）
    public float accelX;          // X軸加速度 (g)
    public float accelY;          // Y軸加速度 (g)
    public float accelZ;          // Z軸加速度 (g)
    public float gyroX;           // X軸角速度 (dps)
    public float gyroY;           // Y軸角速度 (dps)
    public float gyroZ;           // Z軸角速度 (dps)
    public float voltage;         // 電壓 (V)
    public long receivedAt;       // 手機接收時間（毫秒）

    public IMUData() {
    }

    public IMUData(long timestamp, float accelX, float accelY, float accelZ,
                   float gyroX, float gyroY, float gyroZ, float voltage) {
        this.timestamp = timestamp;
        this.accelX = accelX;
        this.accelY = accelY;
        this.accelZ = accelZ;
        this.gyroX = gyroX;
        this.gyroY = gyroY;
        this.gyroZ = gyroZ;
        this.voltage = voltage;
        this.receivedAt = System.currentTimeMillis();
    }

    @Override
    public String toString() {
        return String.format(
            "時間: %d ms | 加速度: [%.3f, %.3f, %.3f] g | 角速度: [%.2f, %.2f, %.2f] dps | 電壓: %.2f V",
            timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, voltage
        );
    }
}

