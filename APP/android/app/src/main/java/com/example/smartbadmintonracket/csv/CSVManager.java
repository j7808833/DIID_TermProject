package com.example.smartbadmintonracket.csv;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import com.example.smartbadmintonracket.IMUData;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * CSV 檔案管理器
 * 負責將 IMU 資料以 CSV 格式儲存到外部儲存
 * 每 10 分鐘自動切換檔案，時間對齊到 10 分鐘倍數
 */
public class CSVManager {
    private static final String TAG = "CSVManager";
    
    // 檔案配置
    private static final String FILE_PREFIX = "imu_data_";
    private static final String FILE_EXTENSION = ".csv";
    private static final String DIRECTORY_NAME = "IMU_Data";
    
    // 時間對齊配置（10 分鐘 = 600000 毫秒）
    private static final long TIME_INTERVAL_MS = 10 * 60 * 1000; // 10 分鐘
    
    // CSV 欄位標題
    private static final String CSV_HEADER = "timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ\n";
    
    // 當前狀態
    private Context context;
    private File currentFile;
    private FileWriter currentWriter;
    private long currentFileStartTime; // 當前檔案對應的 10 分鐘倍數時間點
    private boolean isRecordingMode = false;
    private boolean isInitialized = false;
    
    // 待寫入資料緩衝區（用於批次寫入以提高效率）
    private List<IMUData> pendingData;
    private final Object dataLock = new Object();
    
    // Handler 用於定時檢查和批次寫入
    private Handler writeHandler;
    private Runnable writeRunnable;
    private static final long WRITE_INTERVAL_MS = 2000; // 每 2 秒批次寫入一次
    
    // 統計資訊
    private int totalWritten = 0;
    private int totalFailed = 0;
    
    public CSVManager(Context context) {
        this.context = context.getApplicationContext();
        this.pendingData = new ArrayList<>();
        this.writeHandler = new Handler(Looper.getMainLooper());
    }
    
    /**
     * 初始化 CSV 管理器
     */
    public void initialize() {
        if (isInitialized) {
            Log.w(TAG, "CSV 管理器已經初始化");
            return;
        }
        
        try {
            // 確保目錄存在
            File directory = getCSVDirectory();
            if (!directory.exists()) {
                boolean created = directory.mkdirs();
                if (!created) {
                    throw new IOException("無法建立 CSV 目錄: " + directory.getAbsolutePath());
                }
            }
            
            isInitialized = true;
            Log.d(TAG, "CSV 管理器初始化成功，目錄: " + directory.getAbsolutePath());
            
            // 開始定時批次寫入
            startPeriodicWrite();
        } catch (Exception e) {
            Log.e(TAG, "CSV 管理器初始化失敗: " + e.getMessage(), e);
            showErrorToast("CSV 儲存初始化失敗: " + e.getMessage());
            isInitialized = false;
        }
    }
    
    /**
     * 設定錄製模式
     */
    public void setRecordingMode(boolean enabled) {
        if (isRecordingMode == enabled) {
            return; // 狀態未改變
        }
        
        isRecordingMode = enabled;
        
        if (enabled) {
            // 開始錄製：初始化當前檔案
            if (!isInitialized) {
                initialize();
            }
            
            try {
                // 計算當前時間對應的 10 分鐘倍數時間點
                long now = System.currentTimeMillis();
                currentFileStartTime = alignTo10Minutes(now);
                
                // 開啟新檔案
                openNewFile(currentFileStartTime);
                
                Log.d(TAG, "錄製模式已開啟，檔案: " + (currentFile != null ? currentFile.getName() : "null"));
            } catch (Exception e) {
                Log.e(TAG, "開啟錄製檔案失敗: " + e.getMessage(), e);
                showErrorToast("無法開啟 CSV 檔案: " + e.getMessage());
                isRecordingMode = false;
            }
        } else {
            // 停止錄製：寫入剩餘資料並關閉檔案
            Log.d(TAG, "錄製模式已關閉，寫入剩餘資料");
            flushAndCloseFile();
        }
    }
    
