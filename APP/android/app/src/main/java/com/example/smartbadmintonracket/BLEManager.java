package com.example.smartbadmintonracket;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.app.ActivityCompat;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.UUID;

/**
 * BLE 管理器
 * 處理 BLE 掃描、連接和資料接收
 */
public class BLEManager {
    private static final String TAG = "BLEManager";
    
    // BLE 服務和特徵 UUID
    private static final String DEVICE_NAME = "SmartRacket";
    private static final UUID SERVICE_UUID = UUID.fromString("0769bb8e-b496-4fdd-b53b-87462ff423d0");
    private static final UUID CHARACTERISTIC_UUID = UUID.fromString("8ee82f5b-76c7-4170-8f49-fff786257090");
    private static final UUID TIME_SYNC_CHAR_UUID = UUID.fromString("a1b2c3d4-e5f6-4789-a012-3456789abcde");
    
    private Context context;
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bluetoothLeScanner;
    private BluetoothGatt bluetoothGatt;
    private Handler handler;
    
    // 資料緩衝區（用於處理分段資料）
    private byte[] dataBuffer = new byte[30];
    private int bufferOffset = 0;
    private static final int EXPECTED_DATA_SIZE = 30;
    
    // 時間同步相關變數
    private long timeBaseMs = 0;  // 基準時間（毫秒，從當天 00:00:00 開始的毫秒數）
    private boolean timeSynced = false;
    
    // 回調接口
    public interface BLEConnectionCallback {
        void onDeviceFound(BluetoothDevice device);
        void onConnected();
        void onDisconnected();
        void onConnectionFailed(String error);
    }
    
    public interface IMUDataCallback {
        void onDataReceived(IMUData data);
    }
    
    private BLEConnectionCallback connectionCallback;
    private IMUDataCallback dataCallback;
    
    // 掃描相關
    private boolean isScanning = false;
    private static final long SCAN_PERIOD = 10000; // 10秒掃描時間
    
    // 連接超時處理
    private static final long DESCRIPTOR_WRITE_TIMEOUT = 3000; // 3秒超時
    private Handler timeoutHandler;
    private Runnable descriptorWriteTimeoutRunnable;
    
    public BLEManager(Context context) {
        this.context = context;
        this.handler = new Handler(Looper.getMainLooper());
        this.timeoutHandler = new Handler(Looper.getMainLooper());
        
        BluetoothManager bluetoothManager = 
            (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
            if (bluetoothAdapter != null) {
                bluetoothLeScanner = bluetoothAdapter.getBluetoothLeScanner();
            }
        }
    }
    
    /**
     * 檢查藍牙是否可用
     */
    public boolean isBluetoothAvailable() {
        return bluetoothAdapter != null && bluetoothAdapter.isEnabled();
    }
    
