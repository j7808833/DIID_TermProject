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
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.app.ActivityCompat;

import java.util.ArrayList;
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
    
    private Context context;
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bluetoothLeScanner;
    private BluetoothGatt bluetoothGatt;
    private Handler handler;
    
    // 資料緩衝區（用於處理分段資料）
    private byte[] dataBuffer = new byte[30];
    private int bufferOffset = 0;
    private static final int EXPECTED_DATA_SIZE = 30;
    
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
    
    public BLEManager(Context context) {
        this.context = context;
        this.handler = new Handler(Looper.getMainLooper());
        
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
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) 
            != PackageManager.PERMISSION_GRANTED) {
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
        
        if (bluetoothLeScanner != null && 
            ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) 
            == PackageManager.PERMISSION_GRANTED) {
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
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
            != PackageManager.PERMISSION_GRANTED) {
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
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                    == PackageManager.PERMISSION_GRANTED) {
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
                Log.d(TAG, "BLE 連接中斷");
                // 重置緩衝區
                bufferOffset = 0;
                if (connectionCallback != null) {
                    connectionCallback.onDisconnected();
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
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "MTU 協商完成，開始服務發現");
                gatt.discoverServices();
            }
        }
        
        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "服務發現成功");
                
                // 列出所有服務（用於除錯）
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                    == PackageManager.PERMISSION_GRANTED) {
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
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                    == PackageManager.PERMISSION_GRANTED) {
                    List<BluetoothGattCharacteristic> characteristics = service.getCharacteristics();
                    Log.d(TAG, "服務中有 " + characteristics.size() + " 個特徵:");
                    for (BluetoothGattCharacteristic c : characteristics) {
                        Log.d(TAG, "  特徵 UUID: " + c.getUuid().toString() + 
                            ", 屬性: " + Integer.toHexString(c.getProperties()));
                    }
                }
                
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
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                    == PackageManager.PERMISSION_GRANTED) {
                    boolean notificationSet = gatt.setCharacteristicNotification(characteristic, true);
                    Log.d(TAG, "設定通知: " + notificationSet);
                    
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
                        boolean writeSuccess = gatt.writeDescriptor(descriptor);
                        Log.d(TAG, "寫入描述符: " + writeSuccess);
                    } else {
                        Log.w(TAG, "特徵沒有描述符，可能無法啟用通知");
                        Log.w(TAG, "嘗試直接啟用通知（某些設備可能不需要描述符）");
                        Log.d(TAG, "資料回調狀態: " + (dataCallback != null ? "已設定" : "未設定"));
                        // 即使沒有描述符，也嘗試觸發連接成功回調
                        if (connectionCallback != null) {
                            connectionCallback.onConnected();
                        }
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
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "描述符寫入成功，通知已啟用");
                Log.d(TAG, "資料回調狀態: " + (dataCallback != null ? "已設定" : "未設定"));
                if (connectionCallback != null) {
                    connectionCallback.onConnected();
                }
            } else {
                Log.e(TAG, "描述符寫入失敗: " + status);
                if (connectionCallback != null) {
                    connectionCallback.onConnectionFailed("啟用通知失敗: " + status);
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
            
            Log.d(TAG, "收到資料通知，長度: " + data.length + " bytes");
            
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
                // 先記錄原始資料（用於除錯）
                Log.d(TAG, "解析後的原始資料: timestamp=" + imuData.timestamp + 
                    ", accel=[" + imuData.accelX + "," + imuData.accelY + "," + imuData.accelZ + "]" +
                    ", gyro=[" + imuData.gyroX + "," + imuData.gyroY + "," + imuData.gyroZ + "]" +
                    ", voltage=" + imuData.voltage);
                
                if (IMUDataParser.validate(imuData)) {
                    Log.d(TAG, "資料驗證通過，傳遞給回調");
                    if (dataCallback != null) {
                        dataCallback.onDataReceived(imuData);
                    } else {
                        Log.e(TAG, "資料回調為 null！請檢查 MainActivity 是否正確設定了回調");
                    }
                } else {
                    // 驗證失敗的詳細資訊已在 IMUDataParser.validate() 中記錄
                    Log.w(TAG, "資料驗證失敗，但暫時允許通過（用於除錯）");
                    // 暫時允許驗證失敗的資料通過，以便查看實際數值
                    if (dataCallback != null) {
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
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) 
                == PackageManager.PERMISSION_GRANTED) {
                bluetoothGatt.disconnect();
            }
            bluetoothGatt.close();
            bluetoothGatt = null;
        }
        
        Log.d(TAG, "已斷開連接");
    }
    
    /**
     * 檢查是否已連接
     */
    public boolean isConnected() {
        return bluetoothGatt != null;
    }
}

