package com.example.smartbadmintonracket.calibration;

import android.content.Context;
import android.util.Log;
import com.example.smartbadmintonracket.IMUData;

import java.util.ArrayList;
import java.util.List;

/**
 * 校正管理器
 * 負責收集資料、計算偏移量、應用校正
 */
public class CalibrationManager {
    private static final String TAG = "CalibrationManager";
    private static final int REQUIRED_SAMPLES = 200; // 需要收集 200 筆資料（約 4 秒，50Hz * 4秒）
    
    private CalibrationStorage storage;
    private CalibrationData currentCalibration;
    
    // 校正過程中的資料收集
    private List<IMUData> calibrationSamples;
    private boolean isCalibrating;
    private int sampleCount;
    private CalibrationCallback callback;
    
    public interface CalibrationCallback {
        void onProgress(int current, int total);
        void onComplete(CalibrationData calibrationData);
        void onError(String error);
    }
    
    public CalibrationManager(Context context) {
        storage = new CalibrationStorage(context);
        loadCalibration();
    }
    
    /**
     * 載入已儲存的校正資料
     */
    private void loadCalibration() {
        currentCalibration = storage.loadCalibration();
        if (currentCalibration != null) {
            Log.d(TAG, "已載入校正資料: " + currentCalibration.toString());
        } else {
            Log.d(TAG, "沒有已儲存的校正資料");
        }
    }
    
    /**
     * 開始校正
     * @param callback 校正回調
     */
    public void startCalibration(CalibrationCallback callback) {
        if (isCalibrating) {
            Log.w(TAG, "校正已進行中");
            return;
        }
        
        this.callback = callback;
        this.calibrationSamples = new ArrayList<>();
        this.isCalibrating = true;
        this.sampleCount = 0;
        
        Log.d(TAG, "開始校正，需要收集 " + REQUIRED_SAMPLES + " 筆資料");
    }
    
    /**
     * 添加校正樣本資料
     * 在校正過程中，每收到一筆資料就呼叫此方法
     */
    public void addCalibrationSample(IMUData data) {
        if (!isCalibrating) {
            return;
        }
        
        calibrationSamples.add(data);
        sampleCount++;
        
        // 每 10 筆資料更新一次進度
        if (sampleCount % 10 == 0 && callback != null) {
            callback.onProgress(sampleCount, REQUIRED_SAMPLES);
        }
        
        // 收集完成
        if (sampleCount >= REQUIRED_SAMPLES) {
            completeCalibration();
        }
    }
    
    /**
     * 完成校正並計算偏移量
     */
    private void completeCalibration() {
        if (calibrationSamples.size() < REQUIRED_SAMPLES) {
            if (callback != null) {
                callback.onError("資料不足，無法完成校正");
            }
            isCalibrating = false;
            return;
        }
        
        try {
            // 計算各軸的平均值
            float accelXSum = 0, accelYSum = 0, accelZSum = 0;
            float gyroXSum = 0, gyroYSum = 0, gyroZSum = 0;
            
            for (IMUData data : calibrationSamples) {
                accelXSum += data.accelX;
                accelYSum += data.accelY;
                accelZSum += data.accelZ;
                gyroXSum += data.gyroX;
                gyroYSum += data.gyroY;
                gyroZSum += data.gyroZ;
            }
            
            int count = calibrationSamples.size();
            float accelXMean = accelXSum / count;
            float accelYMean = accelYSum / count;
            float accelZMean = accelZSum / count;
            float gyroXMean = gyroXSum / count;
            float gyroYMean = gyroYSum / count;
            float gyroZMean = gyroZSum / count;
            
            // 計算偏移量
            // 加速度計：X/Y 軸直接使用平均值，Z 軸減去 1g（重力）
            float accelXOffset = accelXMean;
            float accelYOffset = accelYMean;
            float accelZOffset = accelZMean - 1.0f; // 減去重力加速度 1g
            
            // 陀螺儀：三軸都使用平均值
            float gyroXOffset = gyroXMean;
            float gyroYOffset = gyroYMean;
            float gyroZOffset = gyroZMean;
            
            // 建立校正資料
            CalibrationData calibrationData = new CalibrationData(
                accelXOffset, accelYOffset, accelZOffset,
                gyroXOffset, gyroYOffset, gyroZOffset,
                System.currentTimeMillis()
            );
            
            // 儲存校正資料
            storage.saveCalibration(calibrationData);
            currentCalibration = calibrationData;
            
            Log.d(TAG, "校正完成: " + calibrationData.toString());
            
            // 通知完成
            if (callback != null) {
                callback.onComplete(calibrationData);
            }
            
        } catch (Exception e) {
            Log.e(TAG, "校正計算失敗", e);
            if (callback != null) {
                callback.onError("校正計算失敗: " + e.getMessage());
            }
        } finally {
            isCalibrating = false;
            calibrationSamples.clear();
        }
    }
    
    /**
     * 取消校正
     */
    public void cancelCalibration() {
        if (isCalibrating) {
            isCalibrating = false;
            calibrationSamples.clear();
            sampleCount = 0;
            Log.d(TAG, "校正已取消");
        }
    }
    
    /**
     * 應用校正到原始資料
     * @param rawData 原始 IMU 資料
     * @return 校正後的 IMU 資料
     */
    public IMUData applyCalibration(IMUData rawData) {
        if (currentCalibration == null || !currentCalibration.isValid()) {
            // 沒有校正資料，返回原始資料
            return rawData;
        }
        
        // 應用校正：減去偏移量
        return new IMUData(
            rawData.timestamp,
            rawData.accelX - currentCalibration.accelXOffset,
            rawData.accelY - currentCalibration.accelYOffset,
            rawData.accelZ - currentCalibration.accelZOffset,
            rawData.gyroX - currentCalibration.gyroXOffset,
            rawData.gyroY - currentCalibration.gyroYOffset,
            rawData.gyroZ - currentCalibration.gyroZOffset,
            rawData.voltage,
            rawData.receivedAt
        );
    }
    
    /**
     * 取得當前校正資料
     */
    public CalibrationData getCurrentCalibration() {
        return currentCalibration;
    }
    
    /**
     * 檢查是否有校正資料
     */
    public boolean hasCalibration() {
        return currentCalibration != null && currentCalibration.isValid();
    }
    
    /**
     * 清除校正資料
     */
    public void clearCalibration() {
        storage.clearCalibration();
        currentCalibration = null;
        Log.d(TAG, "校正資料已清除");
    }
    
    /**
     * 檢查是否正在校正中
     */
    public boolean isCalibrating() {
        return isCalibrating;
    }
    
    /**
     * 取得校正進度
     */
    public int getCalibrationProgress() {
        if (!isCalibrating) {
            return 0;
        }
        return (sampleCount * 100) / REQUIRED_SAMPLES;
    }
}

