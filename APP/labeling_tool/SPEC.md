# PC Labeling Tool Specification (v1.0)

這份文件是專為 AI 或工程師提供的實作規格書。目標是開發一款高效能的羽球動作標註工具，支援長影片與多段 CSV 的精確同步。

---

# 1. 專案目標

建立一套 **PC 標註工具（Labeling Tool）**，核心需求：

1. **多 CSV 整合**：支援載入多個分割的 CSV 檔（每 5 分鐘一段），自動合併並對齊影片。
2. **精確同步**：解決硬體時鐘漂移（Drift）問題，支援「雙點線性拉伸」。
3. **高效標註**：設計針對高幀率動作（羽球）的播放控制與視覺輔助。
4. **標準輸出**：產出 `JSONL` 格式訓練資料，包含 `80筆 (前60後20)` 六軸資料。

---

# 2. 技術棧建議 (Tech Stack)

* **語言**: Python 3.10+
* **GUI 框架**: PySide6 (推薦) 或 PyQt6
  * *注意：需設定 High DPI 支援 (`os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "1"`)*
* **影片核心**: QMediaPlayer (Qt Multimedia) 或 VLC (python-vlc)
* **圖表核心**: pyqtgraph (必須，因 Matplotlib 效能不足以支撐 50Hz 游標刷新)
* **資料處理**: pandas (CSV/Time series), scipy (Signal processing), numpy

---

# 3. 資料輸入規格

## 3.1 CSV 格式 (Android App 輸出)

Android App `CSVManager.java` 產出的標準格式：
`timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ`

### 3.1.1 欄位定義
* **timestamp**: 裝置時間，格式 `yyyy/MM/dd HH:mm:ss.SSS` (e.g., `2025/12/05 22:20:06.510`)
* **receivedAt**: 手機接收時間，格式同上 (備用，主要用 timestamp)
* **accelX/Y/Z**: 加速度 (g), float
* **gyroX/Y/Z**: 角速度 (dps), float

### 3.1.2 預處理流程 (Loading & Fusion)
由於 APP 每 5 分鐘切檔，使用者會載入「一整個資料夾」或「多個檔案」。
1. **Load**: 讀取所有選定的 CSV。
2. **Merge**: 使用 pandas `concat` 合併。
3. **Sort**: 依 `timestamp` 排序。
4. **Deduplicate**: 去除重複時間點 (drop_duplicates)。
5. **Parse Time**: 將 `yyyy/MM/dd HH:mm:ss.SSS` 轉為 Unix Timestamp (ms) 或 datetime。
6. **Resample (Critical)**:
   * 建立標準 50Hz Grid (每 20ms 一點)。
   * 使用 `interpolate` (linear) 補齊缺漏值。
   * 輸出標準化 Time Index。

## 3.2 MP4 影片
* 支援 H.264/H.265 編碼。
* **長度檢查**: 若 `Total CSV Duration` < `Video Duration`，需跳出警告 (Warning: CSV coverage covers only XX% of video)。

---

# 4. 核心功能模組

## 4.1 時鐘同步與漂移修正 (Drift Correction)

解決 IMU 晶片與相機時鐘速度不一致的問題。

### 4.1.1 雙點線性對齊 (Two-point Scaling)
不只設定一個 Offset，而是設定「頭」與「尾」。
* 公式：`t_csv = t_video * scale_factor + offset`
* 流程：
  1. **Anchor A (Start)**: 找第 1 球，影片與曲線對齊 -> 設定 `(t_vid_1, t_csv_1)`。
  2. **Anchor B (End)**: 找第 N 球 (越後面越好)，影片與曲線對齊 -> 設定 `(t_vid_2, t_csv_2)`。
  3. **Calculate**:
     * `scale_factor = (t_csv_2 - t_csv_1) / (t_vid_2 - t_vid_1)`
     * `offset = t_csv_1 - t_vid_1 * scale_factor`

### 4.1.2 預設模式
若只設一個點，預設 `scale_factor = 1.0` (即單純 Offset)。

## 4.2 視覺化輔助 (Magnitude)
為了讓使用者更容易對齊，計算合力：
* `acc_mag = sqrt(ax^2 + ay^2 + az^2)`
* `gyro_mag = sqrt(gx^2 + gy^2 + gz^2)`
* 介面提供 Checkbox: **[x] Show Magnitude** (將合力畫成粗線，通常 Peak 對應擊球點)。

## 4.3 播放與導航控制
羽球動作極快，需細粒度控制：
* **播放速度**: 下拉選單 `[0.25x, 0.5x, 1.0x, 2.0x]`。
* **逐幀移動 (Frame Step)**: 快捷鍵 `Left / Right` -> 移動 1 Frame (約 33ms)。
* **數據移動 (Data Step)**: 快捷鍵 `Shift + Left / Right` -> 移動 1 Data Point (20ms)。

---

# 5. 標註與輸出規格

## 5.1 視窗截取 (Windowing)
當使用者標註瞬間 `t_current`：
1. **Find Index**: 在 50Hz Grid 中找到最接近的 index `i`。
2. **Slice**: 取範圍 `[i-60 : i+20]` (共 80 筆)。
   * 前 60 筆 (1.2秒 context)
   * 當下 1 筆
   * 後 19 筆 (0.38秒 follow-through)
3. **Data Shape**: `(80, 6)` (或 `(80, 8)` 若包含 magnitude)。

## 5.3 標註類別定義
系統需內建以下 5 種羽球姿態標籤（支援快捷鍵 1~5）：
1. **Smash** (殺球)
2. **Drive** (抽球)
3. **Toss** (挑球)
4. **Drop** (吊球)
5. **Other** (其他)

