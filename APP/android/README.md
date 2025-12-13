# 智能羽毛球拍 IMU 接收器 - Android App

## 📱 專案說明

這是一個 Android 應用程式，用於連接 nRF52840 感測器並接收 IMU（慣性測量單元）資料。

## ✨ 功能特色

- ✅ BLE 藍牙低功耗連接
- ✅ 自動掃描並連接 SmartRacket 設備
- ✅ 即時接收 IMU 資料（50Hz，每 20ms 一筆）
- ✅ 顯示加速度、角速度、電壓等資料
- ✅ **零點校正功能**：手動觸發校正，收集 200 筆資料計算偏移量（App 端處理，Z 軸自動補償 1g）
- ✅ **時間同步**：校正時自動將手機時間同步至感測器
- ✅ **即時圖表顯示**：6 個獨立圖表（加速度 X/Y/Z，角速度 X/Y/Z），使用 MPAndroidChart
- ✅ **資料降採樣**：圖表更新頻率 10Hz（每 100ms），維持 5 秒資料窗口
- ✅ **電壓濾波**：雙層濾波器（移動平均 + EMA）平滑電壓讀數
- ✅ **Firebase 資料上傳**：批次上傳至 Firestore（5 秒或 100 筆資料）
- ✅ **錄製模式**：可切換錄製模式控制資料上傳
- ✅ 資料驗證和錯誤處理
- ✅ **Material Design 3** 現代化 UI 設計

## 🔧 技術規格

### 硬體需求
- Android 8.0 (API 26) 或更高版本
- 支援 BLE 的 Android 設備
- nRF52840 感測器（設備名稱：SmartRacket）

### BLE 設定
- **設備名稱**: SmartRacket
- **服務 UUID**: `0769bb8e-b496-4fdd-b53b-87462ff423d0`
- **特徵 UUID**: `8ee82f5b-76c7-4170-8f49-fff786257090`
- **資料格式**: 30 bytes（時間戳 4 + 加速度 12 + 陀螺儀 12 + 電壓 2）
- **傳輸頻率**: 50Hz（每 20ms 一筆）

### 主要依賴
- **MPAndroidChart v3.1.0**：圖表顯示
- **Firebase Firestore**：雲端資料庫
- **Gson 2.10.1**：JSON 序列化（校正資料儲存）
- **Material Design 3**：現代化 UI 設計

## 📦 專案結構

```
app/src/main/
├── java/com/example/smartbadmintonracket/
│   ├── MainActivity.java          # 主活動，處理 UI 和整體協調
│   ├── BLEManager.java            # BLE 管理器，處理掃描、連接、資料接收
│   ├── IMUData.java               # IMU 資料模型類
│   ├── IMUDataParser.java         # 資料解析器，將 30 bytes 解析為 IMUData
│   ├── calibration/               # 零點校正模組
│   │   ├── CalibrationManager.java    # 校正管理器
│   │   ├── CalibrationData.java       # 校正資料模型
│   │   └── CalibrationStorage.java    # 校正資料儲存（SharedPreferences + Gson）
│   ├── chart/                     # 圖表顯示模組
│   │   └── ChartManager.java     # 圖表管理器（MPAndroidChart）
│   ├── filter/                    # 資料濾波模組
│   │   └── VoltageFilter.java     # 電壓濾波器（移動平均 + EMA）
│   └── firebase/                  # Firebase 上傳模組
│       └── FirebaseManager.java   # Firebase Firestore 管理器
├── res/
│   ├── layout/
│   │   └── activity_main.xml      # 主介面佈局（Material Design 3）
│   ├── values/
│   │   ├── colors.xml             # 顏色定義
│   │   └── themes.xml             # Material Design 3 主題
│   └── drawable/                  # 狀態指示器圖示
└── AndroidManifest.xml            # 應用程式清單（包含 BLE、網路權限）
```

## 🚀 使用方式

### 1. 編譯和安裝

1. 使用 Android Studio 開啟專案
2. 等待 Gradle 同步完成
3. 連接 Android 設備或啟動模擬器（需支援 BLE）
4. 點擊「Run」按鈕編譯並安裝應用程式

