# Smart Racket App 合併筆記（V2 / V3 / V4）— 後續開發者需要處理的事項

## 版本全名（開頭定義）

- V2：DIID_TermProject_v2/smart_racket_app  
- V3：DIID_TermProject-feature-flutter-app-junwei_v3  
- V4：DIID_TermProject_v4/smart_racket_app  

說明：目前整合狀態是我這邊沒有處理完善，導致「V3 的錄製流程」與「V2/V4 的 UI 顯示流程」尚未在同一條資料管線中對齊。後續開發者的目標是把兩者整合起來，避免出現「能錄不能顯示、能顯示不能錄」的二選一。

---

## 1) 錄製 Session 流程（V3 有；目前多半是 UI-only）

### V3 已具備（FirebaseService）
- startSession / endSession / cancelSession 完整流程
- session metadata：created_at、device_id、sample_rate、status
- raw_data 以 UUID 為 key 寫入 Realtime Database
- BUFFER_SIZE=50 批次上傳（避免每筆都打 DB）
- uploadedCount / pendingCount 計數（支援 UI Uploaded/Pending）

### 目前 UI 已經存在（RecordPage）
- Uploaded/Pending 顯示
- Flush Pending、Reset Counters、End & Upload、Clear/Cancel
- Session ID 編輯
- LabelChip（Smash/Drive/Drop/Clear/Net + None）
- 但目前多是 dynamic fallback 嘗試呼叫；若後端未提供對應方法，按鈕實際上會空轉

### 後續開發者建議補齊（最小可用集合）
HomeProvider 內需要有「錄製狀態機 + 真實串接 FirebaseService」：

- 狀態欄位：
  - isRecording
  - isPaused（若要 Pause/Resume）
  - currentSessionId
  - uploadedCount / pendingCount
- 必要方法（至少一套命名要確定存在，不用靠 dynamic try-catch）：
  - startRecord()  -> firebase.startSession()
  - stopRecord()   -> firebase.endSession(label)
  - clearRecord()  -> firebase.cancelSession()
  - flushPending() -> firebase.flushBuffer()
  - resetUploadCounters() -> uploaded/pending 歸零
  - endSession(label?) / cancelSession()（兩者至少要有可用入口）

---

## 2) Label（姿勢標註）寫入 Session（V3 有；目前缺後端落點）

### V3 已具備（設計方向）
- endSession(label) 時把 label 寫入 session（或 metadata/結尾欄位）
- 或錄製期間 setLabel，結束上傳時帶入

### 目前 UI 狀態
- UI 有 LabelChip（Smash/Drive/Drop/Clear/Net + None）
- _setLabel() 會嘗試呼叫 provider 的多種方法名稱（dynamic fallback）

### 後續開發者建議補齊（最小可用）
HomeProvider 內至少要有一組「確定存在」的欄位與方法：
- String? currentLabel
- Future<void> setLabel(String label)

FirebaseService.endSession(label) 需要確實把 label 寫進 session（metadata 或 session root 欄位均可，但請保持一致）

---

## 3) BLE 資料解析與穩定性（V3 有；目前不一定完整）

### V3 BleService 已具備
- requestMtu(185)（Android）
- notify chunk 組包固定長度封包（30 bytes）
- resync：解析失敗丟 1 byte 重新對齊
- buffer 防爆（避免 BytesBuilder 無限長）
- imuDataStream broadcast（上層訂閱用）

### 目前 UI 對 HomeProvider 的依賴（必須滿足）
- SixAxisPanel 依賴：
  - latestFrame、batteryVoltage、isConnected、connectionStatus
- GraphPage 依賴：
  - recentFramesSnapshot（快速取 snapshot）

### 後續開發者建議補齊（若尚未做）
HomeProvider 啟動時訂閱 BleService.imuDataStream，並維護：
- latestFrame（給 SixAxisPanel）
- recentFrames（固定長度 ring buffer，給 GraphPage snapshot）
- batteryVoltage（從封包或欄位換算）

備註：
- 若 V3 BleService 已完成解析/組包，HomeProvider 建議不要再二次組包；直接吃「已解析資料」並轉成 UI 需要的 frame 格式即可。

---

## 4) Permissions（V3 有；目前多半缺實作）

### V3 常見會處理
- Android 12+ BLE scan/connect 權限（BLUETOOTH_SCAN / CONNECT / LOCATION 等）
- permission_handler 統一入口（requestPermissions / ensurePermissions）

### 目前 UI 狀態
- RealtimePage 有 Permissions 按鈕
- 會嘗試呼叫 requestPermissions / ensurePermissions / checkPermissions（dynamic fallback）
- 若 HomeProvider 沒實作，會顯示「Permission method not supported」

### 後續開發者建議補齊（最小可用）
HomeProvider 提供一個確定存在的入口：
- Future<void> requestPermissions()

內部用 permission_handler 請求並回饋結果（UI 已有 SnackBar 提示邏輯）

---

## 5) Calibration（V3 可能有；目前多半只有 UI 對話框）

### V3 常見具備（概念）
- startCalibration/calibrate：把目前 gyro 作為 offset
- resetCalibration/resetOffsets：清除 offset
- isCalibrated 旗標
- offset 套用到後續 gyro（或 acc/gyro 都可）

### 目前 UI 狀態（CalibrationDialog）
- 會動態嘗試多種方法名稱：
  - startCalibration / calibrate / calibrateNow / runCalibration
  - resetCalibration / clearCalibration / resetOffsets / clearOffsets / setOffsetsToZero
