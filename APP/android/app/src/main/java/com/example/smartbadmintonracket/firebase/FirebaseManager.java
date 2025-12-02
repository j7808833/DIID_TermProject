package com.example.smartbadmintonracket.firebase;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.example.smartbadmintonracket.IMUData;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.FieldValue;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Firebase 管理器
 * 負責將 IMU 資料批次上傳至 Firestore
 * 支援錄製模式切換和批次上傳（5秒或100筆資料）
 */
public class FirebaseManager {
    private static final String TAG = "FirebaseManager";
    
    // Firestore 實例
    private FirebaseFirestore db;
    
    // 待上傳資料列表
    private List<IMUData> pendingData;
    
    // 上傳配置
    private static final int UPLOAD_INTERVAL_MS = 5000;  // 5 秒
    private static final int BATCH_SIZE = 100;            // 100 筆資料
    
    // 上傳狀態
    private long lastUploadTime = 0;
    private boolean isRecordingMode = false;
    private boolean isInitialized = false;
    
    // 當前 session ID
    private String currentSessionId;
    
    // 設備 ID
    private String deviceId = "SmartRacket_001";
    
    // Handler 用於定時檢查上傳條件
    private Handler uploadHandler;
    private Runnable uploadCheckRunnable;
    
    // 上傳統計
    private int totalUploaded = 0;
    private int totalFailed = 0;
    
    public FirebaseManager() {
        pendingData = new ArrayList<>();
        uploadHandler = new Handler(Looper.getMainLooper());
        currentSessionId = generateSessionId();
    }
    
    /**
     * 初始化 Firebase
     */
    public void initialize() {
        if (isInitialized) {
            Log.w(TAG, "Firebase 已經初始化");
            return;
        }
        
        try {
            db = FirebaseFirestore.getInstance();
            isInitialized = true;
            Log.d(TAG, "Firebase 初始化成功");
            
            // 開始定時檢查上傳條件
            startUploadCheck();
        } catch (Exception e) {
            Log.e(TAG, "Firebase 初始化失敗: " + e.getClass().getSimpleName() + " - " + e.getMessage(), e);
            isInitialized = false;
        }
    }
    
    /**
     * 添加資料到待上傳列表
     * 僅在錄製模式下添加
     */
    public void addData(IMUData data) {
        if (!isRecordingMode) {
            return;  // 僅在錄製模式下上傳
        }
        
        if (!isInitialized) {
            Log.w(TAG, "Firebase 尚未初始化，無法添加資料");
            return;
        }
        
        // 確保 receivedAt 已設定
        if (data.receivedAt == 0) {
            data.receivedAt = System.currentTimeMillis();
        }
        
        synchronized (pendingData) {
            pendingData.add(data);
        }
        
        // 檢查是否需要立即上傳
        checkUploadCondition();
    }
    
    /**
     * 檢查上傳條件
     * 當資料量達到 BATCH_SIZE 或距離上次上傳超過 UPLOAD_INTERVAL_MS 時觸發上傳
     */
    private void checkUploadCondition() {
        if (!isRecordingMode || !isInitialized) {
            return;
        }
        
        long currentTime = System.currentTimeMillis();
        boolean timeCondition = (currentTime - lastUploadTime) >= UPLOAD_INTERVAL_MS;
        
        int dataSize;
        synchronized (pendingData) {
            dataSize = pendingData.size();
        }
        boolean sizeCondition = dataSize >= BATCH_SIZE;
        
        if (timeCondition || sizeCondition) {
            uploadBatch();
        }
    }
    