    /**
     * 添加資料到待寫入列表
     * 僅在錄製模式下添加
     */
    public void addData(IMUData data) {
        if (!isRecordingMode) {
            return; // 僅在錄製模式下寫入
        }
        
        if (!isInitialized) {
            Log.w(TAG, "CSV 管理器尚未初始化，無法添加資料");
            return;
        }
        
        // 確保 receivedAt 已設定
        if (data.receivedAt == 0) {
            data.receivedAt = System.currentTimeMillis();
        }
        
        // 檢查是否需要切換檔案（基於 receivedAt）
        long nextFileStartTime = alignTo10Minutes(data.receivedAt);
        if (nextFileStartTime != currentFileStartTime) {
            // 需要切換到新檔案
            Log.d(TAG, "時間已跨越 10 分鐘邊界，切換檔案");
            flushAndCloseFile();
            currentFileStartTime = nextFileStartTime;
            try {
                openNewFile(currentFileStartTime);
            } catch (Exception e) {
                Log.e(TAG, "切換檔案失敗: " + e.getMessage(), e);
                showErrorToast("切換 CSV 檔案失敗: " + e.getMessage());
                isRecordingMode = false;
                return;
            }
        }
        
        // 添加到待寫入列表
        synchronized (dataLock) {
            pendingData.add(data);
        }
    }
    
    /**
     * 對齊時間到 10 分鐘倍數
     * 例如：10:08:13 -> 10:10:00, 10:10:00 -> 10:10:00, 10:10:01 -> 10:20:00
     * 規則：如果分鐘數是 10 的倍數，使用當前時間點；否則計算下一個 10 分鐘倍數
     */
    private long alignTo10Minutes(long timestamp) {
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(timestamp);
        
        // 取得分鐘數
        int minutes = cal.get(Calendar.MINUTE);
        int seconds = cal.get(Calendar.SECOND);
        int milliseconds = cal.get(Calendar.MILLISECOND);
        
        int alignedMinutes;
        
        if (minutes % 10 == 0) {
            // 如果已經是 10 分鐘倍數，使用當前時間點（秒和毫秒設為 0）
            alignedMinutes = minutes;
        } else {
            // 計算下一個 10 分鐘倍數
            alignedMinutes = ((minutes / 10) + 1) * 10;
        }
        
        // 設定為對齊後的時間（秒和毫秒設為 0）
        cal.set(Calendar.MINUTE, alignedMinutes);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        
        return cal.getTimeInMillis();
    }
    
    /**
     * 開啟新檔案
     */
    private void openNewFile(long fileStartTime) throws IOException {
        // 關閉舊檔案（如果存在）
        if (currentWriter != null) {
            try {
                currentWriter.close();
            } catch (IOException e) {
                Log.w(TAG, "關閉舊檔案失敗", e);
            }
        }
        
        // 生成檔案名稱：imu_data_20250124_101000.csv
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault());
        String fileName = FILE_PREFIX + dateFormat.format(new Date(fileStartTime)) + FILE_EXTENSION;
        
        // 建立檔案
        File directory = getCSVDirectory();
        currentFile = new File(directory, fileName);
        
        // 檢查檔案是否已存在（理論上不應該，但以防萬一）
        boolean fileExists = currentFile.exists();
        
        // 開啟檔案寫入器（append 模式）
        currentWriter = new FileWriter(currentFile, true);
        