    /**
     * 檢查是否有 BLE 掃描權限（根據 Android 版本）
     */
    private boolean hasScanPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) 
                == PackageManager.PERMISSION_GRANTED;
        } else {
            // Android 11 及以下 (API 30 及以下)
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) 
                == PackageManager.PERMISSION_GRANTED &&
                ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADMIN) 
                == PackageManager.PERMISSION_GRANTED &&
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
                == PackageManager.PERMISSION_GRANTED;
        }
    }
    
    /**
     * 檢查是否有 BLE 連接權限（根據 Android 版本）
     */
    private boolean hasConnectPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                == PackageManager.PERMISSION_GRANTED;
        } else {
            // Android 11 及以下 (API 30 及以下)
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) 
                == PackageManager.PERMISSION_GRANTED &&
                ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADMIN) 
                == PackageManager.PERMISSION_GRANTED;
        }
    }
    
    /**
     * 開始掃描 BLE 設備
     */
    public void startScan(BLEConnectionCallback callback) {
        this.connectionCallback = callback;
        
        if (!isBluetoothAvailable()) {
            if (callback != null) {
                callback.onConnectionFailed("藍牙未開啟");
            }
            return;
        }
        
        if (bluetoothLeScanner == null) {
            if (callback != null) {
                callback.onConnectionFailed("BLE 掃描器不可用");
            }
            return;
        }
        
        // 檢查權限
        if (!hasScanPermission()) {
            if (callback != null) {
                callback.onConnectionFailed("缺少 BLE 掃描權限");
            }
            return;
        }
        
        // 設定掃描過濾器（根據設備名稱）
        List<ScanFilter> filters = new ArrayList<>();
        ScanFilter filter = new ScanFilter.Builder()
            .setDeviceName(DEVICE_NAME)
            .build();
        filters.add(filter);
        
        // 設定掃描參數
        ScanSettings settings = new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build();
        
        // 開始掃描
        isScanning = true;
        bluetoothLeScanner.startScan(filters, settings, scanCallback);
        
        Log.d(TAG, "開始掃描 BLE 設備: " + DEVICE_NAME);
        
        // 10秒後停止掃描
        handler.postDelayed(() -> {
            if (isScanning) {
                stopScan();
            }
        }, SCAN_PERIOD);
    }
    
    /**
     * 停止掃描
     */
    public void stopScan() {
        if (!isScanning) {
            return;
        }
        
        if (bluetoothLeScanner != null && hasScanPermission()) {
            bluetoothLeScanner.stopScan(scanCallback);
        }
        
        isScanning = false;
        Log.d(TAG, "停止掃描");
    }
    
    /**
     * 掃描回調
     */
    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            String deviceName = device.getName();
            
            Log.d(TAG, "掃描到設備: " + deviceName + " (" + device.getAddress() + ")");
            
            if (DEVICE_NAME.equals(deviceName)) {
                stopScan();
                if (connectionCallback != null) {
                    connectionCallback.onDeviceFound(device);
                }
                connectToDevice(device);
            }
        }
        
        @Override
        public void onScanFailed(int errorCode) {
            Log.e(TAG, "掃描失敗，錯誤碼: " + errorCode);
            stopScan();
            if (connectionCallback != null) {
                connectionCallback.onConnectionFailed("掃描失敗: " + errorCode);
            }
        }
    };
    
    /**
     * 連接到設備
     */
    public void connectToDevice(BluetoothDevice device) {
        if (device == null) {
            return;
        }
        
        // 檢查權限
        if (!hasConnectPermission()) {
            if (connectionCallback != null) {
                connectionCallback.onConnectionFailed("缺少 BLE 連接權限");
            }
            return;
        }
        
        Log.d(TAG, "正在連接到設備: " + device.getAddress());
        
        // 如果已有連接，先斷開
        if (bluetoothGatt != null) {
            bluetoothGatt.disconnect();
            bluetoothGatt.close();
            bluetoothGatt = null;
        }
        
        // 建立 GATT 連接
        bluetoothGatt = device.connectGatt(context, false, gattCallback);
    }
    
    /**
     * GATT 回調
     */
    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "BLE 連接成功");
                
                // 先請求更大的 MTU（最大 247 bytes），成功後再發現服務
                if (hasConnectPermission()) {
                    boolean mtuRequested = gatt.requestMtu(247);
                    Log.d(TAG, "請求 MTU (247): " + mtuRequested);
                    
                    // 如果 MTU 請求失敗，直接開始服務發現
                    if (!mtuRequested) {
                        Log.w(TAG, "MTU 請求失敗，直接開始服務發現");
                        gatt.discoverServices();
                    }
                    // 如果成功，等待 onMtuChanged 回調後再開始服務發現
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "BLE 連接中斷，status=" + status);
                
                // 清理 GATT 連接
                if (gatt != null) {
                    try {
                        if (hasConnectPermission()) {
                            gatt.disconnect();
                        }
                        gatt.close();
                    } catch (Exception e) {
                        Log.e(TAG, "清理 GATT 連接時發生異常: " + e.getMessage(), e);
                    }
                }
                
                // 重置緩衝區
                bufferOffset = 0;
                
                // 重置時間同步狀態（下次連線時需要重新同步）
                timeSynced = false;
                timeBaseMs = 0;
                
                // 清理超時回調
                if (descriptorWriteTimeoutRunnable != null) {
                    timeoutHandler.removeCallbacks(descriptorWriteTimeoutRunnable);
                    descriptorWriteTimeoutRunnable = null;
                }
                
                // 重置 bluetoothGatt 引用（避免使用已關閉的連接）
                if (bluetoothGatt == gatt) {
                    bluetoothGatt = null;
                }
                
                // 通知回調（在主線程執行，確保 UI 更新）
                if (connectionCallback != null) {
                    handler.post(() -> {
                        try {
                            connectionCallback.onDisconnected();
                        } catch (Exception e) {
                            Log.e(TAG, "onDisconnected 回調執行時發生異常: " + e.getMessage(), e);
                        }
                    });
                }
            }
        }
        
        @Override
        public void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "MTU 已更改為: " + mtu + " bytes");
            } else {
                Log.w(TAG, "MTU 更改失敗: " + status + "，使用預設 MTU (23 bytes)");
            }
            
            // MTU 協商完成後（無論成功或失敗），開始服務發現
            if (hasConnectPermission()) {
                Log.d(TAG, "MTU 協商完成，開始服務發現");
                gatt.discoverServices();
            }
        }
        
        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "服務發現成功");
                
                // 列出所有服務（用於除錯）
                if (hasConnectPermission()) {
                    List<BluetoothGattService> services = gatt.getServices();
                    Log.d(TAG, "找到 " + services.size() + " 個服務:");
                    for (BluetoothGattService s : services) {
                        Log.d(TAG, "  服務 UUID: " + s.getUuid().toString());
                    }
                }
                
                // 查找目標服務
                BluetoothGattService service = gatt.getService(SERVICE_UUID);
                if (service == null) {
                    Log.e(TAG, "未找到目標服務: " + SERVICE_UUID.toString());
                    if (connectionCallback != null) {
                        connectionCallback.onConnectionFailed("未找到目標服務");
                    }
                    return;
                }
                
                Log.d(TAG, "找到目標服務: " + SERVICE_UUID.toString());
                
                // 列出服務中的所有特徵（用於除錯）
                if (hasConnectPermission()) {
                    List<BluetoothGattCharacteristic> characteristics = service.getCharacteristics();
                    Log.d(TAG, "服務中有 " + characteristics.size() + " 個特徵:");
                    for (BluetoothGattCharacteristic c : characteristics) {
                        Log.d(TAG, "  特徵 UUID: " + c.getUuid().toString() + 
                            ", 屬性: " + Integer.toHexString(c.getProperties()));
                    }
                }
                
                // 同步時間（連線時同步）
                syncTimeWithMCU();
                
                // 查找目標特徵
                BluetoothGattCharacteristic characteristic = service.getCharacteristic(CHARACTERISTIC_UUID);
                if (characteristic == null) {
                    Log.e(TAG, "未找到目標特徵: " + CHARACTERISTIC_UUID.toString());
                    if (connectionCallback != null) {
                        connectionCallback.onConnectionFailed("未找到目標特徵");
                    }
                    return;
                }
                
                Log.d(TAG, "找到目標特徵: " + CHARACTERISTIC_UUID.toString());
                
                // 檢查特徵屬性
                int properties = characteristic.getProperties();
                Log.d(TAG, "特徵屬性: 0x" + Integer.toHexString(properties));
                boolean canNotify = (properties & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0;
                boolean canIndicate = (properties & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0;
                Log.d(TAG, "支援通知: " + canNotify + ", 支援指示: " + canIndicate);
                
                if (!canNotify && !canIndicate) {
                    Log.e(TAG, "特徵不支援通知或指示");
                    if (connectionCallback != null) {
                        connectionCallback.onConnectionFailed("特徵不支援通知");
                    }
                    return;
                }
                
                // 啟用通知
                if (hasConnectPermission()) {
                    boolean notificationSet = gatt.setCharacteristicNotification(characteristic, true);
                    Log.d(TAG, "設定通知: " + notificationSet);
                    
                    if (!notificationSet) {
                        Log.e(TAG, "設定通知失敗，但仍嘗試寫入描述符");
                    }
                    
                    // 寫入描述符以啟用通知
                    List<BluetoothGattDescriptor> descriptors = characteristic.getDescriptors();
                    Log.d(TAG, "特徵有 " + descriptors.size() + " 個描述符");
                    
                    if (descriptors.size() > 0) {
                        BluetoothGattDescriptor descriptor = descriptors.get(0);
                        Log.d(TAG, "描述符 UUID: " + descriptor.getUuid().toString());
                        
                        // 根據特徵屬性選擇通知或指示
                        byte[] value = canNotify ? 
                            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE :
                            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE;
                        
                        descriptor.setValue(value);
                        
                        // 確保有權限後再寫入，並在主線程執行
                        if (hasConnectPermission()) {
                            // 延遲一小段時間，確保 setCharacteristicNotification 完成
                            handler.postDelayed(() -> {
                                if (bluetoothGatt != null && hasConnectPermission()) {
                                    boolean writeSuccess = false;
                                    try {
                                        writeSuccess = bluetoothGatt.writeDescriptor(descriptor);
                                        Log.d(TAG, "寫入描述符請求: " + writeSuccess);
                                    } catch (Exception e) {
                                        Log.e(TAG, "寫入描述符時發生異常: " + e.getMessage(), e);
                                    }
                                    
                                    if (writeSuccess) {
                                        // 設置超時，如果 3 秒內沒有收到回調，也觸發連接成功
                                        timeoutHandler.removeCallbacks(descriptorWriteTimeoutRunnable);
                                        descriptorWriteTimeoutRunnable = () -> {
                                            Log.w(TAG, "描述符寫入超時，但仍觸發連接成功（連接本身已成功）");
                                            if (connectionCallback != null) {
                                                connectionCallback.onConnected();
                                            }
                                        };
                                        timeoutHandler.postDelayed(descriptorWriteTimeoutRunnable, DESCRIPTOR_WRITE_TIMEOUT);
                                    } else {
                                        Log.w(TAG, "寫入描述符請求失敗，嘗試重試");
                                        // 重試一次
                                        handler.postDelayed(() -> {
                                            if (bluetoothGatt != null && hasConnectPermission()) {
                                                try {
                                                    boolean retrySuccess = bluetoothGatt.writeDescriptor(descriptor);
                                                    Log.d(TAG, "重試寫入描述符: " + retrySuccess);
                                                    if (!retrySuccess) {
                                                        Log.w(TAG, "重試失敗，但仍觸發連接成功（某些設備可能不需要描述符）");
                                                        if (connectionCallback != null) {
                                                            connectionCallback.onConnected();
                                                        }
                                                    }
                                                } catch (Exception e) {
                                                    Log.e(TAG, "重試寫入描述符時發生異常: " + e.getMessage(), e);
                                                    if (connectionCallback != null) {
                                                        connectionCallback.onConnected();
                                                    }
                                                }
                                            }
                                        }, 500);
                                    }
                                }
                            }, 100); // 延遲 100ms 確保通知設定完成
                        } else {
                            Log.e(TAG, "缺少權限，無法寫入描述符");
                            // 即使無法寫入描述符，也嘗試觸發連接成功（某些設備可能不需要）
                            if (connectionCallback != null) {
                                Log.d(TAG, "權限不足，但仍觸發連接成功回調");
                                connectionCallback.onConnected();
                            }
                        }
                    } else {
                        Log.w(TAG, "特徵沒有描述符，可能無法啟用通知");
                        Log.w(TAG, "嘗試直接啟用通知（某些設備可能不需要描述符）");
                        Log.d(TAG, "資料回調狀態: " + (dataCallback != null ? "已設定" : "未設定"));
                        // 即使沒有描述符，也嘗試觸發連接成功回調
                        if (connectionCallback != null) {
                            Log.d(TAG, "沒有描述符，直接觸發連接成功回調");
                            connectionCallback.onConnected();
                        }
                    }
                } else {
                    Log.e(TAG, "缺少連接權限，無法啟用通知");
                    // 即使沒有權限，也嘗試觸發連接成功（連接本身可能已成功）
                    if (connectionCallback != null) {
                        Log.d(TAG, "權限不足，但仍觸發連接成功回調");
                        connectionCallback.onConnected();
                    }
                }
            } else {
                Log.e(TAG, "服務發現失敗: " + status);
                if (connectionCallback != null) {
                    connectionCallback.onConnectionFailed("服務發現失敗: " + status);
                }
            }
        }
        
        @Override
        public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
            Log.d(TAG, "onDescriptorWrite 回調: status=" + status);
            
            // 取消超時回調（因為已經收到回調了）
            if (descriptorWriteTimeoutRunnable != null) {
                timeoutHandler.removeCallbacks(descriptorWriteTimeoutRunnable);
                descriptorWriteTimeoutRunnable = null;
            }
            
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "描述符寫入成功，通知已啟用");
                Log.d(TAG, "資料回調狀態: " + (dataCallback != null ? "已設定" : "未設定"));
                
                // 觸發連接成功回調
                if (connectionCallback != null) {
                    Log.d(TAG, "觸發連接成功回調");
                    connectionCallback.onConnected();
                } else {
                    Log.w(TAG, "連接回調為 null，無法通知連接成功");
                }
            } else {
                Log.e(TAG, "描述符寫入失敗: status=" + status);
                
                // 即使描述符寫入失敗，如果連接本身是成功的，也嘗試觸發連接成功
                // 某些設備可能不需要描述符，或者可以稍後重試
                Log.w(TAG, "描述符寫入失敗，但連接可能已成功，嘗試觸發連接成功");
                if (connectionCallback != null) {
                    connectionCallback.onConnected();
                }
            }
        }
        
        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, 
                                           BluetoothGattCharacteristic characteristic) {
            // 收到資料通知
            byte[] data = characteristic.getValue();
            
            if (data == null || data.length == 0) {
                Log.w(TAG, "收到空資料或 null");
                return;
            }
            
            Log.d(TAG, "收到資料通知，長度: " + data.length + " bytes, 資料回調: " + (dataCallback != null ? "已設定" : "未設定"));
            
            // 處理資料分段
            if (data.length == EXPECTED_DATA_SIZE) {
                // 完整資料，直接解析
                Log.d(TAG, "收到完整資料 (30 bytes)，直接解析");
                processCompleteData(data);
            } else if (data.length < EXPECTED_DATA_SIZE) {
                // 分段資料，需要拼接
                Log.d(TAG, "收到分段資料 (" + data.length + " bytes)，需要拼接");
                processFragmentedData(data);
            } else {
                // 資料過長，可能是錯誤
                Log.w(TAG, "收到過長資料: " + data.length + " bytes，預期: " + EXPECTED_DATA_SIZE);
                // 嘗試解析前 30 bytes
                byte[] truncatedData = new byte[EXPECTED_DATA_SIZE];
                System.arraycopy(data, 0, truncatedData, 0, EXPECTED_DATA_SIZE);
                processCompleteData(truncatedData);
            }
        }
        
        /**
         * 處理完整的資料（30 bytes）
         */
        private void processCompleteData(byte[] data) {
            // 重置緩衝區
            bufferOffset = 0;
            
            // 驗證資料長度
            if (data == null || data.length != EXPECTED_DATA_SIZE) {
                Log.e(TAG, "資料長度錯誤: " + (data != null ? data.length : 0) + " bytes，預期: " + EXPECTED_DATA_SIZE);
                return;
            }
            
            // 解析資料
            IMUData imuData = IMUDataParser.parse(data);
            
            if (imuData != null) {
                // 將 MCU 發送的相對時間（從當天 00:00:00 開始的毫秒數）轉換為絕對時間
                long absoluteTimestamp = convertToAbsoluteTime(imuData.timestamp);
                imuData.timestamp = absoluteTimestamp;
                
                // 先記錄原始資料（用於除錯）
                Log.d(TAG, "解析後的資料: timestamp=" + imuData.timestamp + " (絕對時間)" +
                    ", accel=[" + imuData.accelX + "," + imuData.accelY + "," + imuData.accelZ + "]" +
                    ", gyro=[" + imuData.gyroX + "," + imuData.gyroY + "," + imuData.gyroZ + "]" +
                    ", voltage=" + imuData.voltage);
                
                if (IMUDataParser.validate(imuData)) {
                    Log.d(TAG, "資料驗證通過，傳遞給回調");
                    if (dataCallback != null) {
                        Log.d(TAG, "調用資料回調，timestamp=" + imuData.timestamp);
                        dataCallback.onDataReceived(imuData);
                    } else {
                        Log.e(TAG, "資料回調為 null！請檢查 MainActivity 是否正確設定了回調");
                    }
                } else {
                    // 驗證失敗的詳細資訊已在 IMUDataParser.validate() 中記錄
                    Log.w(TAG, "資料驗證失敗，但暫時允許通過（用於除錯）");
                    // 暫時允許驗證失敗的資料通過，以便查看實際數值
                    if (dataCallback != null) {
                        Log.d(TAG, "調用資料回調（驗證失敗但仍傳遞），timestamp=" + imuData.timestamp);
                        dataCallback.onDataReceived(imuData);
                    }
                }
            } else {
                Log.e(TAG, "資料解析失敗 - IMUDataParser.parse() 返回 null");
            }
        }
        
        /**
         * 處理分段資料
         */
        private void processFragmentedData(byte[] fragment) {
            if (fragment == null || fragment.length == 0) {
                Log.w(TAG, "分段資料為 null 或空");
                return;
            }
            
            // 將分段資料複製到緩衝區
            int remaining = EXPECTED_DATA_SIZE - bufferOffset;
            int copyLength = Math.min(fragment.length, remaining);
            
            if (copyLength > 0) {
                System.arraycopy(fragment, 0, dataBuffer, bufferOffset, copyLength);
                bufferOffset += copyLength;
            }
            
            Log.d(TAG, "接收分段資料: " + fragment.length + " bytes，緩衝區進度: " + 
                bufferOffset + "/" + EXPECTED_DATA_SIZE);
            
            // 檢查是否已接收完整資料
            if (bufferOffset >= EXPECTED_DATA_SIZE) {
                // 資料完整，解析並處理
                Log.d(TAG, "分段資料拼接完成，開始解析");
                byte[] completeData = new byte[EXPECTED_DATA_SIZE];
                System.arraycopy(dataBuffer, 0, completeData, 0, EXPECTED_DATA_SIZE);
                processCompleteData(completeData);
                
                // 處理剩餘資料（如果有）
                if (fragment.length > copyLength) {
                    int remainingBytes = fragment.length - copyLength;
                    Log.d(TAG, "分段資料有剩餘 " + remainingBytes + " bytes，處理下一段");
                    byte[] remainingData = new byte[remainingBytes];
                    System.arraycopy(fragment, copyLength, remainingData, 0, remainingBytes);
                    processFragmentedData(remainingData);
                }
            } else if (bufferOffset + fragment.length > EXPECTED_DATA_SIZE) {
                // 資料溢出，重置緩衝區
                Log.w(TAG, "資料溢出，重置緩衝區");
                bufferOffset = 0;
            }
        }
    };
    
    /**
     * 設定資料接收回調
     */
    public void setDataCallback(IMUDataCallback callback) {
        this.dataCallback = callback;
        if (callback != null) {
            Log.d(TAG, "資料回調已設定");
        } else {
            Log.w(TAG, "資料回調被設為 null");
        }
    }
    
    /**
     * 取得資料回調（用於檢查）
     */
    public IMUDataCallback getDataCallback() {
        return dataCallback;
    }
    
    /**
     * 斷開連接
     */
    public void disconnect() {
        stopScan();
        
        if (bluetoothGatt != null) {
            try {
                if (hasConnectPermission()) {
                    bluetoothGatt.disconnect();
                }
            } catch (Exception e) {
                Log.e(TAG, "斷開連接時發生異常: " + e.getMessage(), e);
            }
            
            try {
                bluetoothGatt.close();
            } catch (Exception e) {
                Log.e(TAG, "關閉 GATT 連接時發生異常: " + e.getMessage(), e);
            }
            
            bluetoothGatt = null;
        }
        
        // 清理超時回調
        if (descriptorWriteTimeoutRunnable != null) {
            timeoutHandler.removeCallbacks(descriptorWriteTimeoutRunnable);
            descriptorWriteTimeoutRunnable = null;
        }
        
        // 重置狀態
        bufferOffset = 0;
        timeSynced = false;
        timeBaseMs = 0;
        
        Log.d(TAG, "已斷開連接");
    }
    
    /**
     * 同步時間到 MCU
     * 發送從當天 00:00:00 開始的毫秒數
     */
    public void syncTimeWithMCU() {
        if (bluetoothGatt == null || !isConnected()) {
            Log.w(TAG, "無法同步時間：尚未連接");
            return;
        }
        
        if (!hasConnectPermission()) {
            Log.w(TAG, "無法同步時間：缺少權限");
            return;
        }
        
        // 取得當前時間（毫秒）
        long currentTimeMs = System.currentTimeMillis();
        
        // 計算從當天 00:00:00 開始的毫秒數
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(currentTimeMs);
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        long startOfDayMs = cal.getTimeInMillis();
        
        // 計算從當天 00:00:00 開始的毫秒數
        long timeOfDayMs = currentTimeMs - startOfDayMs;
        
        // 轉換為 4 bytes (uint32_t, Little-Endian)
        byte[] timeData = new byte[4];
        timeData[0] = (byte) (timeOfDayMs & 0xFF);
        timeData[1] = (byte) ((timeOfDayMs >> 8) & 0xFF);
        timeData[2] = (byte) ((timeOfDayMs >> 16) & 0xFF);
        timeData[3] = (byte) ((timeOfDayMs >> 24) & 0xFF);
        
        // 寫入時間同步特徵值
        BluetoothGattService service = bluetoothGatt.getService(SERVICE_UUID);
        if (service != null) {
            BluetoothGattCharacteristic timeChar = service.getCharacteristic(TIME_SYNC_CHAR_UUID);
            if (timeChar != null) {
                timeChar.setValue(timeData);
                boolean success = bluetoothGatt.writeCharacteristic(timeChar);
                if (success) {
                    timeBaseMs = timeOfDayMs;
                    timeSynced = true;
                    Log.d(TAG, "已發送時間同步: " + timeOfDayMs + " ms (從當天 00:00:00 開始)");
                } else {
                    Log.e(TAG, "寫入時間同步特徵值失敗");
                }
            } else {
                Log.w(TAG, "找不到時間同步特徵值，可能 MCU 尚未更新");
            }
        } else {
            Log.w(TAG, "找不到服務，無法同步時間");
        }
    }
    
    /**
     * 將 MCU 發送的相對時間（從當天 00:00:00 開始的毫秒數）轉換為絕對時間
     */
    private long convertToAbsoluteTime(long relativeMs) {
        if (!timeSynced || timeBaseMs == 0) {
            // 尚未同步，使用當前時間（向下兼容）
            return System.currentTimeMillis();
        }
        
        // 取得當前日期
        Calendar cal = Calendar.getInstance();
        long currentTimeMs = System.currentTimeMillis();
        cal.setTimeInMillis(currentTimeMs);
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        long startOfDayMs = cal.getTimeInMillis();
        
        // 絕對時間 = 當天 00:00:00 + MCU 相對時間
        return startOfDayMs + relativeMs;
    }
    
    /**
     * 檢查是否已連接
     */
    public boolean isConnected() {
        if (bluetoothGatt == null) {
            return false;
        }
        
        // 嘗試檢查連接狀態（需要權限）
        if (hasConnectPermission()) {
            try {
                int state = bluetoothGatt.getConnectionState(bluetoothGatt.getDevice());
                return state == BluetoothProfile.STATE_CONNECTED;
            } catch (Exception e) {
                Log.w(TAG, "檢查連接狀態時發生異常: " + e.getMessage());
                // 發生異常時，假設已斷開
                return false;
            }
        }
        
        // 沒有權限時，僅檢查 bluetoothGatt 是否為 null
        return true;
    }
}

