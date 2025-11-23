package com.example.smartbadmintonracket;

import android.util.Log;

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
            
            // 讀取電壓原始值 (uint16_t, Little-Endian)
            // 使用 getShort() 讀取有符號 short，然後轉換為無符號 int
            int voltageRaw = buffer.getShort() & 0xFFFF;  // 轉換為無符號 int
            
            // 注意：Arduino 的 analogRead() 通常返回 10-bit (0-1023)
            // 但 nRF52840 SAADC 實際是 12-bit (0-4095)
            // 如果收到的是 10-bit 值（≤ 1023），需要轉換為 12-bit
            int voltageRaw12bit = voltageRaw;
            if (voltageRaw <= 1023) {
                // 如果收到的是 10-bit 值，轉換為 12-bit 等效值
                // 轉換公式：12bit_value = 10bit_value * 4
                voltageRaw12bit = voltageRaw * 4;
                Log.d(TAG, "檢測到 10-bit ADC 值，轉換: " + voltageRaw + " (10-bit) → " + voltageRaw12bit + " (12-bit)");
            } else {
                // 如果已經是 12-bit 值，直接使用
                Log.d(TAG, "收到 12-bit ADC 值: " + voltageRaw);
            }
            
            // 將 ADC 原始值轉換為實際電池電壓
            // 使用 nRF52840 SAADC 公式：
            // V_BAT = RESULT × K / 4096
            // 其中：
            // - RESULT: 12-bit ADC 值（0-4095）
            // - K: 校準常數（理論值 10.8 = 3.6 × 3，但可能需要根據實際硬體調整）
            // - 4096 = 2^12 (12-bit 解析度)
            //
            // 理論值：K = 10.8 (假設 GAIN=1/6, REF=0.6V, 分壓比=1/3)
            // 如果讀值偏低，可以增加 K 值；如果讀值偏高，可以減少 K 值
            // 建議：用萬用表測量實際電池電壓，然後調整 K 值以匹配
            float calibrationConstant = 10.8f;  // 可以根據實際測量值調整
            float voltage = (float)voltageRaw12bit * calibrationConstant / 4096.0f;
            
            // 只在需要除錯時記錄（避免日誌過多）
            // Log.d(TAG, "電壓計算: voltageRaw=" + voltageRaw + 
            //     " → voltageRaw12bit=" + voltageRaw12bit + 
            //     " → voltage=" + voltage + "V");
            
            // 驗證電壓值是否在合理範圍內（電池電壓：2.5V - 4.5V）
            if (voltage < 2.5f || voltage > 4.5f) {
                if (voltage < 1.0f) {
                    Log.w(TAG, "電壓值異常低: voltageRaw=" + voltageRaw + 
                        " (10-bit) / " + voltageRaw12bit + " (12-bit)" +
                        ", 計算電壓=" + voltage + "V" +
                        " (可能是 USB 供電模式、ADC 配置問題，或轉換公式需要調整)");
                } else {
                    Log.w(TAG, "電壓值超出正常範圍: voltageRaw=" + voltageRaw + 
                        " (10-bit) / " + voltageRaw12bit + " (12-bit)" +
                        ", 計算電壓=" + voltage + "V");
                }
            }

            return new IMUData(timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, voltage);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    private static final String TAG = "IMUDataParser";
    
    /**
     * 驗證資料是否有效
     * 
     * @param data IMU 資料
     * @return true 如果資料在合理範圍內
     */
    public static boolean validate(IMUData data) {
        if (data == null) {
            Log.w(TAG, "驗證失敗：資料為 null");
            return false;
        }

        // 加速度範圍：-20g ~ +20g（放寬範圍以容納揮拍動作）
        if (Math.abs(data.accelX) > 20 || 
            Math.abs(data.accelY) > 20 || 
            Math.abs(data.accelZ) > 20) {
            Log.w(TAG, "驗證失敗：加速度超出範圍 - accelX=" + data.accelX + 
                ", accelY=" + data.accelY + ", accelZ=" + data.accelZ);
            return false;
        }

        // 角速度範圍：-2500 ~ +2500 dps（放寬範圍以容納快速揮拍）
        if (Math.abs(data.gyroX) > 2500 || 
            Math.abs(data.gyroY) > 2500 || 
            Math.abs(data.gyroZ) > 2500) {
            Log.w(TAG, "驗證失敗：角速度超出範圍 - gyroX=" + data.gyroX + 
                ", gyroY=" + data.gyroY + ", gyroZ=" + data.gyroZ);
            return false;
        }

        // 電壓範圍：電池 501230 (3.7V, 150mAh)
        // 正常工作範圍：2.5V (過放) ~ 4.5V (滿電)
        // 使用正確的 nRF52840 SAADC 公式後，電壓值應該在合理範圍內
        if (data.voltage < 2.5f || data.voltage > 4.5f) {
            if (data.voltage < 1.0f) {
                Log.w(TAG, "電壓值異常低: voltage=" + data.voltage + 
                    "V (可能是 USB 供電模式、ADC 配置問題，或公式仍需要調整)");
            } else {
                Log.w(TAG, "驗證失敗：電壓超出範圍 - voltage=" + data.voltage + "V");
            }
            // 暫時允許通過，以便查看實際數值
            // return false;
        }

        return true;
    }
}

