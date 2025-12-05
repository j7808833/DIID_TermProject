package com.example.smartbadmintonracket;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import com.google.android.material.button.MaterialButton;

import androidx.activity.EdgeToEdge;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

import android.util.Log;

import com.example.smartbadmintonracket.calibration.CalibrationManager;
import com.example.smartbadmintonracket.chart.ChartManager;
import com.example.smartbadmintonracket.csv.CSVManager;
import com.example.smartbadmintonracket.filter.VoltageFilter;
import com.example.smartbadmintonracket.firebase.FirebaseManager;
import com.github.mikephil.charting.charts.LineChart;

public class MainActivity extends AppCompatActivity {
    
    private BLEManager bleManager;
    private CalibrationManager calibrationManager;
    private ChartManager chartManager;
    private VoltageFilter voltageFilter;
    private FirebaseManager firebaseManager;
    private CSVManager csvManager;
    private TextView statusText;
    private TextView dataCountText;
    private View statusIndicator;
    private com.google.android.material.card.MaterialCardView statusMessageCard;
    private TextView timestampText;
    private TextView accelText;
    private TextView gyroText;
    private TextView voltageText;
    private TextView latestDataText;
    private MaterialButton scanButton;
    private MaterialButton disconnectButton;
    private MaterialButton calibrateButton;
    private MaterialButton recordButton;
    private TextView calibrationStatusText;
    private TextView recordingStatusText;
    
    private int dataCount = 0;
    private boolean isConnected = false;
    