        // 如果是新檔案，寫入 CSV 標題
        if (!fileExists) {
            currentWriter.write(CSV_HEADER);
            currentWriter.flush();
            Log.d(TAG, "建立新 CSV 檔案: " + fileName);
        } else {
            Log.d(TAG, "繼續寫入現有 CSV 檔案: " + fileName);
        }
    }
    
    /**
     * 批次寫入資料到檔案
     */
    private void writePendingData() {
        if (!isRecordingMode || !isInitialized || currentWriter == null) {
            return;
        }
        
        List<IMUData> dataToWrite;
        synchronized (dataLock) {
            if (pendingData.isEmpty()) {
                return;
            }
            dataToWrite = new ArrayList<>(pendingData);
            pendingData.clear();
        }
        
        try {
            for (IMUData data : dataToWrite) {
                // 格式化 CSV 行：timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ
                String csvLine = String.format(Locale.US, "%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                    data.timestamp,
                    data.receivedAt,
                    data.accelX,
                    data.accelY,
                    data.accelZ,
                    data.gyroX,
                    data.gyroY,
                    data.gyroZ
                );
                
                currentWriter.write(csvLine);
                totalWritten++;
            }
            
            // 刷新到磁碟
            currentWriter.flush();
            
            Log.d(TAG, String.format("批次寫入完成，共 %d 筆資料", dataToWrite.size()));
        } catch (IOException e) {
            totalFailed += dataToWrite.size();
            Log.e(TAG, "寫入 CSV 檔案失敗: " + e.getMessage(), e);
            showErrorToast("CSV 寫入失敗: " + e.getMessage());
            
            // 將失敗的資料重新加入待寫入列表（最多保留最近 1000 筆）
            synchronized (dataLock) {
                if (pendingData.size() < 1000) {
                    pendingData.addAll(0, dataToWrite); // 加到前面，優先重試
                }
            }
        }
    }
    
    /**
     * 刷新並關閉當前檔案
     */
    private void flushAndCloseFile() {
        // 先寫入所有待寫入的資料
        writePendingData();
        
        if (currentWriter != null) {
            try {
                currentWriter.flush();
                currentWriter.close();
                Log.d(TAG, "CSV 檔案已關閉: " + (currentFile != null ? currentFile.getName() : "null"));
            } catch (IOException e) {
                Log.e(TAG, "關閉 CSV 檔案失敗: " + e.getMessage(), e);
                showErrorToast("關閉 CSV 檔案失敗: " + e.getMessage());
            } finally {
                currentWriter = null;
                currentFile = null;
            }
        }
    }
    
    /**
     * 取得 CSV 檔案儲存目錄
     * 使用外部儲存（應用專屬目錄，不需要特殊權限）
     */
    private File getCSVDirectory() {
        File externalDir = context.getExternalFilesDir(null);
        if (externalDir == null) {
            // 如果外部儲存不可用，使用內部儲存
            externalDir = context.getFilesDir();
            Log.w(TAG, "外部儲存不可用，使用內部儲存");
        }
        
        return new File(externalDir, DIRECTORY_NAME);
    }
    
    /**
     * 開始定時批次寫入
     */
    private void startPeriodicWrite() {
        if (writeRunnable != null) {
            writeHandler.removeCallbacks(writeRunnable);
        }
        
        writeRunnable = new Runnable() {
            @Override
            public void run() {
                if (isRecordingMode && isInitialized) {
                    writePendingData();
                }
                // 每 2 秒執行一次
                writeHandler.postDelayed(this, WRITE_INTERVAL_MS);
            }
        };
        
        writeHandler.postDelayed(writeRunnable, WRITE_INTERVAL_MS);
    }
    
    /**
     * 停止定時寫入
     */
    private void stopPeriodicWrite() {
        if (writeRunnable != null) {
            writeHandler.removeCallbacks(writeRunnable);
            writeRunnable = null;
        }
    }
    
    /**
     * 顯示錯誤提示
     */
    private void showErrorToast(String message) {
        Handler mainHandler = new Handler(Looper.getMainLooper());
        mainHandler.post(() -> {
            Toast.makeText(context, message, Toast.LENGTH_LONG).show();
        });
    }
    
    /**
     * 取得錄製模式狀態
     */
    public boolean isRecordingMode() {
        return isRecordingMode;
    }
    
    /**
     * 取得寫入統計資訊
     */
    public String getWriteStats() {
        int pendingSize;
        synchronized (dataLock) {
            pendingSize = pendingData.size();
        }
        return String.format("已寫入: %d, 失敗: %d, 待寫入: %d", totalWritten, totalFailed, pendingSize);
    }
    
    /**
     * 取得當前檔案路徑（用於顯示）
     */
    public String getCurrentFilePath() {
        if (currentFile != null) {
            return currentFile.getAbsolutePath();
        }
        return "無";
    }
    
    /**
     * 清理資源
     */
    public void cleanup() {
        stopPeriodicWrite();
        setRecordingMode(false);
        synchronized (dataLock) {
            pendingData.clear();
        }
    }
}

