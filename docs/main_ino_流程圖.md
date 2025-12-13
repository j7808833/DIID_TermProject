# SmartRacket IMU BLE 傳輸系統 - 程式執行流程圖

## 整體系統流程圖

```mermaid
flowchart TD
    Start([系統啟動]) --> Setup[setup 函數執行]
    
    Setup --> InitSerial[初始化串列通訊<br/>9600 bps]
    InitSerial --> InitI2C[初始化 I2C 通訊<br/>400kHz]
    InitI2C --> InitIMU{IMU 初始化成功?}
    
    InitIMU -->|失敗| Error1[輸出錯誤訊息<br/>停止執行]
    InitIMU -->|成功| InitLED[初始化 LED 腳位]
    
    InitLED --> InitBLE[初始化 BLE]
    InitBLE --> BLEConfig[設定 BLE 服務與特徵<br/>設備名稱: SmartRacket]
    BLEConfig --> BLEAdvertise[開始 BLE 廣播]
    BLEAdvertise --> Loop[進入 loop 主迴圈]
    
    Loop --> PollBLE[BLE.poll 處理事件]
    PollBLE --> CheckConnection{檢查 BLE 連接狀態}
    
    // checkVoltageAndSleep() 被註解掉，故暫不執行省電檢查
    
    CheckConnection -->|未連接| NoConnection
    CheckConnection -->|已連接| Connected
    
    NoConnection --> CheckDataTime1{到達資料輸出時間?<br/>20ms = 50Hz}
    CheckDataTime1 -->|是| ReadIMU1[讀取 IMU 資料<br/>減去校正偏移量]
    CheckDataTime1 -->|否| PollBLE
    ReadIMU1 --> ReadVoltage1[讀取電池電壓<br/>啟用分壓電路]
    ReadVoltage1 --> SerialOutput[串列埠輸出資料<br/>aX,aY,aZ,gX,gY,gZ,voltage]
    SerialOutput --> UpdateTime1[更新輸出時間]
    UpdateTime1 --> Delay1[延遲 10ms]
    Delay1 --> PollBLE
    
    Connected --> TimeSync{收到時間同步?}
    TimeSync -->|是| UpdateTimeBase[更新基準時間]
    TimeSync -->|否| FirstCalibration
    FirstCalibration -->|是| Calibrate[執行 IMU 校正<br/>採樣 100 次]
    FirstCalibration -->|否| CheckDataTime2{到達資料輸出時間?<br/>20ms = 50Hz}
    
    Calibrate --> CalcOffset[計算偏移量<br/>加速度Offset設為0<br/>陀螺儀計算平均偏移]
    CalcOffset --> SetCalibrationDone[設定校正完成標記]
    SetCalibrationDone --> FirstConnection[首次連接處理<br/>初始化電壓緩存]
    FirstConnection --> CheckDataTime2
    
    CheckDataTime2 -->|是| ReadIMU2[讀取最新 IMU 資料<br/>減去校正偏移量]
    CheckDataTime2 -->|否| PollBLE
    
    ReadIMU2 --> CheckVoltageTime{需要更新電壓?<br/>每 10 秒或緩存為 0}
    CheckVoltageTime -->|是| ReadVoltageAvg[讀取 30 筆電壓取平均]
    CheckVoltageTime -->|否| UseCachedVoltage[使用緩存電壓值]
    
    ReadVoltageAvg --> UpdateVoltageCache[更新電壓緩存]
    UpdateVoltageCache --> UseCachedVoltage
    UseCachedVoltage --> PackData[封包化資料<br/>30 bytes 二進位格式]
    
    PackData --> PackTimestamp[時間戳 4 bytes]
    PackTimestamp --> PackAccel[加速度 X,Y,Z 各 4 bytes]
    PackAccel --> PackGyro[角速度 X,Y,Z 各 4 bytes]
    PackGyro --> PackVoltage[電壓 2 bytes]
    
    PackVoltage --> SendBLE[透過 BLE 發送資料]
    SendBLE --> SendSuccess{發送成功?}
    SendSuccess -->|失敗| BLEError[輸出錯誤訊息]
    SendSuccess -->|成功| UpdateSendTime[更新傳輸時間]
    BLEError --> UpdateSendTime
    UpdateSendTime --> PollBLE
    
    style Start fill:#90EE90
    style Error1 fill:#FFB6C1
    style Connected fill:#87CEEB
    style NoConnection fill:#DDA0DD
    style Calibrate fill:#FFD700
    style SendBLE fill:#98FB98
```

