# 🏸 智能羽毛球拍 Android App - 完整需求文件

## 📋 目錄

1. [專案概述](#專案概述)
2. [功能需求清單](#功能需求清單)
3. [UI/UX 設計規範](#uiux-設計規範)
4. [技術架構](#技術架構)
5. [核心功能詳細規格](#核心功能詳細規格)
6. [資料流程設計](#資料流程設計)
7. [開發階段規劃](#開發階段規劃)
8. [待確認事項](#待確認事項)

---

## 專案概述

### 專案目標

開發一個 Android 應用程式，用於連接智能羽毛球拍感測器（nRF52840），接收 IMU 資料，進行零點校正，顯示即時資料和曲線圖，並將資料上傳至 Firebase 進行 AI 訓練和遠端辨識。

### 核心功能

1. **BLE 連接管理** - 連接特定球拍設備（SmartRacket）
2. **零點校正** - 手動校正功能，將感測器資料歸零
3. **即時資料顯示** - 顯示六軸感測器數值
4. **曲線圖視覺化** - 以 100ms 為單位顯示六軸曲線圖
5. **Firebase 資料上傳** - 批次上傳校正後的資料
6. **CSV 本地資料儲存** - 將資料儲存為 CSV 格式，支援 Excel 直接開啟
7. **智能斷線處理** - BLE 斷線時自動停止錄製並清理資源
8. **遠端 AI 辨識** - 接收伺服器辨識結果（5種姿態 + 球速）
9. **時間同步** - 校正時自動同步手機時間至感測器

---

## 功能需求清單

### 1. BLE 連接功能

#### 1.1 設備掃描與連接
- ✅ 自動掃描名為 "SmartRacket" 的 BLE 設備
- ✅ 顯示掃描到的設備列表
- ✅ 點擊設備進行連接
- ✅ 顯示連接狀態（未連接/連接中/已連接）
- ✅ 連接失敗時顯示錯誤訊息
- ✅ 自動重連機制（可選）

#### 1.2 連接狀態管理
- ✅ 即時顯示連接狀態
- ✅ 顯示設備電量（從感測器資料中讀取）
- ✅ 斷線時自動提示
- ✅ 手動斷開連接功能

### 2. 零點校正功能

#### 2.1 校正觸發
- ✅ 提供「零點校正」按鈕
- ✅ 校正前提示使用者將球拍靜止平置
- ✅ 校正觸發時自動同步手機時間到感測器
- ✅ 校正過程中顯示進度

#### 2.2 校正邏輯
- **加速度計校正**：
  - X 軸：計算平均值作為偏移量，後續資料減去此偏移量
  - Y 軸：計算平均值作為偏移量，後續資料減去此偏移量
  - Z 軸：計算平均值後減去 1g（重力加速度），後續資料減去此偏移量
- **陀螺儀校正**：
  - X/Y/Z 軸：計算平均值作為偏移量，後續資料減去此偏移量

#### 2.3 校正資料儲存
- ✅ 校正值儲存在本地 SharedPreferences
- ✅ App 啟動時自動載入校正值
- ✅ 校正值可手動清除（重新校正）

#### 2.4 校正資料應用
- ✅ 所有接收到的資料自動應用校正值
- ✅ 顯示的資料為校正後的數值
- ✅ 上傳至 Firebase 的資料為校正後的數值

### 3. 即時資料顯示

#### 3.1 數值顯示
- ✅ 顯示加速度三軸（X, Y, Z）
- ✅ 顯示角速度三軸（X, Y, Z）
- ✅ 顯示電壓值
- ✅ 顯示時間戳記
- ✅ 數值更新頻率：50Hz（每 20ms 更新一次）

#### 3.2 顯示格式
- 加速度：單位 g，顯示 3 位小數
- 角速度：單位 dps，顯示 2 位小數
- 電壓：單位 V，顯示 3 位小數（濾波後）和原始值
  - 格式：`電壓: X.XXX V (原始: X.XXX V)`
  - 使用雙層濾波器平滑讀數（移動平均 + EMA）
- 時間戳記：顯示毫秒數

#### 3.3 電壓監控與濾波（已實現）
- **電壓讀取頻率**：每 10 秒更新一次（Arduino 端）
- **讀取方式**：每次讀取 30 筆電壓值並取平均
- **濾波器**：
  - 第一層：移動平均（100 個樣本，約 2 秒）
  - 第二層：指數移動平均（EMA，alpha = 0.15）
- **校準常數**：8.11（根據實際測量值調整）
- **異常檢測**：自動過濾異常值（< 0.1V 或 > 5.0V）

### 4. 曲線圖顯示（已實現）

#### 4.1 圖表規格
- **時間範圍**：最近 5 秒的資料（約 50 個資料點）
- **更新頻率**：每 100ms 更新一次（降採樣，從 50Hz 資料中每 5 筆取 1 筆）
- **圖表數量**：6 個獨立圖表（加速度 X/Y/Z，角速度 X/Y/Z）
- **圖表類型**：折線圖（Line Chart，使用 MPAndroidChart v3.1.0）
- **資料來源**：校正後的 IMU 資料

#### 4.2 圖表設計（已實現）
- 每個圖表獨立顯示（高度 150dp）
- X 軸：時間（0-5 秒），自動縮放
- Y 軸：數值範圍
  - 加速度：-20g ~ +20g（放寬範圍以容納揮拍動作）
  - 角速度：-2500 dps ~ +2500 dps（放寬範圍以容納快速揮拍）
- 不同軸使用不同顏色區分：
  - 加速度 X：藍色 #2196F3
  - 加速度 Y：綠色 #4CAF50
  - 加速度 Z：紫色 #9C27B0
  - 角速度 X：橙色 #FF9800
  - 角速度 Y：紅色 #F44336
  - 角速度 Z：青色 #00BCD4
- 圖表樣式：Cubic Bezier 平滑曲線、網格線、軸標籤
- 圖表平滑滾動更新（自動移除舊資料點）

#### 4.3 圖表互動（待實作）
- 可切換顯示/隱藏特定軸
- 可暫停/繼續更新
- 可清除圖表資料

#### 4.4 實現細節
- **ChartManager.java**：管理 6 個圖表實例
- **資料降採樣**：使用資料緩衝區，每 100ms 取最新資料點
- **更新機制**：使用 Handler 在主線程定時更新圖表
- **性能優化**：限制資料點數（最多 50 個），自動移除舊資料

### 5. Firebase 資料上傳

#### 5.1 上傳模式
- **測試/錄製模式**：僅在此模式下上傳資料
- **一般模式**：不上傳資料（僅顯示）

#### 5.2 上傳策略
- **批次上傳**：
  - 每 5 秒上傳一次，或
  - 累積 100 筆資料後上傳
  - 兩者條件任一滿足即觸發上傳

#### 5.3 上傳資料格式
```json
{
  "device_id": "SmartRacket_001",
  "session_id": "session_20241123_001",
  "timestamp": 1234567890,
  "accelX": 0.123,
  "accelY": -0.456,
  "accelZ": 0.789,
  "gyroX": 12.34,
  "gyroY": -56.78,
  "gyroZ": 90.12,
  "voltage": 3.65,
  "received_at": 1234567890123,
  "calibrated": true
}
```

#### 5.4 Firebase 結構
- **Collection**: `imu_data`
- **Document ID**: 自動生成
- **Fields**: 如上所示

#### 5.5 離線處理
- ✅ 上傳失敗時儲存至本地 SQLite
- ✅ 網路恢復時自動重新上傳
- ✅ 顯示上傳狀態（成功/失敗/待上傳）

### 6. CSV 本地資料儲存

#### 6.1 功能概述
- ✅ 將 IMU 資料儲存為 CSV 格式到外部儲存
- ✅ 時間戳記格式：`yyyy/MM/dd HH:mm:ss.SSS`（Excel 友好格式）
- ✅ 自動檔案分檔：每 5 分鐘自動切換檔案
- ✅ 批次寫入：每 2 秒批次寫入一次，提高效率

#### 6.2 CSV 檔案格式
- **欄位**：`timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ`
- **時間戳記格式**：`2025/12/05 23:34:51.123`
- **優點**：Excel 可以直接識別，無需手動轉換

#### 6.3 檔案命名規則
- **第一個檔案**：使用第一筆資料的接收時間命名
  - 格式：`imu_data_YYYYMMDD_HHmmss.csv`
  - 範例：`imu_data_20251205_233451.csv`
- **後續檔案**：使用 5 分鐘倍數邊界時間命名
  - 格式：`imu_data_YYYYMMDD_HHmmss.csv`（時間對齊到 5 分鐘倍數）
  - 範例：
    - `imu_data_20251205_233500.csv`（23:35:00 開始）
    - `imu_data_20251205_234000.csv`（23:40:00 開始）

#### 6.4 自動檔案分檔
- **分檔間隔**：5 分鐘（300,000 毫秒）
- **觸發條件**：當資料的 `receivedAt` 時間跨越 5 分鐘倍數邊界時自動切換檔案
- **範例**：從 23:34:51 錄製到 23:40:00，會產生 3 個檔案

#### 6.5 儲存位置
- **目錄**：外部儲存應用專屬目錄 `/Android/data/com.example.smartbadmintonracket/files/IMU_Data/`
- **權限**：不需要特殊權限（使用應用專屬目錄）

#### 6.6 實際實現
- **CSVManager.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/csv/CSVManager.java`

### 7. BLE 斷線處理

#### 7.1 斷線檢測
- ✅ 使用 Android BLE 協議的 `onConnectionStateChange` 回調檢測連接狀態
- ✅ 不會因為幾毫秒的資料接收延遲就判定斷線（使用 BLE 連接監督超時機制）

#### 7.2 斷線處理流程
- ✅ **資源清理**：
  - 關閉 GATT 連接
  - 重置資料緩衝區
  - 重置時間同步狀態
  - 清理超時回調
- ✅ **自動停止錄製**：
  - 停止 Firebase 錄製
  - 停止 CSV 錄製
  - 關閉 CSV 檔案（確保所有資料都已寫入）
- ✅ **UI 更新**：
  - 更新連接狀態顯示
  - 更新錄製按鈕狀態
  - 顯示提示訊息：「設備已斷線，錄製已自動停止」
  - 停止圖表更新
  - 重置電壓濾波器

#### 7.3 常見斷線原因
- 物理斷線（電線斷裂、設備移動超出範圍）
- 電池耗盡（設備自動關機）
- 手動斷開（使用者主動斷開連接）
- BLE 協議層斷線（連接監督超時）

#### 7.4 實際實現
- **BLEManager.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/BLEManager.java`
  - `onConnectionStateChange()` 方法
- **MainActivity.java**：`APP/android/app/src/main/java/com/example/smartbadmintonracket/MainActivity.java`
  - `onDisconnected()` 回調處理

### 8. 遠端 AI 辨識

#### 6.1 動作偵測
- ✅ 偵測揮拍動作（根據加速度或角速度峰值）
- ✅ 偵測到動作時觸發辨識請求
- ✅ 使用 40 筆資料作為一個分析窗口

#### 6.2 辨識請求
- **API 端點**：`POST /api/v1/recognize`
- **請求格式**：
```json
{
  "device_id": "SmartRacket_001",
  "data_frame": [
    { "timestamp": 1234567890, "accelX": 0.123, ... },
    ... (40筆資料)
  ]
}
```

#### 6.3 辨識結果
- **5 種姿態分類**：
  - `smash` - 殺球
  - `drive` - 抽球
  - `toss` - 挑球
  - `drop` - 吊球
  - `other` - 其他
- **球速計算**（僅殺球）：
  - 根據加速度峰值計算
  - 公式建議：`speed = sqrt(accel_peak) * k`（k 為校正係數）
  - 顯示單位：km/h

#### 6.4 結果顯示
- ✅ 顯示辨識結果（姿態名稱）
- ✅ 顯示信心度（百分比）
- ✅ 顯示球速（僅殺球時）
- ✅ 結果凍結顯示 3-5 秒
- ✅ 動畫效果（彈出、淡入）

---

## UI/UX 設計規範

### 設計風格

- **設計語言**：Material Design 3
- **色彩主題**：
  - 主色調：深藍色（#1976D2）
  - 輔助色：橙色（#FF9800）
  - 背景色：淺灰色（#F5F5F5）
  - 文字色：深灰色（#212121）
- **字體**：Roboto（系統預設）
- **圓角**：12dp（卡片）、8dp（按鈕）

### 主介面設計

#### 1. 頂部狀態欄
```
┌─────────────────────────────────────┐
│  🏸 Smart Racket Analyzer          │
│  📶 SmartRacket  ✓ 已連接          │
│  🔋 電量: ████████░░ 80%           │
└─────────────────────────────────────┘
```

#### 2. 連接控制區
```
┌─────────────────────────────────────┐
│  [掃描設備]  [連接]  [斷開]          │
│  [零點校正]                          │
└─────────────────────────────────────┘
```

#### 3. 即時資料顯示區
```
┌─────────────────────────────────────┐
│  即時感測器資料                       │
│  ┌─────────────────────────────┐  │
│  │ 加速度 (g)                    │  │
│  │ X:  0.123  Y: -0.456  Z: 0.789│  │
│  │                              │  │
│  │ 角速度 (dps)                  │  │
│  │ X: 12.34  Y: -56.78  Z: 90.12│  │
│  │                              │  │
│  │ 電壓: 3.65 V                  │  │
│  └─────────────────────────────┘  │
└─────────────────────────────────────┘
```

#### 4. 曲線圖顯示區（可滾動）
```
┌─────────────────────────────────────┐
│  加速度 X 軸                         │
│  ┌─────────────────────────────┐  │
│  │     ▁▂▃▅▇█▇▅▃▂▁          │  │
│  └─────────────────────────────┘  │
│                                     │
│  加速度 Y 軸                         │
│  ┌─────────────────────────────┐  │
│  │     ▁▂▃▅▇█▇▅▃▂▁          │  │
│  └─────────────────────────────┘  │
│  ... (共6個圖表)                    │
└─────────────────────────────────────┘
```

#### 5. 辨識結果顯示區（僅在有結果時顯示）
```
┌─────────────────────────────────────┐
│  🎾 揮拍識別結果                      │
│  ┌─────────────────────────────┐  │
│  │                             │  │
│  │        [殺球]               │  │
│  │                             │  │
│  │      信心度: 85%            │  │
│  │      球速: 120 km/h         │  │
│  │                             │  │
│  └─────────────────────────────┘  │
└─────────────────────────────────────┘
```

#### 6. 控制按鈕區
```
┌─────────────────────────────────────┐
│  [開始錄製]  [停止錄製]  [設定]      │
└─────────────────────────────────────┘
```

### 頁面架構

#### 主頁面（MainActivity）
- 連接狀態顯示
- 即時資料顯示
- 曲線圖顯示
- 辨識結果顯示
- 控制按鈕

#### 設定頁面（SettingsActivity）
- 零點校正按鈕
- Firebase 設定
- 上傳模式切換
- 關於資訊

### 動畫效果

#### 1. 連接動畫
- 連接中：旋轉動畫
- 連接成功：綠色勾選動畫
- 連接失敗：紅色 X 動畫

#### 2. 資料更新動畫
- 數值更新：淡入效果
- 圖表更新：平滑滾動

#### 3. 辨識結果動畫
- 結果出現：彈出 + 縮放動畫
- 結果消失：淡出動畫

---

## 技術架構

### 技術棧

- **開發語言**：Java
- **最低 SDK**：API 26 (Android 8.0)
- **目標 SDK**：API 36 (Android 14)
- **架構模式**：MVP 或 MVVM（建議 MVVM）

### 主要依賴庫

```gradle
dependencies {
    // Android 核心庫
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    
    // BLE（使用 Android 原生 API，無需額外依賴）
    
    // Firebase
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-analytics'
    
    // HTTP 請求（用於遠端辨識）
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    implementation 'com.google.code.gson:gson:2.10.1'
    
    // 圖表庫
    implementation 'com.github.PhilJay:MPAndroidChart:v3.1.0'
    
    // 本地資料庫
    implementation 'androidx.room:room-runtime:2.6.1'
    annotationProcessor 'androidx.room:room-compiler:2.6.1'
    
    // 資料綁定
    implementation 'androidx.lifecycle:lifecycle-viewmodel:2.6.2'
    implementation 'androidx.lifecycle:lifecycle-livedata:2.6.2'
}
```

### 專案結構

```
app/src/main/java/com/example/smartbadmintonracket/
├── MainActivity.java                    # 主活動
├── SettingsActivity.java                # 設定頁面
│
├── ble/
│   ├── BLEManager.java                 # BLE 管理器（已存在）
│   ├── IMUData.java                    # 資料模型（已存在）
│   └── IMUDataParser.java              # 資料解析器（已存在）
│
├── calibration/
│   ├── CalibrationManager.java         # 校正管理器
│   └── CalibrationData.java           # 校正資料模型
│
├── chart/
│   ├── ChartManager.java               # 圖表管理器
│   └── ChartView.java                  # 自訂圖表視圖
│
├── firebase/
│   ├── FirebaseManager.java            # Firebase 管理器
│   └── DataUploader.java               # 資料上傳器
│
├── csv/
│   └── CSVManager.java                  # CSV 檔案管理器（本地儲存）
│
├── recognition/
│   ├── RecognitionManager.java         # 辨識管理器
│   ├── ActionDetector.java             # 動作偵測器
│   └── RecognitionResult.java          # 辨識結果模型
│
├── database/
│   ├── AppDatabase.java                # Room 資料庫
│   ├── IMUDataDao.java                 # 資料存取物件
│   └── IMUDataEntity.java              # 資料實體
│
└── utils/
    ├── SharedPreferencesHelper.java    # SharedPreferences 輔助類
    └── NetworkUtils.java               # 網路工具類
```

---

## 核心功能詳細規格

### 1. 零點校正功能

#### 校正流程

```
1. 使用者點擊「零點校正」按鈕
2. 顯示提示：「請將球拍靜止平置，點擊確定開始校正」
3. 使用者確認後，開始收集資料
4. 收集 200 筆資料（約 4 秒，50Hz * 4秒）
5. 計算各軸平均值
6. 計算校正偏移量：
   - accelX_offset = mean(accelX)
   - accelY_offset = mean(accelY)
   - accelZ_offset = mean(accelZ) - 1.0  // 減去重力
   - gyroX_offset = mean(gyroX)
   - gyroY_offset = mean(gyroY)
   - gyroZ_offset = mean(gyroZ)
7. 同步當前時間到感測器（時間同步）
8. 儲存校正值至 SharedPreferences
9. 顯示「校正完成」訊息
```

#### 校正資料模型

```java
public class CalibrationData {
    public float accelXOffset;
    public float accelYOffset;
    public float accelZOffset;
    public float gyroXOffset;
    public float gyroYOffset;
    public float gyroZOffset;
    public long calibrationTime;  // 校正時間戳記
}
```

#### 校正應用邏輯

```java
public IMUData applyCalibration(IMUData rawData, CalibrationData calData) {
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
```

### 2. 曲線圖顯示功能

#### 資料降採樣

```java
// 從 50Hz 資料降採樣到 10Hz（每 100ms 一點）
// 每 5 筆資料取 1 筆（50Hz / 5 = 10Hz）
private List<IMUData> downsampleData(List<IMUData> data, int factor) {
    List<IMUData> downsampled = new ArrayList<>();
    for (int i = 0; i < data.size(); i += factor) {
        downsampled.add(data.get(i));
    }
    return downsampled;
}
```

#### 圖表資料管理

```java
// 維持最近 5 秒的資料（10Hz * 5秒 = 50 點）
private static final int MAX_DATA_POINTS = 50;

private void updateChart(IMUData data) {
    chartData.add(data);
    
    // 保持資料點數量
    if (chartData.size() > MAX_DATA_POINTS) {
        chartData.remove(0);
    }
    
    // 更新圖表
    chartView.updateData(chartData);
}
```

#### 圖表視圖實現

使用 MPAndroidChart 庫實現 6 個獨立的 LineChart：

```java
public class ChartView extends LinearLayout {
    private LineChart accelXChart;
    private LineChart accelYChart;
    private LineChart accelZChart;
    private LineChart gyroXChart;
    private LineChart gyroYChart;
    private LineChart gyroZChart;
    
    // 初始化圖表
    // 更新資料
    // 設定樣式
}
```

### 3. Firebase 資料上傳

#### 上傳管理器

```java
public class FirebaseManager {
    private Firestore db;
    private List<IMUData> pendingData;
    private Handler uploadHandler;
    private static final int UPLOAD_INTERVAL = 5000;  // 5秒
    private static final int BATCH_SIZE = 100;        // 100筆
    
    // 初始化 Firebase
    // 批次上傳邏輯
    // 離線處理
}
```

#### 上傳觸發條件

```java
private void checkUploadCondition() {
    long currentTime = System.currentTimeMillis();
    boolean timeCondition = (currentTime - lastUploadTime) >= UPLOAD_INTERVAL;
    boolean sizeCondition = pendingData.size() >= BATCH_SIZE;
    
    if (timeCondition || sizeCondition) {
        uploadBatch();
    }
}
```

#### Firebase 資料結構

```
firestore/
└── imu_data/
    ├── {auto_id}/
    │   ├── device_id: "SmartRacket_001"
    │   ├── session_id: "session_20241123_001"
    │   ├── timestamp: 1234567890
    │   ├── accelX: 0.123
    │   ├── accelY: -0.456
    │   ├── accelZ: 0.789
    │   ├── gyroX: 12.34
    │   ├── gyroY: -56.78
    │   ├── gyroZ: 90.12
    │   ├── voltage: 3.65
    │   ├── received_at: 1234567890123
    │   ├── calibrated: true
    │   └── uploaded_at: Timestamp
    └── ...
```

### 4. 遠端 AI 辨識

#### 動作偵測

```java
public class ActionDetector {
    private static final double ACCEL_THRESHOLD = 5.0;  // 5g 閾值
    private static final double GYRO_THRESHOLD = 500.0; // 500 dps 閾值
    
    public boolean detectAction(IMUData data) {
        // 計算加速度總量
        double accelMagnitude = Math.sqrt(
            data.accelX * data.accelX +
            data.accelY * data.accelY +
            data.accelZ * data.accelZ
        );
        
        // 計算角速度總量
        double gyroMagnitude = Math.sqrt(
            data.gyroX * data.gyroX +
            data.gyroY * data.gyroY +
            data.gyroZ * data.gyroZ
        );
        
        return accelMagnitude > ACCEL_THRESHOLD || 
               gyroMagnitude > GYRO_THRESHOLD;
    }
}
```

#### 辨識請求

```java
public class RecognitionManager {
    private static final String API_URL = "https://your-server.com/api/v1/recognize";
    
    public void requestRecognition(List<IMUData> dataFrame) {
        // 準備請求資料
        JSONObject request = new JSONObject();
        request.put("device_id", "SmartRacket_001");
        request.put("data_frame", convertToJSONArray(dataFrame));
        
        // 發送 HTTP POST 請求
        // 解析回應
        // 更新 UI
    }
}
```

#### 球速計算建議

```java
public double calculateSmashSpeed(List<IMUData> dataFrame) {
    // 找出加速度峰值
    double maxAccel = 0;
    for (IMUData data : dataFrame) {
        double accelMagnitude = Math.sqrt(
            data.accelX * data.accelX +
            data.accelY * data.accelY +
            data.accelZ * data.accelZ
        );
        if (accelMagnitude > maxAccel) {
            maxAccel = accelMagnitude;
        }
    }
    
    // 簡化公式：speed = sqrt(accel_peak) * k
    // k 為經驗係數，建議值：15-20
    double k = 18.0;  // 可根據實際測試調整
    double speed = Math.sqrt(maxAccel) * k;
    
    // 轉換為 km/h（如果需要的話）
    return speed;  // 單位：km/h（假設）
}
```

**注意**：球速計算公式需要根據實際測試資料進行調整。建議的計算方式：
- 方法1：根據加速度峰值 `speed = sqrt(peak_accel) * k`
- 方法2：根據加速度積分 `speed = integral(accel) * dt * k`
- 方法3：根據角速度和球拍長度 `speed = angular_velocity * racket_length * k`

---

## 資料流程設計

### 完整資料流程

```
┌─────────────────┐
│  nRF52840 感測器 │
│  發送 30 bytes  │
└────────┬────────┘
         │ BLE (50Hz)
         ▼
┌─────────────────┐
│  BLEManager     │
│  - 接收資料      │
│  - 解析 30 bytes │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ CalibrationMgr  │
│  - 應用校正值    │
└────────┬────────┘
         │
         ├─────────────────┬─────────────────┐
         ▼                  ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  UI 更新      │  │  圖表更新    │  │  資料緩衝    │
│  - 顯示數值    │  │  - 降採樣    │  │  - 40筆窗口  │
└──────────────┘  │  - 更新圖表  │  └──────┬───────┘
                  └──────────────┘         │
                                           ▼
                                  ┌──────────────┐
                                  │ ActionDetect │
                                  │  - 偵測動作  │
                                  └──────┬───────┘
                                         │
                                         ▼
                                  ┌──────────────┐
                                  │ Recognition  │
                                  │  - 發送請求  │
                                  └──────┬───────┘
                                         │
                                         ▼
                                  ┌──────────────┐
                                  │  伺服器辨識   │
                                  │  - 返回結果  │
                                  └──────┬───────┘
                                         │
                                         ▼
                                  ┌──────────────┐
                                  │  UI 顯示結果  │
                                  └──────────────┘

         │
         ▼
┌─────────────────┐
│  Data Buffer    │
│  - 累積資料      │
└────────┬────────┘
         │
         ▼ (每5秒或100筆)
┌─────────────────┐
│ FirebaseManager │
│  - 批次上傳      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Firebase       │
│  Firestore      │
└─────────────────┘
```

---

## 開發階段規劃

### 階段一：基礎功能（優先）

1. ✅ BLE 連接功能（已完成）
2. ⏳ 零點校正功能
3. ⏳ 即時資料顯示
4. ⏳ 基礎 UI 設計

### 階段二：視覺化功能

1. ⏳ 曲線圖顯示（6個獨立圖表）
2. ⏳ 圖表資料降採樣
3. ⏳ 圖表樣式優化

### 階段三：資料上傳

1. ⏳ Firebase 整合
2. ⏳ 批次上傳邏輯
3. ⏳ 離線資料處理
4. ⏳ 上傳狀態顯示

### 階段四：AI 辨識

1. ⏳ 動作偵測
2. ⏳ 遠端辨識請求
3. ⏳ 辨識結果顯示
4. ⏳ 球速計算

### 階段五：UI 優化

1. ⏳ 時尚感 UI 設計
2. ⏳ 動畫效果
3. ⏳ 響應式佈局
4. ⏳ 深色模式支援（可選）

---

## 待確認事項

### 1. Firebase 設定
- [x] Firebase 專案：需要建立（參考 `docs/Firebase_設定教學.md`）📚
- [ ] Firebase 配置檔案（google-services.json）：待建立專案後下載
- [ ] Firestore 資料庫規則：待建立資料庫後設定

### 2. 伺服器 API
- [x] 辨識 API 端點：`POST /api/v1/recognize`（參考 `docs/伺服器API_規劃與設計.md`）📚
- [ ] API 認證方式：建議先不使用，之後可加入 API Key
- [x] 辨識結果格式：已定義（參考需求文件）

### 3. 球速計算
- [x] 球速計算公式需要根據實際測試資料調整 ✅
- [x] 球速單位：km/h ✅
- [x] 需要根據實際測試資料校正係數 ✅

### 4. 測試/錄製模式
- [x] 切換方式：使用狀態指示器 + 切換按鈕（見下方設計建議）✅
- [x] 錄製模式：有開始/停止按鈕 ✅
- [x] session_id：需要標記，格式為 `session_YYYYMMDD_HHMMSS` ✅

### 5. UI 設計細節
- [ ] 主色調偏好？
- [ ] 圖表顏色配置？
- [ ] 是否需要深色模式？

---

## 技術細節補充

### 零點校正注意事項

**重要**：加速度計 Z 軸在靜止平置時應該約為 1g（重力加速度），不是 0。校正時需要：
- 計算 Z 軸平均值
- 減去 1.0g（重力）
- 將結果作為偏移量

**校正驗證**：
- 校正後，靜止狀態下：
  - 加速度 X/Y/Z 應接近 0
  - 陀螺儀 X/Y/Z 應接近 0

### 曲線圖性能優化

- 使用 `RecyclerView` 或 `ViewPager` 顯示多個圖表
- 圖表更新使用 `Handler.post()` 避免阻塞主線程
- 資料降採樣在背景線程進行
- 限制圖表資料點數量（50 點 = 5 秒）

### Firebase 上傳優化

- 使用 `WorkManager` 處理背景上傳
- 實現重試機制（最多 3 次）
- 上傳失敗時儲存至本地 SQLite
- 定期檢查並重新上傳失敗的資料

### 網路請求處理

- 使用 `OkHttp` 進行 HTTP 請求
- 實現請求超時（建議 10 秒）
- 處理網路錯誤和伺服器錯誤
- 顯示網路狀態給使用者

---

**文件版本**: v1.0  
**建立日期**: 2024年11月  
**維護者**: DIID Term Project Team