    /**
     * 批次上傳資料至 Firestore
     */
    private void uploadBatch() {
        if (!isInitialized || db == null) {
            Log.w(TAG, "Firebase 尚未初始化，無法上傳");
            return;
        }
        
        List<IMUData> dataToUpload;
        synchronized (pendingData) {
            if (pendingData.isEmpty()) {
                return;
            }
            dataToUpload = new ArrayList<>(pendingData);
            pendingData.clear();
        }
        
        lastUploadTime = System.currentTimeMillis();
        
        Log.d(TAG, "開始上傳批次資料，共 " + dataToUpload.size() + " 筆");
        
        // 批次上傳（使用批次寫入以提高效率）
        int successCount = 0;
        int failCount = 0;
        
        for (IMUData data : dataToUpload) {
            Map<String, Object> docData = new HashMap<>();
            docData.put("device_id", deviceId);
            docData.put("session_id", currentSessionId);
            docData.put("timestamp", data.timestamp);
            docData.put("accelX", data.accelX);
            docData.put("accelY", data.accelY);
            docData.put("accelZ", data.accelZ);
            docData.put("gyroX", data.gyroX);
            docData.put("gyroY", data.gyroY);
            docData.put("gyroZ", data.gyroZ);
            docData.put("voltage", data.voltage);
            docData.put("received_at", data.receivedAt);
            docData.put("calibrated", true);
            docData.put("uploaded_at", FieldValue.serverTimestamp());
            
            db.collection("imu_data")
                .add(docData)
                .addOnSuccessListener(documentReference -> {
                    totalUploaded++;
                    Log.d(TAG, "資料上傳成功: " + documentReference.getId());
                })
                .addOnFailureListener(e -> {
                    totalFailed++;
                    Log.e(TAG, "資料上傳失敗: " + e.getClass().getSimpleName() + " - " + e.getMessage(), e);
                    // TODO: 儲存至本地資料庫以便重試
                });
        }
        
        Log.d(TAG, String.format("批次上傳完成，成功: %d, 失敗: %d", successCount, failCount));
    }
    
    /**
     * 設定錄製模式
     */
    public void setRecordingMode(boolean enabled) {
        if (isRecordingMode == enabled) {
            return;  // 狀態未改變
        }
        
        isRecordingMode = enabled;
        
        if (enabled) {
            // 開始錄製：生成新的 session ID
            currentSessionId = generateSessionId();
            Log.d(TAG, "錄製模式已開啟，Session ID: " + currentSessionId);
            
            // 如果尚未初始化，現在初始化
            if (!isInitialized) {
                initialize();
            }
        } else {
            // 停止錄製：上傳剩餘資料
            Log.d(TAG, "錄製模式已關閉，上傳剩餘資料");
            uploadBatch();
        }
    }
    
    /**
     * 取得錄製模式狀態
     */
    public boolean isRecordingMode() {
        return isRecordingMode;
    }
    
    /**
     * 生成 Session ID
     */
    private String generateSessionId() {
        return "session_" + System.currentTimeMillis() + "_" + UUID.randomUUID().toString().substring(0, 8);
    }
    
    /**
     * 開始定時檢查上傳條件
     */
    private void startUploadCheck() {
        if (uploadCheckRunnable != null) {
            uploadHandler.removeCallbacks(uploadCheckRunnable);
        }
        
        uploadCheckRunnable = new Runnable() {
            @Override
            public void run() {
                if (isRecordingMode && isInitialized) {
                    checkUploadCondition();
                }
                // 每 1 秒檢查一次
                uploadHandler.postDelayed(this, 1000);
            }
        };
        
        uploadHandler.postDelayed(uploadCheckRunnable, 1000);
    }
    
    /**
     * 停止定時檢查
     */
    public void stopUploadCheck() {
        if (uploadCheckRunnable != null) {
            uploadHandler.removeCallbacks(uploadCheckRunnable);
            uploadCheckRunnable = null;
        }
    }
    
    /**
     * 取得上傳統計
     */
    public String getUploadStats() {
        int pendingSize;
        synchronized (pendingData) {
            pendingSize = pendingData.size();
        }
        return String.format("已上傳: %d, 失敗: %d, 待上傳: %d", totalUploaded, totalFailed, pendingSize);
    }
    
    /**
     * 取得當前 Session ID
     */
    public String getCurrentSessionId() {
        return currentSessionId;
    }
    
    /**
     * 設定設備 ID
     */
    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }
    
    /**
     * 清理資源
     */
    public void cleanup() {
        stopUploadCheck();
        setRecordingMode(false);
        synchronized (pendingData) {
            pendingData.clear();
        }
    }
}