## IMU 校正流程詳圖

```mermaid
flowchart TD
    StartCal[開始校正] --> InitSum[初始化累加變數<br/>sumAX, sumAY, sumAZ<br/>sumGX, sumGY, sumGZ]
    
    InitSum --> Loop100[迴圈 100 次]
    Loop100 --> ReadRaw[讀取原始感測器值]
    ReadRaw --> Accumulate[累加原始值]
    Accumulate --> Delay10[延遲 10ms]
    Delay10 --> CheckCount{是否完成 100 次?}
    
    CheckCount -->|否| Loop100
    CheckCount -->|是| CalcAvg[計算平均值]
    
    CalcAvg --> CalcOffsetAX[offsetAX = 0]
    CalcOffsetAX --> CalcOffsetAY[offsetAY = 0]
    CalcOffsetAY --> CalcOffsetAZ[offsetAZ = 0]
    CalcOffsetAZ --> CalcOffsetGX[offsetGX = sumGX / 100]
    CalcOffsetGX --> CalcOffsetGY[offsetGY = sumGY / 100]
    CalcOffsetGY --> CalcOffsetGZ[offsetGZ = sumGZ / 100]
    
    CalcOffsetGZ --> Done[校正完成]
    
    style StartCal fill:#FFD700
    style Done fill:#90EE90
```

## 電壓讀取流程詳圖

```mermaid
flowchart TD
    StartVolt[開始讀取電壓] --> EnableDivider[啟用分壓電路<br/>P0.14 = LOW]
    EnableDivider --> WaitStable[等待 500µs<br/>電壓穩定]
    
    WaitStable --> InitSum[初始化累加變數<br/>sum = 0, validSamples = 0]
    InitSum --> Loop30[迴圈 30 次]
    
    Loop30 --> ReadADC[讀取 ADC 值<br/>analogRead A0]
    ReadADC --> Validate{讀數有效?<br/>0-1023}
    
    Validate -->|否| NextSample[下一個樣本]
    Validate -->|是| Convert12bit[轉換為 12-bit<br/>raw * 4]
    Convert12bit --> AddSum[累加到 sum]
    AddSum --> IncValid[validSamples++]
    IncValid --> Delay100[延遲 100µs]
    Delay100 --> NextSample
    
    NextSample --> Check30{完成 30 次?}
    Check30 -->|否| Loop30
    Check30 -->|是| DisableDivider[關閉分壓電路<br/>P0.14 = HIGH<br/>省電]
    
    DisableDivider --> CheckValid{validSamples > 0?}
    CheckValid -->|否| Return0[返回 0]
    CheckValid -->|是| CalcAvg[計算平均值<br/>sum / validSamples]
    
    CalcAvg --> ReturnValue[返回平均值]
    
    style StartVolt fill:#87CEEB
    style ReturnValue fill:#90EE90
    style Return0 fill:#FFB6C1
```

## 資料封包結構

```mermaid
flowchart LR
    Start[開始封包化] --> Buffer[建立 30 bytes 緩衝區]
    
    Buffer --> TS[時間戳記<br/>4 bytes<br/>位置: 0-3]
    TS --> AX[加速度 X<br/>4 bytes<br/>位置: 4-7]
    AX --> AY[加速度 Y<br/>4 bytes<br/>位置: 8-11]
    AY --> AZ[加速度 Z<br/>4 bytes<br/>位置: 12-15]
    AZ --> GX[角速度 X<br/>4 bytes<br/>位置: 16-19]
    GX --> GY[角速度 Y<br/>4 bytes<br/>位置: 20-23]
    GY --> GZ[角速度 Z<br/>4 bytes<br/>位置: 24-27]
    GZ --> V[電壓<br/>2 bytes<br/>位置: 28-29]
    
    V --> Complete[封包完成<br/>30 bytes]
    
    style Start fill:#87CEEB
    style Complete fill:#90EE90
```

