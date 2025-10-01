# IMU 3D 視覺化程式

## 📋 功能說明

這個程式可以接收Arduino IMU感測器的串列資料，並即時顯示立體三軸指標，讓您直觀地看到感測器的姿態變化。

## 🎯 特色功能

- **即時3D顯示**: 立體三軸指標跟隨IMU姿態變化
- **串列通訊**: 直接接收Arduino的CSV格式資料
- **姿態計算**: 自動計算俯仰角、滾轉角、偏航角
- **參考網格**: 提供空間參考基準
- **模擬模式**: 無硬體時可使用模擬資料測試

## 🛠️ 安裝需求

### Python環境
- Python 3.7+
- pip套件管理器

### 必要套件
```bash
pip install -r requirements.txt
```

或手動安裝：
```bash
pip install pygame PyOpenGL PyOpenGL-accelerate numpy pyserial
```

## 🚀 使用方法

### 1. 準備Arduino程式
確保您的Arduino程式正在運行並輸出CSV格式資料：
```
Timestamp,AccelX,AccelY,AccelZ,GyroX,GyroY,GyroZ,TempC
```

### 2. 修改串列埠設定
在 `imu_3d_visualizer.py` 中修改串列埠：
```python
port = 'COM3'  # Windows
# port = '/dev/ttyUSB0'  # Linux
# port = '/dev/ttyACM0'  # Mac
```

### 3. 執行程式
```bash
python imu_3d_visualizer.py
```

### 4. 操作說明
- **ESC**: 退出程式
- **R**: 重置姿態角度
- **滑鼠**: 旋轉視角（如果實作）

## 📊 顯示說明

### 三軸指標
- **紅色軸**: X軸（前後）
- **綠色軸**: Y軸（左右）
- **藍色軸**: Z軸（上下）

### 姿態角度
- **Roll (滾轉)**: 繞X軸旋轉
- **Pitch (俯仰)**: 繞Y軸旋轉
- **Yaw (偏航)**: 繞Z軸旋轉

## 🔧 故障排除

### 常見問題

1. **串列埠連接失敗**
   - 檢查Arduino是否正確連接
   - 確認串列埠號碼是否正確
   - 檢查Arduino程式是否正在運行

2. **資料讀取錯誤**
   - 確認Arduino輸出格式為CSV
   - 檢查波特率設定是否一致
   - 確認資料包含8個欄位

3. **3D顯示問題**
   - 確認已安裝PyOpenGL
   - 檢查顯示驅動程式
   - 嘗試降低顯示解析度

### 除錯模式
在程式中加入除錯輸出：
```python
print(f"Accel: {self.accel}, Gyro: {self.gyro}")
print(f"Roll: {self.roll:.2f}, Pitch: {self.pitch:.2f}, Yaw: {self.yaw:.2f}")
```

## 🎨 自訂功能

### 修改顯示顏色
```python
# 在draw_axes()函數中修改
glColor3f(1, 0, 0)  # 紅色 (R, G, B)
glColor3f(0, 1, 0)  # 綠色
glColor3f(0, 0, 1)  # 藍色
```

### 調整更新頻率
```python
# 在run()函數中修改
clock.tick(60)  # 60 FPS
```

### 添加文字顯示
可以整合pygame的字體渲染功能來顯示數值。

## 📈 進階功能建議

1. **資料記錄**: 將IMU資料儲存到檔案
2. **姿態融合**: 使用卡爾曼濾波器改善姿態計算
3. **多視角**: 支援不同視角切換
4. **資料分析**: 即時頻譜分析
5. **網路傳輸**: 支援WiFi或藍牙傳輸

## 🔗 相關資源

- [Pygame官方文件](https://www.pygame.org/docs/)
- [PyOpenGL文件](https://pyopengl.sourceforge.net/)
- [Arduino串列通訊](https://www.arduino.cc/reference/en/language/functions/communication/serial/)
