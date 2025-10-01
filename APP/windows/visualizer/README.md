# Windows BLE IMU 視覺化程式

這個目錄包含Windows平台上的BLE IMU資料視覺化程式。

## 檔案說明

- `ble_imu_visualizer.py` - 主要的3D視覺化程式，接收BLE資料並顯示立體三軸指標
- `ble_uart_test.py` - BLE UART測試程式，用於接收和顯示原始資料
- `requirements.txt` - Python依賴套件清單
- `README.md` - 本說明檔案

## 安裝依賴

```bash
pip install -r requirements.txt
```

## 使用方法

### 1. 3D視覺化程式

```bash
python ble_imu_visualizer.py
```

功能：
- 自動掃描並連接Arduino設備
- 即時顯示立體三軸指標
- 支援鍵盤控制（ESC退出，R重置）

### 2. UART測試程式

```bash
python ble_uart_test.py
```

功能：
- 接收並顯示原始BLE資料
- 解析CSV格式的IMU資料
- 顯示詳細的資料內容

## 硬體需求

- Arduino XIAO nRF52840 Sense
- Windows 10/11 支援藍牙
- Python 3.8+

## 故障排除

1. **找不到BLE設備**
   - 確認Arduino已上傳BLE程式
   - 檢查藍牙是否開啟
   - 確認設備名稱是否為"SmartRacket"

2. **連接後立即斷線**
   - 檢查Arduino程式是否正確
   - 嘗試降低資料傳輸頻率
   - 檢查Windows藍牙驅動程式

3. **視覺化程式無法啟動**
   - 確認已安裝所有依賴套件
   - 檢查OpenGL驅動程式
   - 嘗試以管理員權限執行