## 系統狀態機

```mermaid
stateDiagram-v2
    [*] --> 初始化中: 系統啟動
    
    初始化中 --> 廣播中: BLE 初始化成功
    初始化中 --> 錯誤: IMU 初始化失敗
    
    廣播中 --> 已連接: 手機連接
    廣播中 --> 資料輸出: 每 20ms
    
    已連接 --> 校正中: 首次連接
    校正中 --> 資料傳輸: 校正完成
    
    資料傳輸 --> 資料傳輸: 每 20ms 發送
    資料傳輸 --> 廣播中: 斷線
    
    資料輸出 --> 廣播中: 持續輸出串列資料
    
    錯誤 --> [*]: 停止執行
    
    note right of 校正中
        採樣 100 次
        計算偏移量
    end note
    
    note right of 資料傳輸
        50Hz 傳輸頻率
        30 bytes 封包
    end note
```

## 時間軸流程圖

```mermaid
gantt
    title SmartRacket 系統執行時間軸
    dateFormat X
    axisFormat %L ms
    
    section 初始化階段
    setup() 執行           :0, 100
    
    section 主迴圈 (每 20ms)
    BLE.poll()             :100, 1
    讀取 IMU 資料          :101, 2
    讀取電壓               :103, 1
    串列輸出               :104, 1
    BLE 資料封包化         :105, 2
    BLE 發送               :107, 1
    
    section 電壓更新 (每 10 秒)
    讀取 30 筆電壓取平均   :10000, 50
    
    section IMU 校正 (首次連接)
    採樣 100 次            :200, 1000
```

## 關鍵參數說明

| 參數         | 數值     | 說明                                      |
| ------------ | -------- | ----------------------------------------- |
| 資料輸出頻率 | 50Hz     | 每 20ms 輸出一次                          |
| BLE 傳輸頻率 | 50Hz     | 每 20ms 傳輸一次                          |
| 電壓讀取間隔 | 10 秒    | 每 10 秒更新一次電壓緩存                  |
| 電壓採樣次數 | 30 次    | 每次讀取 30 筆取平均                      |
| IMU 校正採樣 | 100 次   | 校正時採樣 100 次                         |
| I2C 時鐘頻率 | 400kHz   | 高速模式                                  |
| 串列通訊速率 | 9600 bps | 除錯用                                    |
| 資料封包大小 | 30 bytes | 時間戳 4 + 加速度 12 + 陀螺儀 12 + 電壓 2 |

## 資料流程說明

1. **初始化階段 (setup)**
   - 初始化所有硬體介面
   - 設定 BLE 服務和特徵
   - 開始 BLE 廣播

2. **主迴圈 (loop)**
   - 持續處理 BLE 事件
   - 無論是否連接，每 20ms 讀取一次 IMU 資料
   - 已連接時，每 20ms 透過 BLE 發送資料
   - 未連接時，僅輸出串列資料

3. **IMU 校正**
   - 首次 BLE 連接時自動執行
   - 採樣 100 次計算偏移量
   - 加速度 Z 軸需減去重力加速度 (1g)

4. **電壓監控**
   - 每 10 秒更新一次電壓緩存
   - 每次讀取 30 筆取平均以提高穩定性
   - 使用分壓電路，讀取後立即關閉以省電

5. **資料封包**
   - 30 bytes 二進位格式
   - Little-Endian 位元組順序
   - 包含時間戳、六軸資料和電壓

---

**最後更新：** 2024年  
**維護者：** DIID Term Project Team

