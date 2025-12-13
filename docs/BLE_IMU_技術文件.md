# 🏸 智能羽毛球拍 IMU 感測器系統 - 完整技術文件

## 📋 目錄

1. [系統概述](#系統概述)
2. [硬體規格](#硬體規格)
3. [BLE 通訊協議詳解](#ble-通訊協議詳解)
4. [資料格式規格](#資料格式規格)
5. [手機端藍芽接收程式開發指南](#手機端藍芽接收程式開發指南)
6. [手機App結果展示與UI設計](#手機app結果展示與ui設計)
7. [姿態校正功能](#姿態校正功能)
8. [Firebase 資料傳輸](#firebase-資料傳輸)
9. [資料庫設計](#資料庫設計)
10. [AI 訓練資料準備](#ai-訓練資料準備)
11. [系統架構流程圖](#系統架構流程圖)
12. [開發注意事項](#開發注意事項)
13. [故障排除](#故障排除)

---

## 系統概述

本系統是一個智能羽毛球拍感測器，透過內嵌於球拍手柄的 IMU（慣性測量單元）感測器，即時採集球拍揮動時的加速度和角速度資料，透過 BLE（藍牙低功耗）傳輸至手機 App，再經由 Firebase Firestore 上傳至雲端資料庫，最後用於 AI 模型訓練，以識別不同的球路。

### 核心功能流程

```
羽球拍感測器 → BLE傳輸 → 手機App → 零點校正 → 即時顯示 → 曲線圖視覺化 → Firebase上傳 → 遠端AI辨識 → 結果顯示
```

### 手機App核心功能

Android 手機 App 提供以下核心功能：

1. **BLE 連接管理**：連接特定球拍設備（SmartRacket）
2. **零點校正功能**：手動校正，將靜止平置時的感測器讀數歸零
3. **即時資料顯示**：即時顯示六軸感測器數值
4. **曲線圖視覺化**：以 100ms 為單位顯示六軸曲線圖
5. **Firebase 資料上傳**：批次上傳校正後的資料用於 AI 訓練
6. **CSV 本地資料儲存**：將資料儲存為 CSV 格式，支援 Excel 直接開啟
7. **智能斷線處理**：BLE 斷線時自動停止錄製並清理資源
8. **遠端 AI 辨識**：接收伺服器辨識結果（5種姿態 + 殺球球速）

### 球路識別類型

系統可識別 **5 種球路類型**：
- **smash** - 殺球
- **drive** - 抽球
- **toss** - 挑球
- **drop** - 吊球
- **other** - 其他

此外，對於殺球動作，系統會計算並顯示**球速**。

---

## 硬體規格

### 核心組件

| 組件         | 型號                      | 規格         | 功能                                  |
| ------------ | ------------------------- | ------------ | ------------------------------------- |
| **主控板**   | Seeed XIAO nRF52840 Sense | 20×17.5×5 mm | ARM Cortex-M4F, 256KB Flash, 32KB RAM |
| **感測器**   | LSM6DS3TR                 | -            | 六軸IMU（加速度計 + 陀螺儀）          |
| **電池**     | 501230                    | -            | 3.7V 鋰電池，150mAh                   |
| **充電接口** | Type-C                    | 5×8.5×3.5 mm | USB充電接口                           |

### IMU 感測器參數

| 參數                   | 加速度計 | 陀螺儀    |
| ---------------------- | -------- | --------- |
| **資料輸出頻率 (ODR)** | 416 Hz   | 416 Hz    |
| **量測範圍**           | ±16G     | ±2000 dps |
| **帶寬設定**           | 100 Hz   | 400 Hz    |
| **I²C 傳輸速率**       | 400 kHz  | 400 kHz   |
| **解析度**             | 16-bit   | 16-bit    |

### 硬體連接配置

```
球拍手柄內部配置：
├── Type-C接口（充電）
├── 主控板 (XIAO nRF52840 Sense)
│   ├── I2C 連接 LSM6DS3 (SDA, SCL)
│   ├── A0 類比輸入（電壓監控，P0.31/AIN7）
│   ├── P0_14 數位輸出（VBAT_ENABLE，控制分壓電路）
│   └── P0_13 數位輸出（充電模式控制）
└── 電池 (501230, 3.7V, 150mAh)
```

---

## BLE 通訊協議詳解

### 設備識別資訊

- **設備名稱**: `SmartRacket`
- **藍牙版本**: Bluetooth 5.0 (BLE)
- **連接模式**: 主從模式（手機為主端，感測器為從端）

### BLE 服務架構

#### 1. 服務 UUID
```
0769bb8e-b496-4fdd-b53b-87462ff423d0
```


#### 2. 特徵 UUID (Characteristic)
- **IMU Data**: `8ee82f5b-76c7-4170-8f49-fff786257090` (Notify/Read)
- **Time Sync**: `a1b2c3d4-e5f6-4789-a012-3456789abcde` (Write)

#### 3. 特徵屬性
- **IMU Data**:
  - **讀取 (Read)**: 支援
  - **通知 (Notify)**: 支援（主要使用此方式接收資料）
  - **寫入 (Write)**: 不支援

- **Time Sync**:
  - **讀取 (Read)**: 不支援
  - **通知 (Notify)**: 不支援
  - **寫入 (Write)**: 支援 (用於同步手機時間)

### BLE 連接流程

```
1. 感測器啟動 → 初始化BLE服務 → 開始廣播 (Advertising)
2. 手機App → 掃描BLE設備 → 找到 "SmartRacket"
3. 手機App → 發起連接請求 (Connect Request)
4. 感測器 → 接受連接 → 建立BLE連接
5. 手機App → 訂閱通知 (Subscribe to Notify)
6. 感測器 → 開始發送IMU資料（每20ms一次）
```

### BLE 資料傳輸參數

- **傳輸頻率**: 50 Hz（每 20ms 傳送一次）
- **單次資料大小**: 30 bytes
- **傳輸方式**: BLE Notification（推播模式，無需手機主動讀取）
- **廣播間隔**: 100ms（未連接時）

### 連接狀態管理

```python
連接狀態檢查流程：
1. 持續監聽連接狀態
2. 連接中斷時自動重新廣播
3. 低電量時自動斷線並通知手機 (目前程式端暫時停用此功能)
4. 手機斷線後感測器進入省電模式 (目前程式端暫時停用此功能)
```

---

## 資料格式規格

### 資料封包結構（30 bytes）

#### 二進位格式（Little-Endian）

| 偏移量 | 長度    | 資料類型   | 欄位名稱     | 說明                                                                                            |
| ------ | ------- | ---------- | ------------ | ----------------------------------------------------------------------------------------------- |
| 0-3    | 4 bytes | `uint32_t` | `timestamp`  | 時間戳記（millis()，單位：毫秒）                                                                |
| 4-7    | 4 bytes | `float`    | `accelX`     | X軸加速度（單位：g，已校正）                                                                    |
| 8-11   | 4 bytes | `float`    | `accelY`     | Y軸加速度（單位：g，已校正）                                                                    |
| 12-15  | 4 bytes | `float`    | `accelZ`     | Z軸加速度（單位：g，已校正，已減去重力）                                                        |
| 16-19  | 4 bytes | `float`    | `gyroX`      | X軸角速度（單位：dps，已校正）                                                                  |
| 20-23  | 4 bytes | `float`    | `gyroY`      | Y軸角速度（單位：dps，已校正）                                                                  |
| 24-27  | 4 bytes | `float`    | `gyroZ`      | Z軸角速度（單位：dps，已校正）                                                                  |
| 28-29  | 2 bytes | `uint16_t` | `voltageRaw` | 原始電壓讀值（10-bit: 0-1023，需轉換為 12-bit: 0-4095，使用公式：V_BAT = RESULT × 8.11 / 4096） |

### 資料解析範例（Python）

```python
import struct

def parse_imu_data(data: bytes) -> dict:
    """
    解析30 bytes的IMU資料封包
    
    Args:
        data: 30 bytes的二進位資料
    
    Returns:
        dict: 包含所有感測器資料的字典
    """
    if len(data) != 30:
        raise ValueError(f"資料長度錯誤，應為30 bytes，實際為{len(data)} bytes")
    
    # 使用Little-Endian格式解析
    timestamp = struct.unpack('<I', data[0:4])[0]      # uint32_t
    accelX = struct.unpack('<f', data[4:8])[0]         # float
    accelY = struct.unpack('<f', data[8:12])[0]        # float
    accelZ = struct.unpack('<f', data[12:16])[0]       # float
    gyroX = struct.unpack('<f', data[16:20])[0]        # float
    gyroY = struct.unpack('<f', data[20:24])[0]        # float
    gyroZ = struct.unpack('<f', data[24:28])[0]        # float
    voltageRaw = struct.unpack('<H', data[28:30])[0]   # uint16_t (10-bit: 0-1023)
    
    # 轉換 10-bit 到 12-bit（nRF52840 SAADC 實際是 12-bit）
    voltageRaw12bit = voltageRaw
    if voltageRaw <= 1023:
        voltageRaw12bit = voltageRaw * 4  # 10-bit 轉 12-bit
    
    # 計算實際電壓值
    # 電池：501230, 3.7V, 150mAh
    # 使用 nRF52840 SAADC 公式：V_BAT = RESULT × K / 4096
    # 校準常數 K = 8.11（根據實際測量值調整，2025-01-24）
    voltage = voltageRaw12bit * 8.11 / 4096.0
    
    return {
        'timestamp': timestamp,        # 毫秒
        'accelX': accelX,             # g (重力加速度單位)
        'accelY': accelY,             # g
        'accelZ': accelZ,             # g
        'gyroX': gyroX,               # dps (度/秒)
        'gyroY': gyroY,               # dps
        'gyroZ': gyroZ,               # dps
        'voltage': voltage             # V (伏特)
    }
```

### 資料解析範例（JavaScript/TypeScript）

```typescript
interface IMUData {
    timestamp: number;
    accelX: number;
    accelY: number;
    accelZ: number;
    gyroX: number;
    gyroY: number;
    gyroZ: number;
    voltage: number;
}

function parseIMUData(buffer: ArrayBuffer): IMUData {
    const view = new DataView(buffer);
    
    let offset = 0;
    const timestamp = view.getUint32(offset, true); offset += 4;
    const accelX = view.getFloat32(offset, true); offset += 4;
    const accelY = view.getFloat32(offset, true); offset += 4;
    const accelZ = view.getFloat32(offset, true); offset += 4;
    const gyroX = view.getFloat32(offset, true); offset += 4;
    const gyroY = view.getFloat32(offset, true); offset += 4;
    const gyroZ = view.getFloat32(offset, true); offset += 4;
    const voltageRaw = view.getUint16(offset, true); offset += 2;
    
    // 計算實際電壓值
    // 電池：501230, 3.7V, 150mAh
    // 使用 nRF52840 SAADC 公式：
    // V_BAT = RESULT × K / 4096
    // 其中：
    // - RESULT: 12-bit ADC 值（0-4095）
    // - K: 校準常數 = 8.11（根據實際測量值調整，2025-01-24）
    // 注意：Arduino analogRead() 返回 10-bit (0-1023)，需要轉換為 12-bit
    let voltageRaw12bit = voltageRaw;
    if (voltageRaw <= 1023) {
        voltageRaw12bit = voltageRaw * 4;  // 10-bit 轉 12-bit
    }
    const voltage = voltageRaw12bit * 8.11 / 4096.0;
    
    return {
        timestamp,
        accelX,
        accelY,
        accelZ,
        gyroX,
        gyroY,
        gyroZ,
        voltage
    };
}
```

### 資料單位說明

- **加速度 (Acceleration)**: 
  - 單位：`g`（重力加速度，1g ≈ 9.8 m/s²）
  - 範圍：通常為 ±16g
  - 靜止狀態下，Z軸約為 1g（重力）

- **角速度 (Angular Velocity)**:
  - 單位：`dps`（度/秒，degrees per second）
  - 範圍：±2000 dps
  - 靜止狀態下，各軸應接近 0 dps

- **時間戳記 (Timestamp)**:
  - 單位：毫秒（milliseconds）
  - 來源：Arduino `millis()` 函數
  - 從系統啟動開始累計

- **電壓 (Voltage)**:
  - 單位：`V`（伏特）
  - 範圍：2.5V - 4.5V（電池 501230, 3.7V, 150mAh）
  - 讀取頻率：每 10 秒更新一次（Arduino 端）
  - 讀取方式：每次讀取 30 筆電壓值並取平均
  - 轉換公式：`V_BAT = RESULT × 8.11 / 4096`
    - RESULT：12-bit ADC 值（0-4095）
    - 校準常數：8.11（根據實際測量值調整，2025-01-24）
  - Android 端濾波：雙層濾波器（移動平均 + EMA）平滑讀數

### 電壓讀取與濾波機制（2025-01-24 更新）

#### Arduino 端電壓讀取

1. **讀取頻率優化**：
   - 串列輸出 (Serial): 每次主迴圈 (20ms) 讀取 (用於除錯)
   - BLE 資料包: 使用緩存值，每 10 秒更新一次 (減少 ADC 開銷)

2. **讀取方式**：
   - 使用 `readVoltageAverage()` 函數
   - 每次讀取 30 筆電壓值並計算平均值
   - 讀取前啟用分壓電路（P0.14 = LOW）
   - 讀取完畢立即關閉分壓電路（P0.14 = HIGH）以省電

3. **ADC 轉換**：
   - Arduino `analogRead()` 返回 10-bit 值（0-1023）
   - nRF52840 SAADC 實際是 12-bit（0-4095）
   - 轉換公式：`12bit_value = 10bit_value × 4`

4. **電壓計算**：
   - 使用 nRF52840 SAADC 公式：`V_BAT = RESULT × K / 4096`
   - 校準常數 K = 8.11（根據實際測量值調整）

#### Android 端電壓濾波

1. **雙層濾波架構**：
   - **第一層**：移動平均（100 個樣本，約 2 秒）
   - **第二層**：指數移動平均（EMA，alpha = 0.15）

2. **異常值處理**：
   - 自動過濾異常值（< 0.1V 或 > 5.0V）
   - 檢測 USB 供電模式或讀取錯誤

3. **UI 顯示**：
   - 同時顯示濾波後的值和原始值
   - 格式：`電壓: X.XXX V (原始: X.XXX V)`

**實際實現位置**：
- Arduino：`src/main/main.ino` - `readVoltageAverage()` 函數
- Android：`APP/android/app/src/main/java/com/example/smartbadmintonracket/filter/VoltageFilter.java`

### IMU 校正機制

**注意**：本專案使用**手動觸發校正**，而非自動校正。使用者需要點擊「零點校正」按鈕來觸發校正流程。

**實際實現**：
1. **加速度計校正**：
   - 程式碼目前 **設定 Offset 為 0** (不進行校正)
   - 原因：無法保證開機時球拍是水平放置的，避免錯誤扣除重力加速度
   - **補救措施**：由 Android App 端進行校正（收集資料計算平均值，Z軸減去 1g）

2. **陀螺儀校正**：
   - 收集 200 筆資料計算平均值
   - 作為零點偏移補償

3. **校正資料儲存**：
   - 使用 SharedPreferences + Gson 儲存在本地
   - App 重啟後自動載入並應用校正值

---

## 手機端藍芽接收程式開發指南

### 開發環境建議

#### Android (Java) - 本專案使用

**專案技術棧**：
- **開發語言**: Java
- **框架**: 原生 Android (AndroidX)
- **最低 SDK**: API Level 26
- **目標 SDK**: API Level 36
- **主要依賴**:
  - Android 原生 BLE API (`android.bluetooth`)
  - MPAndroidChart v3.1.0（圖表顯示）
  - Firebase Firestore（雲端資料庫）
  - Gson 2.10.1（JSON 序列化）
  - Material Design 3

**實際實現位置**：
- `APP/android/app/src/main/java/com/example/smartbadmintonracket/`
  - `BLEManager.java` - BLE 連接管理
  - `IMUDataParser.java` - 資料解析
  - `MainActivity.java` - 主活動

#### Android (Kotlin/Java) - 通用範例

**必要權限 (AndroidManifest.xml)**
```xml
<!-- 藍牙權限 -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- 位置權限（Android 12以下需要） -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- WiFi 和網路權限 -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

**Gradle 依賴 (build.gradle)**
```gradle
dependencies {
    // BLE 支援（使用 Android BLE API）
    implementation 'com.polidea.rxandroidble2:rxandroidble:1.17.2'
    
    // 或使用 Google 的 BLE 庫
    implementation 'no.nordicsemi.android:ble:2.6.1'
    
    // HTTP 請求（用於上傳資料）
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    implementation 'com.google.code.gson:gson:2.10.1'
}
```

### 資料緩衝與處理（Android Java 實現）

由於資料傳輸頻率為 50Hz，實際實現使用以下方式管理資料：

**實際實現位置**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/`

```java
// ChartManager.java - 圖表資料緩衝（降採樣）
public class ChartManager {
    private static final int MAX_DATA_POINTS = 50;  // 5秒 * 10Hz = 50點
    private static final long UPDATE_INTERVAL_MS = 100;  // 每100ms更新一次
    private List<IMUData> dataBuffer = new ArrayList<>();
    private long lastUpdateTime = 0;
    
    public void addDataPoint(IMUData data) {
        long currentTime = System.currentTimeMillis();
        
        // 降採樣：每100ms取最新一筆資料
        if (currentTime - lastUpdateTime >= UPDATE_INTERVAL_MS) {
            dataBuffer.add(data);
            
            // 維持5秒的資料（約50個點）
            if (dataBuffer.size() > MAX_DATA_POINTS) {
                dataBuffer.remove(0);
            }
            
            lastUpdateTime = currentTime;
            updateCharts();
        }
    }
}

// FirebaseManager.java - Firebase 批次上傳緩衝
public class FirebaseManager {
    private List<IMUData> pendingData = new ArrayList<>();
    private static final int BATCH_SIZE = 100;  // 100筆資料
    private static final int UPLOAD_INTERVAL_MS = 5000;  // 5秒
    
    public void addData(IMUData data) {
        if (!isRecordingMode) return;
        
        pendingData.add(data);
        
        // 檢查上傳條件：5秒或100筆
        if (pendingData.size() >= BATCH_SIZE || 
            (System.currentTimeMillis() - lastUploadTime) >= UPLOAD_INTERVAL_MS) {
            uploadBatch();
        }
    }
}
```


---

## 手機App結果展示與UI設計

### 展示功能需求

手機App在展示時需要同時完成以下功能：

1. **即時資料收集**：持續接收BLE傳輸的IMU感測器資料
2. **即時AI推理**：使用本地TensorFlow Lite模型進行即時球路識別
3. **結果展示**：將識別結果以視覺化的方式呈現給使用者
4. **測試記錄**：保存每次揮拍的詳細資料和識別結果

### UI設計建議

#### 1. 主介面架構

建議採用Tab導航或底部導航欄設計，主要包含以下頁面：

```
┌─────────────────────────────────┐
│      智能羽球拍分析系統             │
├─────────────────────────────────┤
│                                 │
│  ┌─────┐  ┌─────┐  ┌─────┐    │
│  │首頁 │  │分析 │  │歷史 │    │
│  └─────┘  └─────┘  └─────┘    │
│                                 │
└─────────────────────────────────┘
```

#### 2. 即時測試頁面（首頁）

這是展示時的主要頁面，建議設計如下：

**上半部：連線狀態與即時資料顯示**
```
┌─────────────────────────────────┐
│  📶 SmartRacket  ✓ 已連接       │
│  電量: ████████░░ 80%          │
├─────────────────────────────────┤
│  即時感測器資料                  │
│  ┌─────────────────────────┐  │
│  │ 加速度: X Y Z            │  │
│  │ 角速度: X Y Z            │  │
│  └─────────────────────────┘  │
└─────────────────────────────────┘
```

**中間：AI識別結果展示區（重點）**
```
┌─────────────────────────────────┐
│      🎾 揮拍識別結果              │
│                                 │
│    ┌─────────────────────┐    │
│    │                     │    │
│    │    [殺球]           │    │
│    │                     │    │
│    │  信心度: 85%        │    │
│    │                     │    │
│    └─────────────────────┘    │
│                                 │
│  [準備揮拍] [開始測試] [結束]   │
└─────────────────────────────────┘
```

**下半部：即時波形圖**
```
┌─────────────────────────────────┐
│  即時資料波形                    │
│  ┌─────────────────────────┐  │
│  │  ▁▂▃▅▇█▇▅▃▂▁          │  │
│  │  (動態更新波形圖)         │  │
│  └─────────────────────────┘  │
└─────────────────────────────────┘
```

**UI元素建議：**
- 結果卡片使用大尺寸顯示，顏色區分不同球路類型：
  - 殺球：紅色系（#FF4444）
  - 抽球：藍色系（#4488FF）
  - 其他：灰色系（#888888）
- 信心度以進度條或圓形進度指示器顯示
- 結果顯示時加入動畫效果（如彈出、淡入等）
- 結果凍結顯示3-5秒，讓使用者清楚看到識別結果

#### 3. 測試結果詳細頁面（待實作）

展示每次揮拍的詳細資訊。此功能目前尚未實現，未來可添加詳細的結果展示頁面。

#### 4. 歷史記錄頁面

顯示所有測試記錄的列表：

```
┌─────────────────────────────────┐
│  測試記錄                        │
├─────────────────────────────────┤
│  🎾 殺球  85%  [今天 14:23]    │
│  🎾 抽球  72%  [今天 14:20]    │
│  🎾 其他  45%  [今天 14:15]    │
│  🎾 殺球  90%  [今天 14:10]    │
│  🎾 抽球  68%  [今天 14:05]    │
└─────────────────────────────────┘
```

#### 5. 圖表視覺化規格

**圖表需求**：
- **時間範圍**：最近 5 秒的資料
- **更新頻率**：每 100ms 更新一次（從 50Hz 降採樣）
- **圖表數量**：6 個獨立圖表（每個軸一個）
- **圖表類型**：折線圖

**資料降採樣**：
由於資料以 50Hz（每 20ms）到達，但圖表以 10Hz（每 100ms）更新，需要降採樣：
- 每 5 筆資料取 1 筆（50Hz / 5 = 10Hz）
- 這樣我們在 5 秒內有 50 個資料點（10Hz * 5s = 50 點）

**圖表實現（Android - MPAndroidChart）**：
```java
public class ChartManager {
    private static final int MAX_DATA_POINTS = 50;  // 10Hz * 5秒
    private static final int DOWNSAMPLE_FACTOR = 5;  // 50Hz -> 10Hz
    
    private List<IMUData> chartData = new ArrayList<>();
    private int sampleCounter = 0;
    
    public void addData(IMUData data) {
        sampleCounter++;
        
        // 降採樣：每 5 筆資料取 1 筆
        if (sampleCounter % DOWNSAMPLE_FACTOR == 0) {
            chartData.add(data);
            
            // 維持資料點限制
            if (chartData.size() > MAX_DATA_POINTS) {
                chartData.remove(0);
            }
            
            // 更新圖表
            updateCharts();
        }
    }
    
    private void updateCharts() {
        // 使用新資料更新所有 6 個圖表
        accelXChart.updateData(chartData, IMUData::getAccelX);
        accelYChart.updateData(chartData, IMUData::getAccelY);
        accelZChart.updateData(chartData, IMUData::getAccelZ);
        gyroXChart.updateData(chartData, IMUData::getGyroX);
        gyroYChart.updateData(chartData, IMUData::getGyroY);
        gyroZChart.updateData(chartData, IMUData::getGyroZ);
    }
}
```

**圖表樣式（實際實現）**：
- 每個軸使用不同顏色：
  - 加速度 X：藍色（#2196F3）
  - 加速度 Y：綠色（#4CAF50）
  - 加速度 Z：紫色（#9C27B0）
  - 角速度 X：橙色（#FF9800）
  - 角速度 Y：紅色（#F44336）
  - 角速度 Z：青色（#00BCD4）
- Cubic Bezier 平滑曲線
- 網格線以提高可讀性
- 軸標籤和單位
- Y 軸範圍：加速度 ±20g，角速度 ±2500 dps
- 自動縮放 X 軸範圍（0-5秒）

#### 6. 動畫效果（待實作）

目前 UI 已實現基本的 Material Design 3 設計，動畫效果可在後續版本中添加。未來可使用 Android 的 `ObjectAnimator` 或 `ValueAnimator` 實現結果彈出動畫。

### 展示模式設計

為了在展示時有更好的效果，建議設計以下模式：

#### 1. 測試模式
- 清晰的開始/停止按鈕
- 測試過程中顯示即時資料
- 每次揮拍後立即顯示結果
- 結果持續顯示3-5秒後自動清除，準備下一次測試

#### 2. 演示模式
- 自動記錄模式，無需手動操作
- 連續測試多個揮拍動作
- 自動保存所有結果
- 可以回放測試過程

### 狀態管理（Android Java 實現）

實際實現使用以下方式管理狀態：

```java
// MainActivity.java - 主要狀態管理
public class MainActivity extends AppCompatActivity {
    private BLEManager bleManager;
    private CalibrationManager calibrationManager;
    private ChartManager chartManager;
    private FirebaseManager firebaseManager;
    private VoltageFilter voltageFilter;
    
    private boolean isConnected = false;
    private int dataCount = 0;
    
    // 狀態通過回調接口管理
    private void setupBLECallbacks() {
        bleManager.setDataCallback(data -> {
            // 應用校正
            IMUData calibratedData = calibrationManager.applyCalibration(data);
            
            // 更新圖表
            chartManager.addDataPoint(calibratedData);
            
            // 上傳至 Firebase（如果錄製模式開啟）
            firebaseManager.addData(calibratedData);
            
            // 更新 UI
            updateDataDisplay(calibratedData);
        });
    }
}
```


### 效能優化建議

1. **圖表更新頻率**：波形圖建議每秒更新10-20次即可，不需要50Hz
2. **結果快取**：識別結果快取顯示，避免頻繁重新計算
3. **背景處理**：AI推理在背景執行緒進行，避免阻塞UI

---

## 零點校正功能

### 功能必要性說明

零點校正是確保感測器讀數準確和AI模型準確識別的重要功能，因為：

1. **感測器安裝差異**：不同球拍或不同安裝角度會導致感測器座標系與實際揮拍動作座標系不一致
2. **感測器偏移**：IMU 感測器本身具有固有偏移量，需要補償
3. **重力補償**：當球拍靜止平置時，Z 軸應該讀取約 1g（重力），而不是 0
4. **提高識別準確度**：經過校正後的資料能顯著提升AI模型的識別準確率

### 校正原理

當球拍靜止平置時：
- **加速度計**：
  - X 軸：應為 0（校正後）
  - Y 軸：應為 0（校正後）
  - Z 軸：靜止時約為 1g（重力），因此需要減去 1g 才能得到 0
- **陀螺儀**：
  - X/Y/Z 軸：應全部為 0（校正後）

### 校正流程設計

#### 1. 校正模式觸發（Android Java 實現）

在主介面提供「零點校正」按鈕：

**實際實現位置**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/MainActivity.java`

```java
// MainActivity.java
private void setupCalibrationButton() {
    calibrateButton.setOnClickListener(v -> {
        if (!isConnected) {
            Toast.makeText(this, "請先連接設備", Toast.LENGTH_SHORT).show();
            return;
        }
        
        if (calibrationManager.isCalibrating()) {
            // 取消校正
            calibrationManager.cancelCalibration();
        } else {
            // 開始校正
            showCalibrationDialog();
        }
    });
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
```


#### 2. 校正步驟設計

**步驟1：準備階段**
```
┌─────────────────────────────────┐
│  姿態校正                        │
├─────────────────────────────────┤
│                                 │
│  請將球拍放置在平坦表面         │
│  保持球拍靜止不動               │
│                                 │
│  準備好後請點擊「開始校正」      │
│                                 │
│      [取消]    [開始校正]        │
└─────────────────────────────────┘
```

**步驟2：靜止狀態採樣（Android Java 實現）**

**實際實現位置**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/calibration/CalibrationManager.java`

```java
// CalibrationManager.java
public class CalibrationManager {
    private static final int REQUIRED_SAMPLES = 200;  // 收集200筆資料（約4秒）
    private List<IMUData> calibrationSamples = new ArrayList<>();
    private boolean isCalibrating = false;
    private CalibrationCallback callback;
    
    public void startCalibration(CalibrationCallback callback) {
        this.callback = callback;
        isCalibrating = true;
        calibrationSamples.clear();
    }
    
    public void addCalibrationSample(IMUData data) {
        if (!isCalibrating) return;
        
        calibrationSamples.add(data);
        
        // 更新進度
        if (callback != null) {
            callback.onProgress(calibrationSamples.size(), REQUIRED_SAMPLES);
        }
        
        // 完成校正
        if (calibrationSamples.size() >= REQUIRED_SAMPLES) {
            completeCalibration();
        }
    }
    
    private void completeCalibration() {
        // 計算校正參數
        CalibrationData calData = calculateCalibration(calibrationSamples);
        
        // 保存校正參數
        storage.saveCalibration(calData);
        
        isCalibrating = false;
        
        if (callback != null) {
            callback.onComplete(calData);
        }
    }
    
    private CalibrationData calculateCalibration(List<IMUData> samples) {
        // 計算平均值作為偏移量
        float sumAX = 0, sumAY = 0, sumAZ = 0;
        float sumGX = 0, sumGY = 0, sumGZ = 0;
        
        for (IMUData data : samples) {
            sumAX += data.accelX;
            sumAY += data.accelY;
            sumAZ += data.accelZ;
            sumGX += data.gyroX;
            sumGY += data.gyroY;
            sumGZ += data.gyroZ;
        }
        
        int count = samples.size();
        float accelXOffset = sumAX / count;
        float accelYOffset = sumAY / count;
        float accelZMean = sumAZ / count;
        float accelZOffset = accelZMean - 1.0f;  // Z軸減去1g（重力）
        
        float gyroXOffset = sumGX / count;
        float gyroYOffset = sumGY / count;
        float gyroZOffset = sumGZ / count;
        
        return new CalibrationData(
            accelXOffset, accelYOffset, accelZOffset,
            gyroXOffset, gyroYOffset, gyroZOffset
        );
    }
    
    public IMUData applyCalibration(IMUData rawData) {
        CalibrationData calData = storage.loadCalibration();
        if (calData == null) {
            return rawData;  // 未校正則返回原始資料
        }
        
        return new IMUData(
            rawData.timestamp,
            rawData.accelX - calData.accelXOffset,
            rawData.accelY - calData.accelYOffset,
            rawData.accelZ - calData.accelZOffset,
            rawData.gyroX - calData.gyroXOffset,
            rawData.gyroY - calData.gyroYOffset,
            rawData.gyroZ - calData.gyroZOffset,
            rawData.voltage
        );
    }
}
```


**校正進度顯示：**
```
┌─────────────────────────────────┐
│  校正中...                      │
│                                 │
│  ████████░░░░░░░░░░ 40%         │
│                                 │
│  請保持球拍靜止不動             │
│  剩餘時間: 2.4 秒               │
│                                 │
└─────────────────────────────────┘
```

#### 3. 校正資料應用（已實現）

校正後的資料需要應用到所有接收到的資料。實際實現已在 `CalibrationManager.java` 中完成，詳見上方代碼範例。

**應用時機**：
- 所有顯示的資料都經過校正
- 所有上傳至 Firebase 的資料都經過校正
- 所有圖表顯示的資料都經過校正

**重要注意事項**：
- 所有顯示的資料都應該經過校正
- 所有上傳的資料都應該經過校正
- 校正值儲存在本地，App 重啟後仍然有效

#### 4. 校正資料儲存（已實現）

使用 SharedPreferences + Gson 保存校正參數：

**實際實現位置**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/calibration/CalibrationStorage.java`

```java
public class CalibrationStorage {
    private static final String CALIBRATION_KEY = "imu_calibration_data";
    private SharedPreferences prefs;
    private Gson gson;
    
    public CalibrationStorage(Context context) {
        prefs = context.getSharedPreferences("CalibrationPrefs", Context.MODE_PRIVATE);
        gson = new Gson();
    }
    
    public void saveCalibration(CalibrationData data) {
        SharedPreferences.Editor editor = prefs.edit();
        String json = gson.toJson(data);
        editor.putString(CALIBRATION_KEY, json);
        editor.apply();
    }
    
    public CalibrationData loadCalibration() {
        String json = prefs.getString(CALIBRATION_KEY, null);
        if (json == null) return null;
        
        return gson.fromJson(json, CalibrationData.class);
    }
    
    public void clearCalibration() {
        prefs.edit().remove(CALIBRATION_KEY).apply();
    }
}
```

### 校正時機建議

1. **手動觸發**：使用者可隨時點擊「零點校正」按鈕進行校正
2. **更換設備**：更換球拍或重新安裝感測器後
3. **定期校正**：當感測器讀數似乎不準確時建議校正
4. **校正持久性**：校正值儲存在本地，App 重啟後仍然有效

### 校正驗證（待實作）

校正完成後，可以進行簡單的驗證。目前實現中，校正值會直接儲存並應用，未來可添加驗證邏輯。

**Java 實現範例（待實作）**：
```java
public boolean validateCalibration(CalibrationData calData) {
    // 驗證加速度計偏移是否在合理範圍內
    if (Math.abs(calData.accelXOffset) > 2.0f || 
        Math.abs(calData.accelYOffset) > 2.0f || 
        Math.abs(calData.accelZOffset) > 2.0f) {
        return false; // 加速度計偏移過大
    }
    
    // 驗證陀螺儀偏移是否在合理範圍內
    if (Math.abs(calData.gyroXOffset) > 50.0f || 
        Math.abs(calData.gyroYOffset) > 50.0f || 
        Math.abs(calData.gyroZOffset) > 50.0f) {
        return false; // 陀螺儀偏移過大
    }
    
    return true;
}
```


### 進階校正功能（可選）

如果需要更高精度，可以實現多方位校正：

1. **多角度校正**：讓使用者將球拍置於不同角度進行校正
2. **動態校正**：進行特定動作（如標準揮拍）來校正
3. **個人化校正**：根據使用者的揮拍習慣進行個人化調整

---

## Firebase 資料傳輸

### 資料上傳策略

#### 1. 批次上傳（推薦用於訓練資料收集）

批次上傳資料至 Firebase Firestore：

```java
public class FirebaseManager {
    private Firestore db;
    private List<IMUData> pendingData = new ArrayList<>();
    private Handler uploadHandler;
    private static final int UPLOAD_INTERVAL = 5000;  // 5 秒
    private static final int BATCH_SIZE = 100;        // 100 筆資料
    private long lastUploadTime = 0;
    private boolean isRecordingMode = false;
    
    public void initialize() {
        db = FirebaseFirestore.getInstance();
        uploadHandler = new Handler(Looper.getMainLooper());
    }
    
    public void addData(IMUData data) {
        if (!isRecordingMode) {
            return;  // 僅在錄製模式下上傳
        }
        
        pendingData.add(data);
        checkUploadCondition();
    }
    
    private void checkUploadCondition() {
        long currentTime = System.currentTimeMillis();
        boolean timeCondition = (currentTime - lastUploadTime) >= UPLOAD_INTERVAL;
        boolean sizeCondition = pendingData.size() >= BATCH_SIZE;
        
        if (timeCondition || sizeCondition) {
            uploadBatch();
        }
    }
    
    private void uploadBatch() {
        if (pendingData.isEmpty()) return;
        
        List<IMUData> dataToUpload = new ArrayList<>(pendingData);
        pendingData.clear();
        lastUploadTime = System.currentTimeMillis();
        
        // 上傳至 Firestore
        for (IMUData data : dataToUpload) {
            Map<String, Object> docData = new HashMap<>();
            docData.put("device_id", "SmartRacket_001");
            docData.put("session_id", getCurrentSessionId());
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
                    Log.d(TAG, "資料已上傳: " + documentReference.getId());
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "上傳失敗", e);
                    // 儲存至本地資料庫以便重試
                    saveToLocalDatabase(dataToUpload);
                });
        }
    }
    
    public void setRecordingMode(boolean enabled) {
        this.isRecordingMode = enabled;
    }
}
```

#### 2. 上傳模式控制

資料上傳僅在**錄製/測試模式**下進行：

- **錄製模式開啟**：資料被收集並上傳至 Firebase
- **錄製模式關閉**：資料僅顯示，不上傳
- 使用者可以透過「開始錄製」/「停止錄製」按鈕切換錄製模式

### 上傳觸發條件

當**任一**條件滿足時觸發上傳：
1. **時間條件**：距離上次上傳已過 5 秒
2. **數量條件**：已累積 100 筆資料

### 離線資料緩存（待實作）

目前 Firebase 上傳失敗時會在 Logcat 中記錄錯誤，但尚未實現本地資料庫儲存。未來可考慮使用 Room 資料庫實現離線緩存和重試機制。

---

## CSV 本地資料儲存

### 功能概述

Android App 提供本地 CSV 檔案儲存功能，將 IMU 資料以 CSV 格式儲存到外部儲存，方便後續分析和處理。CSV 檔案使用 Excel 友好的時間戳記格式，並支援自動檔案分檔。

### CSV 檔案格式

#### 時間戳記格式

- **格式**：`yyyy/MM/dd HH:mm:ss.SSS`
- **範例**：`2025/12/05 23:34:51.123`
- **優點**：Excel 可以直接識別此格式，無需手動轉換

#### CSV 欄位結構

```csv
timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ
2025/12/05 23:34:51.123,2025/12/05 23:34:51.145,-1.016414,-0.006844,-0.023593,-0.087150,0.118300,0.036750
```

- **timestamp**：感測器時間戳記（已轉換為絕對時間）
- **receivedAt**：Android 接收時間戳記
- **accelX/Y/Z**：加速度三軸（單位：g）
- **gyroX/Y/Z**：角速度三軸（單位：dps）

### 檔案命名規則

#### 第一個檔案

- 使用第一筆資料的接收時間命名
- 格式：`imu_data_YYYYMMDD_HHmmss.csv`
- 範例：從 `23:34:51.123` 開始錄製 → `imu_data_20251205_233451.csv`

#### 後續檔案

- 使用 5 分鐘倍數邊界時間命名
- 格式：`imu_data_YYYYMMDD_HHmmss.csv`（時間對齊到 5 分鐘倍數）
- 範例：
  - 第一個檔案：`imu_data_20251205_233451.csv`（23:34:51 開始）
  - 第二個檔案：`imu_data_20251205_233500.csv`（23:35:00 開始）
  - 第三個檔案：`imu_data_20251205_234000.csv`（23:40:00 開始）

### 自動檔案分檔

#### 分檔間隔

- **時間間隔**：5 分鐘（300,000 毫秒）
- **觸發條件**：當資料的 `receivedAt` 時間跨越 5 分鐘倍數邊界時自動切換檔案

#### 分檔邏輯

```java
// 第一個檔案：使用第一筆資料時間命名
if (isFirstFile) {
    openNewFile(firstDataTime);  // 例如：23:34:51
    currentFileStartTime = alignTo5Minutes(firstDataTime);  // 23:35:00
}

// 後續檔案：檢查是否跨越 5 分鐘邊界
long nextFileStartTime = alignTo5Minutes(data.receivedAt);
if (nextFileStartTime != currentFileStartTime) {
    // 切換到新檔案
    flushAndCloseFile();
    openNewFile(getCurrent5MinuteBlock(data.receivedAt));
    currentFileStartTime = nextFileStartTime;
}
```

#### 範例場景

從 23:34:51 開始錄製到 23:40:00，會產生 3 個檔案：

1. `imu_data_20251205_233451.csv`（23:34:51 - 23:35:00）
2. `imu_data_20251205_233500.csv`（23:35:00 - 23:40:00）
3. `imu_data_20251205_234000.csv`（23:40:00 開始）

### 批次寫入機制

- **寫入頻率**：每 2 秒批次寫入一次
- **優點**：減少 I/O 操作，提高效率
- **資料緩衝**：使用 `pendingData` 列表暫存待寫入資料

### 儲存位置

- **目錄**：外部儲存應用專屬目錄 `/Android/data/com.example.smartbadmintonracket/files/IMU_Data/`
- **權限**：不需要特殊權限（使用應用專屬目錄）

### 實際實現位置

- **CSVManager.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/csv/CSVManager.java`

---

## BLE 斷線處理機制

### 斷線檢測

系統使用 Android BLE 協議的 `onConnectionStateChange` 回調來檢測連接狀態變化：

```java
@Override
public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
    if (newState == BluetoothProfile.STATE_DISCONNECTED) {
        // 檢測到斷線
        handleDisconnection(gatt);
    }
}
```

### 斷線處理流程

#### 1. 資源清理

- 關閉 GATT 連接（`gatt.disconnect()` 和 `gatt.close()`）
- 重置資料緩衝區
- 重置時間同步狀態
- 清理超時回調
- 將 `bluetoothGatt` 設為 `null`（避免使用已關閉的連接）

#### 2. 自動停止錄製

當檢測到斷線時，如果正在錄製，系統會自動：

- **停止 Firebase 錄製**：`firebaseManager.setRecordingMode(false)`
- **停止 CSV 錄製**：`csvManager.setRecordingMode(false)`
- **關閉 CSV 檔案**：確保所有資料都已寫入

#### 3. UI 更新

- 更新連接狀態顯示（「已斷線」）
- 更新錄製按鈕狀態（「開始錄製」）
- 顯示提示訊息：「設備已斷線，錄製已自動停止」
- 停止圖表更新
- 重置電壓濾波器

### 斷線原因處理

#### 常見斷線原因

1. **物理斷線**：電線斷裂、設備移動超出範圍
2. **電池耗盡**：設備自動關機
3. **手動斷開**：使用者主動斷開連接
4. **BLE 協議層斷線**：連接監督超時（Connection Supervision Timeout）

#### 連接監督超時

- BLE 協議使用「連接監督超時」機制來檢測連接是否仍然有效
- 預設超時時間通常為數秒到數十秒（由 BLE 堆疊決定）
- 不會因為幾毫秒的資料接收延遲就判定斷線

### 斷線後的恢復

#### 手動重連

- 使用者可以點擊「掃描設備」按鈕重新掃描並連接
- 系統會自動清理舊的連接狀態

#### 自動重連（待實作）

- 目前尚未實現自動重連功能
- 未來可考慮在斷線後自動重新掃描並連接

### 實際實現位置

- **BLEManager.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/BLEManager.java`
  - `onConnectionStateChange()` 方法
- **MainActivity.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/MainActivity.java`
  - `onDisconnected()` 回調處理

---

## 資料庫設計

### 建議的資料庫結構（MySQL/PostgreSQL）

#### 主要資料表：`imu_raw_data`

```sql
CREATE TABLE imu_raw_data (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    device_id VARCHAR(50) NOT NULL,
    timestamp BIGINT NOT NULL,
    accel_x FLOAT NOT NULL,
    accel_y FLOAT NOT NULL,
    accel_z FLOAT NOT NULL,
    gyro_x FLOAT NOT NULL,
    gyro_y FLOAT NOT NULL,
    gyro_z FLOAT NOT NULL,
    voltage FLOAT,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uploaded_at TIMESTAMP,
    INDEX idx_device_timestamp (device_id, timestamp),
    INDEX idx_received_at (received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### 訓練資料表：`training_data`

```sql
CREATE TABLE training_data (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    session_id VARCHAR(100) NOT NULL,
    device_id VARCHAR(50) NOT NULL,
    label VARCHAR(20) NOT NULL,  -- 'smash', 'drive', 'other'
    start_timestamp BIGINT NOT NULL,
    end_timestamp BIGINT NOT NULL,
    data_frame JSON,  -- 儲存40筆資料的陣列
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_session (session_id),
    INDEX idx_label (label)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### 球路識別結果表：`stroke_recognition`

```sql
CREATE TABLE stroke_recognition (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    device_id VARCHAR(50) NOT NULL,
    session_id VARCHAR(100) NOT NULL,
    predicted_label VARCHAR(20) NOT NULL,
    confidence FLOAT NOT NULL,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_device_session (device_id, session_id),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### RESTful API 設計建議

#### 1. 上傳單筆IMU資料
```
POST /api/v1/imu-data
Content-Type: application/json

Request Body:
{
  "device_id": "SmartRacket_001",
  "timestamp": 1234567890,
  "accelX": 0.123,
  "accelY": -0.456,
  "accelZ": 0.789,
  "gyroX": 12.34,
  "gyroY": -56.78,
  "gyroZ": 90.12,
  "voltage": 3.65,
  "received_at": 1234567890123
}

Response:
{
  "status": "success",
  "data_id": 12345,
  "message": "Data uploaded successfully"
}
```

#### 2. 批次上傳IMU資料
```
POST /api/v1/imu-data/batch
Content-Type: application/json

Request Body:
{
  "device_id": "SmartRacket_001",
  "data": [
    { "timestamp": 1234567890, "accelX": 0.123, ... },
    { "timestamp": 1234567910, "accelX": 0.124, ... },
    ...
  ]
}

Response:
{
  "status": "success",
  "uploaded_count": 50,
  "message": "Batch data uploaded successfully"
}
```

#### 3. 上傳標記的訓練資料
```
POST /api/v1/training-data
Content-Type: application/json

Request Body:
{
  "session_id": "session_20241201_001",
  "device_id": "SmartRacket_001",
  "label": "smash",
  "start_timestamp": 1234567890,
  "end_timestamp": 1234568690,
  "data_frame": [
    { "timestamp": 1234567890, "accelX": 0.123, ... },
    { "timestamp": 1234567910, "accelX": 0.124, ... },
    ... (40筆資料)
  ]
}

Response:
{
  "status": "success",
  "training_data_id": 67890,
  "message": "Training data saved successfully"
}
```

---

## AI 訓練資料準備

### 資料格式要求

#### 1. 時間窗口切割

AI 模型需要固定長度的輸入，建議使用**40筆資料**作為一個分析窗口（對應約 0.8 秒的資料）：

```python
def create_data_frames(raw_data, window_size=40):
    """
    將原始資料切割成固定長度的frame
    
    Args:
        raw_data: List[dict] - 原始IMU資料列表
        window_size: int - 每個frame的資料筆數（預設40）
    
    Returns:
        List[List[dict]] - 切割後的資料frame列表
    """
    frames = []
    for i in range(len(raw_data) - window_size + 1):
        frame = raw_data[i:i + window_size]
        frames.append(frame)
    return frames
```

#### 2. 特徵提取

每個frame需要轉換為模型輸入格式 `[1, 40, 6, 1]`：

- **批次大小**: 1
- **時間點**: 40（40筆資料）
- **特徵數**: 6（accelX, accelY, accelZ, gyroX, gyroY, gyroZ）
- **通道數**: 1

```python
import numpy as np

def frame_to_model_input(frame):
    """
    將資料frame轉換為模型輸入格式
    
    Args:
        frame: List[dict] - 40筆IMU資料
    
    Returns:
        numpy.ndarray - 形狀為 (1, 40, 6, 1) 的陣列
    """
    features = []
    for data in frame:
        features.append([
            data['accelX'],
            data['accelY'],
            data['accelZ'],
            data['gyroX'],
            data['gyroY'],
            data['gyroZ']
        ])
    
    # 轉換為 numpy 陣列
    array = np.array(features, dtype=np.float32)
    
    # 重塑為 (1, 40, 6, 1)
    array = array.reshape(1, 40, 6, 1)
    
    return array
```

### 資料標記流程

#### 1. 自動峰值偵測

根據感測器資料的峰值來識別擊球動作：

```python
def detect_peak_frames(data, threshold_std=2.0):
    """
    透過標準差偵測峰值（擊球動作）
    
    Args:
        data: List[dict] - IMU資料列表
        threshold_std: float - 標準差閾值
    
    Returns:
        List[int] - 峰值索引列表
    """
    # 提取gY軸資料作為主要判斷依據
    gyY_values = [d['gyroY'] for d in data]
    
    mean = np.mean(gyY_values)
    std = np.std(gyY_values)
    
    peaks = []
    for i in range(len(gyY_values)):
        if abs(gyY_values[i] - mean) > threshold_std * std:
            peaks.append(i)
    
    return peaks

def create_labeled_frames(raw_data, peak_indices, label):
    """
    根據峰值建立標記的資料frame
    
    Args:
        raw_data: List[dict] - 原始資料
        peak_indices: List[int] - 峰值索引
        label: str - 標籤（'smash', 'drive', 'other'）
    
    Returns:
        List[dict] - 標記的frame列表
    """
    frames = []
    for peak_idx in peak_indices:
        # 峰值前19筆 + 峰值 + 後20筆 = 40筆
        start_idx = max(0, peak_idx - 19)
        end_idx = min(len(raw_data), peak_idx + 21)
        
        frame = raw_data[start_idx:end_idx]
        
        if len(frame) == 40:
            frames.append({
                'label': label,
                'data': frame,
                'peak_index': peak_idx
            })
    
    return frames
```

#### 2. 手動標記工具

建議開發一個標記工具，讓使用者可以：
- 視覺化顯示IMU資料波形
- 手動標記擊球動作的開始和結束時間
- 選擇球路類別（smash、drive、other）

### 資料預處理

#### 1. 資料標準化

```python
def normalize_frame(frame, mean=None, std=None):
    """
    標準化資料frame（Z-score標準化）
    
    Args:
        frame: numpy.ndarray - 原始資料frame
        mean: numpy.ndarray - 預計算的平均值（用於測試資料）
        std: numpy.ndarray - 預計算的標準差（用於測試資料）
    
    Returns:
        tuple: (標準化後的frame, mean, std)
    """
    if mean is None or std is None:
        mean = np.mean(frame, axis=0, keepdims=True)
        std = np.std(frame, axis=0, keepdims=True)
    
    # 避免除以零
    std = np.where(std == 0, 1, std)
    
    normalized = (frame - mean) / std
    
    return normalized, mean, std
```

#### 2. 資料增強

```python
def augment_data(frames, noise_factor=0.01):
    """
    添加雜訊進行資料增強
    
    Args:
        frames: List[numpy.ndarray] - 原始frame列表
        noise_factor: float - 雜訊強度
    
    Returns:
        List[numpy.ndarray] - 增強後的frame列表
    """
    augmented = []
    for frame in frames:
        noise = np.random.normal(0, noise_factor, frame.shape)
        augmented_frame = frame + noise
        augmented.append(augmented_frame)
    
    return augmented
```

### 資料集組織

```
training_data/
├── smash/
│   ├── frame_001.npy
│   ├── frame_002.npy
│   └── ...
├── drive/
│   ├── frame_001.npy
│   ├── frame_002.npy
│   └── ...
└── other/
    ├── frame_001.npy
    ├── frame_002.npy
    └── ...
```

---

## 系統架構流程圖

### 完整資料流程

```
┌─────────────────┐
│   羽球拍感測器    │
│  (Arduino IMU)  │
└────────┬────────┘
         │ BLE (50Hz)
         │ 30 bytes/packet
         ▼
┌─────────────────┐
│   手機App接收    │
│  (BLE Client)   │
│  - 解析資料      │
│  - 緩衝管理      │
└────────┬────────┘
         │
         ├─────────────────┐
         │                 │
         ▼                 ▼
┌─────────────────┐  ┌─────────────────┐
│   本地資料庫     │  │   WiFi上傳      │
│  (SQLite緩存)   │  │   (HTTP/HTTPS)  │
└─────────────────┘  └────────┬────────┘
                              │
                              ▼
                      ┌─────────────────┐
                      │   伺服器資料庫   │
                      │  (MySQL/PostgreSQL)
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │   AI訓練模組     │
                      │  - 資料預處理    │
                      │  - 模型訓練      │
                      │  - 模型部署      │
                      └─────────────────┘
```

### 手機App模組架構

```
┌─────────────────────────────────────┐
│          手機App架構                │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────┐                  │
│  │  BLE Manager │                  │
│  │  - 掃描設備  │                  │
│  │  - 連接管理  │                  │
│  │  - 資料接收  │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ┌──────▼───────┐                  │
│  │ Data Parser  │                  │
│  │  - 解析30bytes│                 │
│  │  - 資料驗證   │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ┌──────▼───────┐                  │
│  │ Calibration  │                  │
│  │  - 零點校正   │                  │
│  │  - 應用校正   │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ├──────┴───────┬──────────────────┤
│  │              │                  │
│  ▼              ▼                  │
│  ┌──────────┐  ┌──────────────┐   │
│  │ Chart     │  │  Firebase    │   │
│  │ Manager   │  │  - Firestore │   │
│  │ - 圖表    │  │  - 批次上傳  │   │
│  │ - 降採樣  │  │  - 錄製模式  │   │
│  └──────────┘  └──────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

---

## 開發注意事項

### BLE 連接注意事項

1. **連接超時處理**：
   - 設定合理的連接超時時間（建議15秒）
   - 連接失敗時提供重試機制

2. **斷線重連機制**：
   - 監聽連接狀態變化
   - 自動重新掃描和連接
   - 顯示連接狀態給使用者

3. **資料接收穩定性**：
   - 檢查接收到的資料長度（必須為30 bytes）
   - 處理資料解析錯誤
   - 記錄錯誤日誌用於除錯

### 網路傳輸注意事項（Firebase Firestore）

1. **網路狀態檢查**：
   - Firebase 會自動處理網路狀態
   - 網路未連接時，資料會暫存在本地（待實作 Room 資料庫）

2. **資料上傳失敗處理**：
   - 目前會在 Logcat 中記錄錯誤
   - 未來可實現重試機制和本地資料庫儲存
   - 定期檢查並重新上傳未成功的資料（待實作）

3. **電池消耗優化**：
   - 批次上傳減少網路請求次數（每 5 秒或 100 筆）
   - 僅在錄製模式下上傳，避免不必要的網路請求
   - 使用 Firebase 的批次寫入功能（未來可優化）

### 資料處理注意事項

1. **時間戳記同步**：
   - 手機接收時間與感測器時間的差異
   - 建議記錄手機本地時間戳記
   - 伺服器端統一使用UTC時間

2. **資料品質控制**：
   - 檢查感測器資料的有效範圍
   - 過濾異常值（如全0或極大值）
   - 驗證時間戳記的連續性

3. **記憶體管理**：
   - 避免在記憶體中累積過多資料
   - 定期清理已處理的資料
   - 使用適當的資料結構大小

---

## 故障排除

### BLE 連接問題

#### 問題1：無法掃描到設備

**可能原因**：
- 感測器未啟動或BLE未廣播
- 手機藍牙未開啟
- 設備距離過遠

**解決方法**：
1. 檢查Arduino程式是否正確上傳
2. 確認感測器LED指示燈狀態
3. 檢查手機藍牙權限
4. 靠近感測器（建議1米內）

#### 問題2：連接後立即斷線

**可能原因**：
- BLE服務UUID不匹配
- 特徵UUID不匹配
- 手機BLE驅動問題

**解決方法**：
1. 檢查UUID是否完全一致（包含大小寫）
2. 確認BLE服務和特徵是否正確發現
3. 嘗試重新啟動手機藍牙
4. 檢查Arduino程式中的BLE設定

#### 問題3：資料接收不穩定

**可能原因**：
- 傳輸頻率過高
- BLE訊號干擾
- 手機處理效能不足

**解決方法**：
1. 降低資料傳輸頻率（修改Arduino程式）
2. 遠離WiFi路由器等干擾源
3. 檢查手機是否有其他BLE連接占用頻寬
4. 優化資料接收處理邏輯

### 資料解析問題

#### 問題1：資料長度錯誤

**症狀**：收到非30 bytes的資料

**解決方法**：
```java
if (data.length != 30) {
    Log.w(TAG, "警告：收到異常長度的資料 " + data.length + " bytes");
    return; // 跳過此筆資料
}
```

#### 問題2：資料值異常

**症狀**：加速度或角速度值超出合理範圍

**解決方法**：
```java
public boolean validateData(IMUData data) {
    // 加速度範圍：-20g ~ +20g（已放寬範圍）
    if (Math.abs(data.accelX) > 20.0f || 
        Math.abs(data.accelY) > 20.0f || 
        Math.abs(data.accelZ) > 20.0f) {
        return false;
    }
    
    // 角速度範圍：-2500 ~ +2500 dps（已放寬範圍）
    if (Math.abs(data.gyroX) > 2500.0f || 
        Math.abs(data.gyroY) > 2500.0f || 
        Math.abs(data.gyroZ) > 2500.0f) {
        return false;
    }
    
    return true;
}
```

### 網路傳輸問題

#### 問題1：上傳失敗

**可能原因**：
- 網路連接不穩定
- 伺服器API錯誤
- 資料格式錯誤

**解決方法**：
1. 實現重試機制
2. 檢查HTTP狀態碼和錯誤訊息
3. 驗證JSON格式是否正確
4. 檢查伺服器日誌

#### 問題2：資料遺失

**可能原因**：
- 上傳失敗但未保存
- 本地資料庫寫入失敗
- 應用程式意外關閉

**解決方法**：
1. 所有資料先存入本地資料庫
2. 上傳成功後才標記為已上傳
3. 定期檢查並重新上傳未成功的資料
4. 使用事務確保資料一致性

---

## 參考資源

### 官方文件

- [Seeed XIAO nRF52840 Sense 文件](https://wiki.seeedstudio.com/XIAO_BLE/)
- [ArduinoBLE 函式庫文件](https://www.arduino.cc/reference/en/libraries/arduinoble/)
- [Android BLE 官方文件](https://developer.android.com/guide/topics/connectivity/bluetooth/ble-overview)
- [MPAndroidChart 文件](https://github.com/PhilJay/MPAndroidChart)
- [Firebase Firestore Android 文件](https://firebase.google.com/docs/firestore/quickstart)
- [BLE 規格文件](https://www.bluetooth.com/specifications/specs/core-specification/)

### 範例程式碼位置

- **Arduino主程式**: `src/main/main.ino`
- **Windows接收程式**: `APP/windows/visualizer/ble_imu_receiver.py`
- **過往專案範例**: `examples/Past_Student_Projects/codes/`

### 開發工具建議

- **BLE掃描工具**: 
  - Android: nRF Connect
  - iOS: LightBlue
- **資料視覺化**: 
  - Python: Matplotlib, Plotly
  - Android: MPAndroidChart v3.1.0
- **API測試**: Postman, curl

---

## 聯絡資訊

如有技術問題，請聯絡專案團隊或查閱專案README文件。

---

**文件版本**: v1.3  
**最後更新**: 2025年11月  
**維護者**: DIID Term Project Team  
**更新內容**: 
- ✅ 更新系統概述：WiFi → Firebase Firestore
- ✅ 移除所有 Flutter/Dart 相關內容，僅保留 Android (Java) 實現
- ✅ 更新零點校正功能：手動觸發，收集 200 筆資料，使用 SharedPreferences + Gson 儲存
- ✅ 更新曲線圖視覺化：MPAndroidChart 實現，6個獨立圖表，50Hz → 10Hz 降採樣
- ✅ 更新 Firebase 資料傳輸：批次上傳（5秒或100筆），錄製模式切換
- ✅ 更新電壓相關技術：校準常數 8.11，讀取頻率每10秒，30筆取平均，雙層濾波器
- ✅ 更新資料解析範例：10-bit 轉 12-bit，正確的電壓計算公式
- ✅ 更新 UI 設計：Material Design 3，狀態卡片，控制按鈕卡片
- ✅ 更新狀態管理：Java 實現範例
- ✅ 更新系統架構流程圖：反映實際實現

