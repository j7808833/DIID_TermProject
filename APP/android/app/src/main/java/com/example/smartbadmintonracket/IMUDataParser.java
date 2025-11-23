package com.example.smartbadmintonracket;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * IMU 資料解析器
 * 將 30 bytes 的二進位資料解析為 IMUData 物件
 */
public class IMUDataParser {
    
    /**
     * 解析 30 bytes 的 IMU 資料封包
     * 
     * 資料格式（Little-Endian）:
     * - 0-3: timestamp (uint32_t, 4 bytes)
     * - 4-7: accelX (float, 4 bytes)
     * - 8-11: accelY (float, 4 bytes)
     * - 12-15: accelZ (float, 4 bytes)
     * - 16-19: gyroX (float, 4 bytes)
     * - 20-23: gyroY (float, 4 bytes)
     * - 24-27: gyroZ (float, 4 bytes)
     * - 28-29: voltageRaw (uint16_t, 2 bytes)
     * 
     * @param data 30 bytes 的二進位資料
     * @return IMUData 物件，如果資料格式錯誤則返回 null
     */
    public static IMUData parse(byte[] data) {
        if (data == null || data.length != 30) {
            return null;
        }

        try {
            // 使用 Little-Endian 位元組順序
            ByteBuffer buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);

            // 解析各欄位
            long timestamp = buffer.getInt() & 0xFFFFFFFFL;  // 轉換為無符號 long
            float accelX = buffer.getFloat();
            float accelY = buffer.getFloat();
            float accelZ = buffer.getFloat();
            float gyroX = buffer.getFloat();
            float gyroY = buffer.getFloat();
            float gyroZ = buffer.getFloat();
            int voltageRaw = buffer.getShort() & 0xFFFF;  // 轉換為無符號 int
            float voltage = voltageRaw / 100.0f;

            return new IMUData(timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, voltage);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    /**
     * 驗證資料是否有效
     * 
     * @param data IMU 資料
     * @return true 如果資料在合理範圍內
     */
    public static boolean validate(IMUData data) {
        if (data == null) {
            return false;
        }

        // 加速度範圍：-16g ~ +16g
        if (Math.abs(data.accelX) > 16 || 
            Math.abs(data.accelY) > 16 || 
            Math.abs(data.accelZ) > 16) {
            return false;
        }

        // 角速度範圍：-2000 ~ +2000 dps
        if (Math.abs(data.gyroX) > 2000 || 
            Math.abs(data.gyroY) > 2000 || 
            Math.abs(data.gyroZ) > 2000) {
            return false;
        }

        // 電壓範圍：0 ~ 5V
        if (data.voltage < 0 || data.voltage > 5) {
            return false;
        }

        return true;
    }
}