### 2. 使用應用程式

1. **開啟應用程式**
   - 首次開啟時會請求 BLE 相關權限，請允許所有權限

2. **連接感測器**
   - 確保 nRF52840 感測器已啟動並正在廣播
   - 點擊「掃描並連接」按鈕
   - 應用程式會自動掃描並連接名為 "SmartRacket" 的設備
   - 連接成功後，狀態會顯示為「已連接」（綠色）

3. **查看資料**
   - 連接成功後，應用程式會自動開始接收資料
   - 畫面會即時顯示：
     - 連接狀態（綠色圓點 = 已連接）
     - 時間戳記
     - 加速度（X, Y, Z 軸，單位：g）
     - 角速度（X, Y, Z 軸，單位：dps）
     - 電壓（單位：V，顯示濾波後和原始值）
     - 接收資料總數
     - 最新一筆完整資料
   - **即時圖表**：6 個獨立圖表顯示各軸資料的即時波形（5 秒窗口）

4. **零點校正**
   - 點擊「零點校正」按鈕
   - 將球拍靜止平置在平坦表面上
   - 保持不動約 4 秒（收集 200 筆資料）
   - 校正時會自動執行時間同步
   - 校正完成後，所有後續資料會自動應用校正值
   - 校正值會儲存在本地，App 重啟後仍然有效

5. **錄製模式**
   - 點擊「開始錄製」按鈕啟用錄製模式
   - 錄製模式下，資料會批次上傳至 Firebase Firestore
   - 上傳條件：每 5 秒或累積 100 筆資料
   - 點擊「停止錄製」可停止資料上傳

6. **斷開連接**
   - 點擊「斷開連接」按鈕即可斷開 BLE 連接

## 📊 資料格式

### 接收的資料結構

每筆資料包含以下資訊：

| 欄位      | 類型  | 單位 | 說明           |
| --------- | ----- | ---- | -------------- |
| timestamp | long  | 毫秒 | 感測器時間戳記 |
| accelX    | float | g    | X軸加速度      |
| accelY    | float | g    | Y軸加速度      |
| accelZ    | float | g    | Z軸加速度      |
| gyroX     | float | dps  | X軸角速度      |
| gyroY     | float | dps  | Y軸角速度      |
| gyroZ     | float | dps  | Z軸角速度      |
| voltage   | float | V    | 電池電壓       |

### 資料驗證

應用程式會自動驗證接收到的資料：
- 加速度範圍：-20g ~ +20g（已放寬範圍）
- 角速度範圍：-2500 ~ +2500 dps（已放寬範圍）
- 電壓範圍：2.5V ~ 4.5V（電池正常範圍）

超出範圍的資料會被過濾，不會顯示在畫面上。

### 電壓讀取與濾波

- **Arduino 端**：每 10 秒讀取一次，每次讀取 30 筆樣本並取平均
- **Android 端**：雙層濾波器
  - 第一層：移動平均（100 個樣本，約 2 秒）
  - 第二層：指數移動平均（EMA，alpha = 0.15）
- **電壓計算公式**：`V_BAT = RESULT × 8.11 / 4096`
  - RESULT：12-bit ADC 值（0-4095）
  - 校準常數：8.11（根據實際測量值調整）

## 🔍 故障排除

### 問題1：無法掃描到設備

**可能原因**：
- 藍牙未開啟
- 感測器未啟動或未廣播
- 設備距離過遠

**解決方法**：
1. 檢查手機藍牙是否已開啟
2. 確認感測器已正確上傳程式並啟動
3. 靠近感測器（建議 1 米內）
4. 檢查 AndroidManifest.xml 中的權限是否正確設定

### 問題2：連接後立即斷線

**可能原因**：
- UUID 不匹配
- 服務或特徵未正確發現

**解決方法**：
1. 確認感測器的 UUID 與應用程式中的 UUID 一致
2. 檢查 Logcat 日誌查看詳細錯誤訊息
3. 重新啟動感測器和應用程式