- 顯示 baseGyro/liveGyro
- 但「真正校正」需要由 Provider 落地

### 後續開發者建議補齊（最小可用）
HomeProvider 欄位與方法：
- bool isCalibrated
- List<double> gyroOffset（3 axis）
- Future<void> startCalibration()：把 current gyro 設為 offset，isCalibrated=true
- Future<void> resetCalibration()：offset=0，isCalibrated=false
- 在產生 latestFrame / recentFrames 時套 offset（gyro - offset）

---

## 6) Shot popup / 統計（UI 已有；後端高度可能缺）

### 目前 UI 明確依賴（若缺會空轉）
- shotPopupSeq（序號遞增觸發 PageBody 彈窗）
- shotPopupType（Smash/Drive/...）
- swingCounts（Map）
- totalSwings（int）
- resetSwingCounts()

### 後續開發者建議補齊（最小可用）
HomeProvider 在收到分類結果時更新：
- totalSwings++
- swingCounts[type]++
- shotPopupType = type
- shotPopupSeq++（讓 PageBody 觸發彈窗）

分類結果來源通常是 WebSocket：
- 收到 server message（type）-> 更新上述欄位

---

## 7) WebSocket / 推論串接（完整版本常見；目前可能缺整合）

### 完整版本通常具備
- WebSocketService connect/disconnect
- sendWindow(List<IMUFrame>) 傳一段時間窗到 server 做分類
- message stream 回來更新 shot type

### 目前 UI 提示的缺口
- RealtimePage 有 Server IP/Domain 欄位與 Save & Reconnect 按鈕
- 但 UI 只會 updateSettings + 提示 reconnect
- 組 window / sendWindow / 解析回傳 / 更新 stats 多半要在 HomeProvider 做

### 後續開發者建議補齊（最小可用）
- DataBufferManager：把 BLE frames 組成 window
- HomeProvider：BLE frames -> window -> websocket.sendWindow
- WebSocket 回來：解析 JSON（type/label/confidence）-> 更新 shotPopup/stats
- updateSettings(sensitivity, serverIp)：要真的存並觸發 websocket reconnect

---

## 8) 根因：資料欄位不一致導致「V2 能顯示不能錄 / V3 能錄不能顯示」

### UI 端（V2/V4）明顯期待的資料型態
- latestFrame: IMUFrame?
- IMUFrame.acc: List<double>（長度 3）
- IMUFrame.gyro: List<double>（長度 3）
- IMUFrame.timestamp: double
- batteryVoltage: double?

### 錄製端（V3 FirebaseService）明顯期待的資料型態
- IMUData.timestampMs（int）
- accX/accY/accZ（double）
- gyroX/gyroY/gyroZ（double）
- voltage（mV 或 V）
- toJson() 對齊 Firebase schema

### 目前症狀整理
- 依照 V2 的 frame 結構：UI 顯示正常，但 Firebase 錄製會壞（不會轉成 V3 JSON）
- 依照 V3 的 IMUData 結構：Firebase 錄製正常，但 UI 顯示數字會壞（acc/gyro list 讀不到）

---

## 9) 後續開發者需要處理的「最重要補件」：統一資料模型 + 兩套 Adapter

### 建議做法
HomeProvider 內只保留一個 canonical 資料結構（例如 ImuSample），再轉出兩套輸出：

- 給 UI：
  - ImuSample.toFrame() -> IMUFrame（acc/gyro list、timestamp double）
- 給 Firebase：
  - ImuSample.toFirebaseJson() -> Map<String,dynamic>（timestampMs、accX..gyroZ、voltage 對齊）

若沒有這層 adapter，就會一直回到「能錄不能顯示 / 能顯示不能錄」的狀態。

### 最小 adapter 清單
- ImuSample.fromBlePacket(...) 或 fromIMUData/fromIMUFrame（視 BLE 上層輸出）
- ImuSample.toFrame(): IMUFrame
- ImuSample.toFirebaseJson(): Map<String, dynamic>

---

## 10) 「看得見但未必有用」的 UI 功能點（高機率缺底層）

若 HomeProvider 未實作，以下會失效或空轉：

- RecordPage：
  - Pause/Resume（isPaused、pauseRecord/resumeRecord）
  - End & Upload（endSession/finishSession/stopSession + Firebase endSession）
  - Flush Pending（flushPending/flush/flushBuffer）
  - Reset Counters（resetUploadCounters/resetCounters）
  - Clear/Cancel（cancelSession/cancelRecord/deleteSession/removeSession）
  - Session ID 編輯（setSessionId/updateSessionId/renameSession）
  - Label 寫入（setLabel + endSession(label)）
- PageBody：
  - shotPopupSeq/shotPopupType（彈窗觸發）
- StatsPage：
  - totalSwings、swingCounts、resetSwingCounts()

---

## 結論（建議處理順序）
1. 在 HomeProvider 建立 canonical ImuSample + adapters（先解欄位不一致）
2. 串 BLE stream -> 更新 latestFrame / recentFrames / batteryVoltage（讓 UI 數字穩定顯示）
3. 串 Firebase Session：start/add/end/cancel + buffer + counters（讓錄製可用）
4. 串 WebSocket：windowing + sendWindow + 解析回傳 + 更新 stats/popup（讓姿勢統計/彈窗可用）
5. 補 Permissions / Calibration 的「確定存在方法」（避免 UI dynamic fallback 空轉）
