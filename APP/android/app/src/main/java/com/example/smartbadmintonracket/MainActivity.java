package com.example.smartbadmintonracket;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

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

public class MainActivity extends AppCompatActivity {
    
    private BLEManager bleManager;
    private TextView statusText;
    private TextView dataCountText;
    private TextView timestampText;
    private TextView accelText;
    private TextView gyroText;
    private TextView voltageText;
    private TextView latestDataText;
    private Button scanButton;
    private Button disconnectButton;
    
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
        
        // 設定權限請求
        setupPermissionLauncher();
        
        // 檢查並請求權限
        checkAndRequestPermissions();
        
        // 設定按鈕點擊事件
        setupButtonListeners();
        
        // 設定 BLE 回調
        setupBLECallbacks();
    }
    
    private void initViews() {
        statusText = findViewById(R.id.statusText);
        dataCountText = findViewById(R.id.dataCountText);
        timestampText = findViewById(R.id.timestampText);
        accelText = findViewById(R.id.accelText);
        gyroText = findViewById(R.id.gyroText);
        voltageText = findViewById(R.id.voltageText);
        latestDataText = findViewById(R.id.latestDataText);
        scanButton = findViewById(R.id.scanButton);
        disconnectButton = findViewById(R.id.disconnectButton);
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
        String[] permissions = {
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        };
        
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
            statusText.setTextColor(0xFFFF9800); // 橙色
            
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
                        statusText.setTextColor(0xFF4CAF50); // 綠色
                        scanButton.setEnabled(false);
                        disconnectButton.setEnabled(true);
                        Toast.makeText(MainActivity.this, "連接成功！", Toast.LENGTH_SHORT).show();
                    });
                }
                
                @Override
                public void onDisconnected() {
                    runOnUiThread(() -> {
                        isConnected = false;
                        statusText.setText("狀態: 已斷線");
                        statusText.setTextColor(0xFFF44336); // 紅色
                        scanButton.setEnabled(true);
                        disconnectButton.setEnabled(false);
                        Toast.makeText(MainActivity.this, "連接已斷開", Toast.LENGTH_SHORT).show();
                    });
                }
                
                @Override
                public void onConnectionFailed(String error) {
                    runOnUiThread(() -> {
                        statusText.setText("狀態: 連接失敗 - " + error);
                        statusText.setTextColor(0xFFF44336); // 紅色
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
            statusText.setTextColor(0xFFF44336); // 紅色
            scanButton.setEnabled(true);
            disconnectButton.setEnabled(false);
            dataCount = 0;
            updateDataCount();
            clearDataDisplay();
        });
    }
    
    private void setupBLECallbacks() {
        bleManager.setDataCallback(data -> {
            runOnUiThread(() -> {
                dataCount++;
                updateDataDisplay(data);
                updateDataCount();
            });
        });
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
        
        // 更新電壓
        voltageText.setText(String.format(Locale.getDefault(), "電壓: %.2f V", data.voltage));
        
        // 更新最新資料（完整資訊）
        latestDataText.setText(String.format(Locale.getDefault(),
            "最新資料 (#%d):\n%s",
            dataCount, data.toString()));
    }
    
    private void updateDataCount() {
        dataCountText.setText(String.format("接收資料數: %d", dataCount));
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
    }
    
    @Override
    protected void onPause() {
        super.onPause();
        // 可選：在背景時停止掃描以節省電量
        if (bleManager != null && !isConnected) {
            bleManager.stopScan();
        }
    }
}