    // 權限請求
    private ActivityResultLauncher<String[]> requestPermissionLauncher;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        setContentView(R.layout.activity_main);
        
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main), (v, insets) -> {
            Insets systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom);
            return insets;
        });
        
        // 初始化 UI
        initViews();
        
        // 初始化 BLE 管理器
        bleManager = new BLEManager(this);
        
        // 初始化校正管理器
        calibrationManager = new CalibrationManager(this);
        
        // 初始化電壓濾波器
        voltageFilter = new VoltageFilter();
        
        // 初始化 Firebase 管理器
        firebaseManager = new FirebaseManager();
        firebaseManager.initialize();
        
        // 初始化 CSV 管理器
        csvManager = new CSVManager(this);
        csvManager.initialize();
        
        // 初始化圖表管理器
        initChartManager();
        
        // 設定權限請求
        setupPermissionLauncher();
        
        // 檢查並請求權限
        checkAndRequestPermissions();
        
        // 設定按鈕點擊事件
        setupButtonListeners();
        
        // 設定校正按鈕
        setupCalibrationButton();
        
        // 設定錄製按鈕
        setupRecordButton();
        
        // 設定 BLE 回調（必須在初始化後立即設定）
        setupBLECallbacks();
        
        Log.d("MainActivity", "BLE 回調已設定");
    }
    
    private void initViews() {
        statusText = findViewById(R.id.statusText);
        dataCountText = findViewById(R.id.dataCountText);
        statusIndicator = findViewById(R.id.statusIndicator);
        statusMessageCard = findViewById(R.id.statusMessageCard);
        timestampText = findViewById(R.id.timestampText);
        accelText = findViewById(R.id.accelText);
        gyroText = findViewById(R.id.gyroText);
        voltageText = findViewById(R.id.voltageText);
        latestDataText = findViewById(R.id.latestDataText);
        scanButton = findViewById(R.id.scanButton);
        disconnectButton = findViewById(R.id.disconnectButton);
        calibrateButton = findViewById(R.id.calibrateButton);
        recordButton = findViewById(R.id.recordButton);
        calibrationStatusText = findViewById(R.id.calibrationStatusText);
        recordingStatusText = findViewById(R.id.recordingStatusText);
    }
    
    private void initChartManager() {
        LineChart accelXChart = findViewById(R.id.accelXChart);
        LineChart accelYChart = findViewById(R.id.accelYChart);
        LineChart accelZChart = findViewById(R.id.accelZChart);
        LineChart gyroXChart = findViewById(R.id.gyroXChart);
        LineChart gyroYChart = findViewById(R.id.gyroYChart);
        LineChart gyroZChart = findViewById(R.id.gyroZChart);
        
        chartManager = new ChartManager(
            accelXChart, accelYChart, accelZChart,
            gyroXChart, gyroYChart, gyroZChart
        );
    }
    
    private void setupPermissionLauncher() {
        requestPermissionLauncher = registerForActivityResult(
            new ActivityResultContracts.RequestMultiplePermissions(),
            result -> {
                boolean allGranted = true;
                for (Boolean granted : result.values()) {
                    if (!granted) {
                        allGranted = false;
                        break;
                    }
                }
                
                if (allGranted) {
                    Toast.makeText(this, "權限已授予", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(this, "需要權限才能使用 BLE 功能", Toast.LENGTH_LONG).show();
                }
            }
        );
    }
    
    private void checkAndRequestPermissions() {
        // 根據 Android 版本請求不同的權限
        // Android 12+ (API 31+): 使用新的 BLE 權限
        // Android 11 及以下: 使用舊的 BLE 權限 + 位置權限
        String[] permissions;
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            permissions = new String[]{
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            };
        } else {
            // Android 11 及以下 (API 30 及以下)
            permissions = new String[]{
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            };
        }
        
        boolean needRequest = false;
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(this, permission) 
                != PackageManager.PERMISSION_GRANTED) {
                needRequest = true;
                break;
            }
        }
        
        if (needRequest) {
            requestPermissionLauncher.launch(permissions);
        }
    }
    
    private void setupButtonListeners() {
        scanButton.setOnClickListener(v -> {
            if (!bleManager.isBluetoothAvailable()) {
                Toast.makeText(this, "請先開啟藍牙", Toast.LENGTH_SHORT).show();
                return;
            }
            
            scanButton.setEnabled(false);
            statusText.setText("狀態: 正在掃描...");
            statusIndicator.setBackgroundResource(R.drawable.status_indicator_connecting);
            
            bleManager.startScan(new BLEManager.BLEConnectionCallback() {
                @Override
                public void onDeviceFound(android.bluetooth.BluetoothDevice device) {
                    runOnUiThread(() -> {
                        statusText.setText("狀態: 找到設備，正在連接...");
                    });
                }
                
                @Override
                public void onConnected() {
                    runOnUiThread(() -> {
                        isConnected = true;
                        statusText.setText("狀態: 已連接");
                        statusIndicator.setBackgroundResource(R.drawable.status_indicator_connected);
                        scanButton.setEnabled(false);
                        disconnectButton.setEnabled(true);
                        // 連接成功後啟動圖表更新
                        if (chartManager != null) {
                            chartManager.startUpdating();
                        }
                        Toast.makeText(MainActivity.this, "連接成功！", Toast.LENGTH_SHORT).show();
                    });
                }
                
                @Override
                public void onDisconnected() {
                    runOnUiThread(() -> {
                        isConnected = false;
                        statusText.setText("狀態: 已斷線");
                        statusIndicator.setBackgroundResource(R.drawable.status_indicator_disconnected);
                        scanButton.setEnabled(true);
                        disconnectButton.setEnabled(false);
                        // 重置電壓濾波器
                        if (voltageFilter != null) {
                            voltageFilter.reset();
                        }
                        Toast.makeText(MainActivity.this, "連接已斷開", Toast.LENGTH_SHORT).show();
                    });
                }
                
                @Override
                public void onConnectionFailed(String error) {
                    runOnUiThread(() -> {
                        statusText.setText("狀態: 連接失敗 - " + error);
                        statusIndicator.setBackgroundResource(R.drawable.status_indicator_disconnected);
                        scanButton.setEnabled(true);
                        Toast.makeText(MainActivity.this, "連接失敗: " + error, Toast.LENGTH_LONG).show();
                    });
                }
            });
        });
        
        disconnectButton.setOnClickListener(v -> {
            bleManager.disconnect();
            isConnected = false;
            statusText.setText("狀態: 已斷開");
            statusIndicator.setBackgroundResource(R.drawable.status_indicator_disconnected);
            scanButton.setEnabled(true);
            disconnectButton.setEnabled(false);
            dataCount = 0;
            updateDataCount();
            clearDataDisplay();
            
            // 重置電壓濾波器
            if (voltageFilter != null) {
                voltageFilter.reset();
            }
            
            // 停止圖表更新
            if (chartManager != null) {
                chartManager.stopUpdating();
            }
        });
    }
    
    private void setupCalibrationButton() {
        calibrateButton.setOnClickListener(v -> {
            if (!isConnected) {
                Toast.makeText(this, "請先連接設備", Toast.LENGTH_SHORT).show();
                return;
            }
            
            if (calibrationManager.isCalibrating()) {
                // 取消校正
                calibrationManager.cancelCalibration();
                calibrateButton.setText("零點校正");
                calibrationStatusText.setVisibility(android.view.View.GONE);
                Toast.makeText(this, "校正已取消", Toast.LENGTH_SHORT).show();
            } else {
                // 開始校正
                showCalibrationDialog();
            }
        });
    }
    
    private void setupRecordButton() {
        recordButton.setOnClickListener(v -> {
            if (!isConnected) {
                Toast.makeText(this, "請先連接設備", Toast.LENGTH_SHORT).show();
                return;
            }
            
            if (firebaseManager == null || csvManager == null) {
                Toast.makeText(this, "資料管理器尚未初始化", Toast.LENGTH_SHORT).show();
                return;
            }
            
            boolean isRecording = firebaseManager.isRecordingMode();
            
            // 同時啟動/停止 Firebase 和 CSV
            firebaseManager.setRecordingMode(!isRecording);
            csvManager.setRecordingMode(!isRecording);
            
            if (!isRecording) {
                // 開始錄製
                recordButton.setText("停止錄製");
                recordButton.setIcon(ContextCompat.getDrawable(this, R.drawable.ic_record_stop));
                recordButton.setBackgroundTintList(android.content.res.ColorStateList.valueOf(getResources().getColor(R.color.recording_active, getTheme())));
                String statusMsg = "錄製中... Session: " + firebaseManager.getCurrentSessionId() + 
                                   "\nCSV: " + csvManager.getCurrentFilePath();
                recordingStatusText.setText(statusMsg);
                recordingStatusText.setVisibility(android.view.View.VISIBLE);
                recordingStatusText.setTextColor(getResources().getColor(R.color.recording_active, getTheme()));
                statusMessageCard.setVisibility(android.view.View.VISIBLE);
                Toast.makeText(this, "開始錄製資料（Firebase + CSV）", Toast.LENGTH_SHORT).show();
            } else {
                // 停止錄製
                recordButton.setText("開始錄製");
                recordButton.setIcon(ContextCompat.getDrawable(this, R.drawable.ic_record_start));
                recordButton.setBackgroundTintList(android.content.res.ColorStateList.valueOf(getResources().getColor(R.color.recording_inactive, getTheme())));
                String stats = "錄製已停止\n" + firebaseManager.getUploadStats() + "\n" + csvManager.getWriteStats();
                recordingStatusText.setText(stats);
                recordingStatusText.setTextColor(getResources().getColor(android.R.color.darker_gray, getTheme()));
                Toast.makeText(this, "停止錄製，資料已上傳並儲存", Toast.LENGTH_SHORT).show();
                
                // 3 秒後隱藏狀態文字
                new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                    recordingStatusText.setVisibility(android.view.View.GONE);
                    if (calibrationStatusText.getVisibility() != android.view.View.VISIBLE) {
                        statusMessageCard.setVisibility(android.view.View.GONE);
                    }
                }, 3000);
            }
        });
        
        // 初始狀態：未錄製
        recordButton.setText("開始錄製");
        recordButton.setIcon(ContextCompat.getDrawable(this, R.drawable.ic_record_start));
        recordButton.setBackgroundTintList(android.content.res.ColorStateList.valueOf(getResources().getColor(R.color.recording_inactive, getTheme())));
        recordingStatusText.setVisibility(android.view.View.GONE);
    }
    
    private void showCalibrationDialog() {
        new android.app.AlertDialog.Builder(this)
            .setTitle("零點校正")
            .setMessage("請將球拍靜止平置在平坦表面上，保持不動。\n\n準備好後點擊「開始校正」")
            .setPositiveButton("開始校正", (dialog, which) -> {
                startCalibration();
            })
            .setNegativeButton("取消", null)
            .show();
    }
    
    private void startCalibration() {
        calibrationManager.startCalibration(new CalibrationManager.CalibrationCallback() {
                @Override
            public void onProgress(int current, int total) {
                runOnUiThread(() -> {
                    int progress = (current * 100) / total;
                    calibrationStatusText.setText(
                        String.format("校正中... %d/%d (%d%%)", current, total, progress)
                    );
                    calibrationStatusText.setVisibility(android.view.View.VISIBLE);
                    statusMessageCard.setVisibility(android.view.View.VISIBLE);
                    calibrateButton.setText("取消校正");
                });
            }
            
            @Override
            public void onComplete(com.example.smartbadmintonracket.calibration.CalibrationData calibrationData) {
                runOnUiThread(() -> {
                    calibrationStatusText.setText("校正完成！");
                    calibrationStatusText.setTextColor(0xFF4CAF50); // 綠色
                    calibrateButton.setText("零點校正");
                    
                    Toast.makeText(MainActivity.this, 
                        "校正完成！\n" + calibrationData.toString(), 
                        Toast.LENGTH_LONG).show();
                    
                    // 3 秒後隱藏狀態文字
                    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                        calibrationStatusText.setVisibility(android.view.View.GONE);
                        if (recordingStatusText.getVisibility() != android.view.View.VISIBLE) {
                            statusMessageCard.setVisibility(android.view.View.GONE);
                        }
                    }, 3000);
                });
            }
            
            @Override
            public void onError(String error) {
                runOnUiThread(() -> {
                    calibrationStatusText.setText("校正失敗: " + error);
                    calibrationStatusText.setTextColor(0xFFF44336); // 紅色
                    calibrateButton.setText("零點校正");
                    
                    Toast.makeText(MainActivity.this, "校正失敗: " + error, Toast.LENGTH_LONG).show();
                    
                    // 3 秒後隱藏狀態文字
                    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                        calibrationStatusText.setVisibility(android.view.View.GONE);
                        if (recordingStatusText.getVisibility() != android.view.View.VISIBLE) {
                            statusMessageCard.setVisibility(android.view.View.GONE);
                        }
                    }, 3000);
                });
            }
        });
        
        calibrationStatusText.setVisibility(android.view.View.VISIBLE);
        calibrationStatusText.setText("請保持球拍靜止...");
        calibrateButton.setText("取消校正");
    }
    
    private void setupBLECallbacks() {
        Log.d("MainActivity", "設定 BLE 資料回調");
        bleManager.setDataCallback(data -> {
            Log.d("MainActivity", "收到 IMU 資料回調: timestamp=" + data.timestamp);
            runOnUiThread(() -> {
                // 如果正在校正，將資料加入校正樣本
                if (calibrationManager != null && calibrationManager.isCalibrating()) {
                    calibrationManager.addCalibrationSample(data);
                }
                
                // 應用校正（如果有校正資料）
                IMUData calibratedData = calibrationManager != null 
                    ? calibrationManager.applyCalibration(data) 
                    : data;
                
                // 將資料傳給圖表管理器（用於降採樣和更新）
                if (chartManager != null) {
                    chartManager.addDataPoint(calibratedData);
                } else {
                    Log.w("MainActivity", "chartManager 為 null，無法更新圖表");
                }
                
                // 將資料傳給 Firebase 管理器（僅在錄製模式下）
                if (firebaseManager != null) {
                    firebaseManager.addData(calibratedData);
                }
                
                // 將資料傳給 CSV 管理器（僅在錄製模式下）
                if (csvManager != null) {
                    csvManager.addData(calibratedData);
                }
                
                dataCount++;
                updateDataDisplay(calibratedData);
                updateDataCount();
            });
        });
        Log.d("MainActivity", "BLE 資料回調設定完成");
    }
    
    private void updateDataDisplay(IMUData data) {
        // 更新時間戳記
        SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault());
        String timeStr = sdf.format(new Date(data.receivedAt));
        timestampText.setText(String.format("時間戳記: %d ms (接收時間: %s)", 
            data.timestamp, timeStr));
        
        // 更新加速度
        accelText.setText(String.format(Locale.getDefault(),
            "加速度 (g):\nX: %.3f\nY: %.3f\nZ: %.3f",
            data.accelX, data.accelY, data.accelZ));
        
        // 更新角速度
        gyroText.setText(String.format(Locale.getDefault(),
            "角速度 (dps):\nX: %.2f\nY: %.2f\nZ: %.2f",
            data.gyroX, data.gyroY, data.gyroZ));
        
        // 更新電壓（使用濾波器平滑讀數）
        float filteredVoltage = voltageFilter != null 
            ? voltageFilter.addSample(data.voltage) 
            : data.voltage;
        // 顯示濾波後的電壓值（保留 3 位小數以觀察穩定性）
        voltageText.setText(String.format(Locale.getDefault(), 
            "電壓: %.3f V (原始: %.3f V)", filteredVoltage, data.voltage));
        
        // 更新最新資料（完整資訊）
        latestDataText.setText(String.format(Locale.getDefault(),
            "最新資料 (#%d):\n%s",
            dataCount, data.toString()));
    }
    
    private void updateDataCount() {
        dataCountText.setText(String.format("%d", dataCount));
    }
    
    private void clearDataDisplay() {
        timestampText.setText("時間戳記: --");
        accelText.setText("加速度 (g):\nX: --\nY: --\nZ: --");
        gyroText.setText("角速度 (dps):\nX: --\nY: --\nZ: --");
        voltageText.setText("電壓: -- V");
        latestDataText.setText("最新資料:\n--");
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (bleManager != null) {
            bleManager.disconnect();
        }
        // 釋放圖表資源
        if (chartManager != null) {
            chartManager.release();
        }
        // 清理 Firebase 資源
        if (firebaseManager != null) {
            firebaseManager.cleanup();
        }
        // 清理 CSV 資源
        if (csvManager != null) {
            csvManager.cleanup();
        }
    }
    
    @Override
    protected void onPause() {
        super.onPause();
        // 可選：在背景時停止掃描以節省電量
        if (bleManager != null && !isConnected) {
            bleManager.stopScan();
        }
        // 暫停時停止圖表更新（節省資源）
        if (chartManager != null) {
            chartManager.stopUpdating();
        }
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        // 恢復時重新啟動圖表更新（如果已連接）
        if (chartManager != null && isConnected) {
            chartManager.startUpdating();
        }
    }
}