## 5.2 輸出格式 (JSONL)
檔名：`labels/{session_id}.jsonl`
每行一筆 JSON record：
```json
{
  "session_id": "20251213_01",
  "label": "smash",
  "timestamp_video_ms": 15420,
  "timestamp_csv_real": "2025/12/05 22:20:21.930",
  "sync_params": {
    "offset_ms": 5500,
    "scale_factor": 1.0002
  },
  "quality": {
    "interp_ratio": 0.05,  // 該段視窗有多少比例是補值的
    "dropped_frames": false
  },
  "data": [
    [0.12, 0.05, 0.98, 10.5, -2.3, 5.1], // ax, ay, az, gx, gy, gz
    ... (80 rows)
  ]
}
```

---

# 6. UI 佈局規劃

## 6.1 主視窗佈局 (Qt Grid Layout)
```
+---------------------------------------------------------------+
|  [Menu Bar] File (Load Video, Load CSV Folder...), Settings   |
+---------------------------------------------------------------+
|  Area A: Video Player (佔比 40-50%)                           |
|  [Video Viewport]                                             |
|  [Seek Bar | Time Label | 0.5x/1.0x Combo]                    |
|  [Controls: << < Play > >>]                                   |
+---------------------------------------------------------------+
|  Area B: Validation & Sync Control (佔比 10%)                 |
|  Offset: [ 1234 ms ] Scale: [ 1.000 ]                         |
|  [Set Start Anchor (A)] [Set End Anchor (B)] [Reset]          |
|  Status: "CSV Covers 100% video" (Green)                      |
+---------------------------------------------------------------+
|  Area C: Graph View (pyqtgraph) (佔比 30-40%)                 |
|  [Plot Widget: Accel XYZ + Mag] (可 Zoom/Pan)                 |
|  [Plot Widget: Gyro XYZ + Mag]                                |
|  * 垂直游標 (黃線) 鎖定影片時間                                  |
+---------------------------------------------------------------+
|  Area D: Labeling (Bottom/Right)                              |
|  [Smash (1)] [Drive (2)] [Toss (3)] [Drop (4)] [Other (5)]    |
|  [Undo (Z)]                                                   |
+---------------------------------------------------------------+
```

---

# 7. 開發里程碑 (Milestones)

請依照此順序進行開發：

### Phase 1: 基礎架構 (Data Ingestion)
1. 實作 `CSVReader`: 支援讀取單一/多個 CSV，Parse 日期格式，Merge & Resample 到 50Hz。
2. 實作 `GraphView`: 使用 pyqtgraph 繪製靜態六軸圖，加入 `Show Magnitude` 切換。

### Phase 2: 影片與同步 (Sync Core)
1. 整合 `VideoPlayer`: 載入 MP4，支援 Play/Pause/Seek。
2. 實作 `SyncManager`: 處理 `t_video` 到 `t_csv` 的轉換（含 Scale/Offset）。
3. 連動：影片播放時，Graph 游標跟隨；拖曳 Graph 游標時，影片跳轉。

### Phase 3: 標註系統 (Labeling)
1. 實作 `LabelManager`: 按鈕觸發 Slice (80筆) 邏輯。
2. 實作 `Writer`: 輸出 JSONL。
3. UI 整合：加入快捷鍵 (1-9, A, S, Z)。

### Phase 4: 優化與防呆 (Refinement)
1. 加入 **Drift Correction** (雙點對齊 UI)。
2. 加入 **Data Quality Check** (補值過多警告)。
3. 加入 **Session Save/Load** (保存工作進度)。

### Phase 5: 打包與發布 (Packaging)
1. 建立 `PyInstaller` spec 檔。
2. 撰寫 `build.bat` 自動化打包腳本。
3. 測試在無 Python 環境的電腦上執行。

---

# 8. 快捷鍵總表

* **Space**: Play / Pause
* **Left / Right**: 上/下一幀 (Frame)
* **Shift + Left / Right**: 上/下一筆資料 (20ms)
* **A**: 設定起始對齊點 (Start Anchor)
* **S**: 設定結束對齊點 (End Anchor)
* **Z**: 撤銷上一筆標註 (Undo)
* **Z**: 撤銷上一筆標註 (Undo)
* **1-5**: 標註對應類別
  * **1**: Smash 殺球
  * **2**: Drive 抽球
  * **3**: Toss 挑球
  * **4**: Drop 吊球
  * **5**: Other 其他

---

# 9. 打包與發布規格 (Distribution)

目標是讓沒有安裝 Python 的同學也能直接執行。

## 9.1 打包工具: PyInstaller
* **產出目標**: Windows `LabelingTool.exe` (單一執行檔 `onefile` 或單一資料夾 `onedir`)。
* **建議模式**: `onedir` (資料夾模式) 啟動較快，除錯容易；若要最簡便給同學可用 `onefile`，但需注意啟動解壓縮時間。

## 9.2 Build Script (`build.bat`)
AI 需提供一個 batch script，內容大致如下：
```batch
pyinstaller ^
    --name="SmartRacketLabeler" ^
    --windowed ^
    --icon=assets/icon.ico ^
    --clean ^
    --noconfirm ^
    main.py
```

## 9.3 常見依賴陷阱
* **PySide6**: 需確保 plugins (platforms, styles) 被正確打包。
* **Pandas/Numpy**: 檔案較大，需注意打包後的體積。
* **Hidden Imports**: 若使用動態 import，需在 spec 檔中手動加入 `hiddenimports`。