### 問題3：接收不到資料

**可能原因**：
- 通知未正確啟用
- 資料格式錯誤

**解決方法**：
1. 檢查 Logcat 日誌
2. 確認感測器正在發送資料（可透過串列埠監控確認）
3. 檢查資料長度是否為 30 bytes

## 📝 開發說明

### 權限說明

應用程式需要以下權限：

- `BLUETOOTH_SCAN`: 掃描 BLE 設備
- `BLUETOOTH_CONNECT`: 連接 BLE 設備
- `ACCESS_FINE_LOCATION`: Android 12 以下需要（BLE 掃描要求）
- `ACCESS_COARSE_LOCATION`: Android 12 以下需要
- `INTERNET`: 網路連接（Firebase 上傳）
- `ACCESS_NETWORK_STATE`: 檢查網路狀態

### 主要類別說明

#### BLEManager
- 處理所有 BLE 相關操作
- 提供掃描、連接、斷開連接功能
- 透過回調接口通知連接狀態和資料接收
- 處理資料分片和重組

#### IMUDataParser
- 解析 30 bytes 的二進位資料
- 使用 Little-Endian 位元組順序
- 驗證資料有效性
- 處理 10-bit 到 12-bit ADC 轉換
- 計算電壓值（使用校準常數 8.11）

#### CalibrationManager
- 管理零點校正流程
- 收集 200 筆資料計算偏移量
- 應用校正值到所有接收資料
- 使用 SharedPreferences + Gson 儲存校正資料

#### ChartManager
- 管理 6 個獨立圖表（MPAndroidChart）
- 實現資料降採樣（50Hz → 10Hz）
- 維持 5 秒資料窗口（50 個資料點）
- 每 100ms 更新一次圖表

#### VoltageFilter
- 雙層濾波器平滑電壓讀數
- 移動平均（100 個樣本）
- 指數移動平均（EMA，alpha = 0.15）
- 過濾異常值

#### FirebaseManager
- 管理 Firebase Firestore 資料上傳
- 批次上傳（5 秒或 100 筆資料）
- 錄製模式控制
- 上傳統計和錯誤處理

#### MainActivity
- 管理 UI 更新
- 處理使用者互動
- 協調所有模組（BLE、校正、圖表、Firebase、濾波）
- 在校正時觸發時間同步功能

## 🔄 後續開發建議

1. **資料儲存**
   - 可添加 Room 資料庫儲存歷史資料（目前 Firebase 上傳失敗時僅記錄日誌）
   - 支援匯出 CSV 或 JSON 格式
   - 實現離線資料緩存和重試機制

2. **資料視覺化**
   - ✅ 即時波形圖顯示（已實現）
   - 3D 姿態視覺化（待實現）
   - 結果動畫效果（待實現）

3. **Firebase 優化**
   - ✅ 批次上傳至 Firestore（已實現）
   - 實現批次寫入優化（目前為逐筆上傳）
   - 添加上傳進度顯示

4. **AI 分析**
   - 整合 TensorFlow Lite 或遠端 API
   - 即時球路識別（5 種球路：smash, drive, toss, drop, other）
   - 殺球球速計算

5. **其他功能**
   - 測試結果詳細頁面
   - 歷史記錄查看
   - 資料匯出功能

## 📄 授權

本專案僅供學習參考使用。

---

**版本**: 1.3  
**最後更新**: 2025年1月

**更新內容**：
- ✅ 新增零點校正功能（手動觸發，200 筆資料，Z軸重力補償）
- ✅ 新增時間同步功能（校正時觸發）
- ✅ 新增即時圖表顯示（6 個獨立圖表，MPAndroidChart）
- ✅ 新增電壓濾波功能（雙層濾波器）
- ✅ 新增 Firebase Firestore 資料上傳（批次上傳，錄製模式）
- ✅ 更新 UI 設計（Material Design 3）
- ✅ 更新資料驗證範圍（已放寬）
- ✅ 更新電壓計算公式（校準常數 8.11）

