# 智能羽毛球拍 IMU 接收器 - Android App

## 📱 專案說明

這是一個 Android 應用程式，用於連接 nRF52840 感測器並接收 IMU（慣性測量單元）資料。

## ✨ 功能特色

- ✅ BLE 藍牙低功耗連接
- ✅ 自動掃描並連接 SmartRacket 設備
- ✅ 即時接收 IMU 資料（50Hz，每 20ms 一筆）
- ✅ 顯示加速度、角速度、電壓等資料
- ✅ 資料驗證和錯誤處理
- ✅ 美觀的使用者介面

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

## 📦 專案結構

```
app/src/main/
├── java/com/example/smartbadmintonracket/
│   ├── MainActivity.java          # 主活動，處理 UI 和 BLE 連接
│   ├── BLEManager.java            # BLE 管理器，處理掃描、連接、資料接收
│   ├── IMUData.java               # IMU 資料模型類
│   └── IMUDataParser.java         # 資料解析器，將 30 bytes 解析為 IMUData
├── res/
│   └── layout/
│       └── activity_main.xml      # 主介面佈局
└── AndroidManifest.xml            # 應用程式清單（包含 BLE 權限）
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
     - 時間戳記
     - 加速度（X, Y, Z 軸，單位：g）
     - 角速度（X, Y, Z 軸，單位：dps）
     - 電壓（單位：V）
     - 接收資料總數
     - 最新一筆完整資料

4. **斷開連接**
   - 點擊「斷開連接」按鈕即可斷開 BLE 連接

## 📊 資料格式

### 接收的資料結構

每筆資料包含以下資訊：

| 欄位 | 類型 | 單位 | 說明 |
|------|------|------|------|
| timestamp | long | 毫秒 | 感測器時間戳記 |
| accelX | float | g | X軸加速度 |
| accelY | float | g | Y軸加速度 |
| accelZ | float | g | Z軸加速度 |
| gyroX | float | dps | X軸角速度 |
| gyroY | float | dps | Y軸角速度 |
| gyroZ | float | dps | Z軸角速度 |
| voltage | float | V | 電池電壓 |

### 資料驗證

應用程式會自動驗證接收到的資料：
- 加速度範圍：-16g ~ +16g
- 角速度範圍：-2000 ~ +2000 dps
- 電壓範圍：0 ~ 5V

超出範圍的資料會被過濾，不會顯示在畫面上。

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

### 主要類別說明

#### BLEManager
- 處理所有 BLE 相關操作
- 提供掃描、連接、斷開連接功能
- 透過回調接口通知連接狀態和資料接收

#### IMUDataParser
- 解析 30 bytes 的二進位資料
- 使用 Little-Endian 位元組順序
- 驗證資料有效性

#### MainActivity
- 管理 UI 更新
- 處理使用者互動
- 協調 BLE 操作和資料顯示

## 🔄 後續開發建議

1. **資料儲存**
   - 可添加 SQLite 資料庫儲存歷史資料
   - 支援匯出 CSV 或 JSON 格式

2. **資料視覺化**
   - 添加即時波形圖顯示
   - 3D 姿態視覺化

3. **WiFi 上傳**
   - 整合 HTTP 客戶端
   - 支援批次上傳至伺服器

4. **AI 分析**
   - 整合 TensorFlow Lite
   - 即時球路識別

## 📄 授權

本專案僅供學習參考使用。

---

**版本**: 1.0  
**最後更新**: 2024年12月

