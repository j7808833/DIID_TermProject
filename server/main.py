import logging
import random
import json
import time
from typing import List, Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

# --- 配置日誌 (Logging) ---
# 設定程式的記錄層級，INFO 代表一般訊息，ERROR 代表錯誤
# 這就像是在寫開發日記，讓我們知道程式執行到哪裡了
logging.basicConfig(level=logging.INFO)
# 建立一個 Logger 物件，名稱叫做 "BadmintonServer"
logger = logging.getLogger("BadmintonServer")

# --- 建立 FastAPI 主程式 ---
# FastAPI 是一個很快速、現代化的 Python 網頁框架
# 我們用它來架設伺服器，處理手機 APP 傳來的資料
app = FastAPI(title="Badminton Swing Recognition Server")

# --- 資料模型 (Data Models) ---
# 這裡定義資料長什麼樣子，使用 Pydantic 函式庫來幫我們檢查資料格式
# 就像是在定義一張表格的欄位

class IMUFrame(BaseModel):
    # 這是一個 IMU 資料點 (一個瞬間的狀態)
    ts: float          # Timestamp: 時間戳記 (秒)
    acc: List[float]   # Accelerometer: 加速度計 [X, Y, Z]
    gyro: List[float]  # Gyroscope: 陀螺儀 [X, Y, Z]

class SwingRequest(BaseModel):
    # 這是手機傳來的一整包「揮拍資料」
    client_id: str         # 手機的 ID (誰傳來的)
    data: List[IMUFrame]   # 一連串的 IMU 資料點 (組合成一個動作)

# --- AI 模型封裝 (Model Wrappers) ---
# 這裡模擬載入訓練好的 AI 模型
# 在真實專案中，這裡會使用 PyTorch (torch.load) 來載入 .pth 檔案

class SwingClassifier:
    """
    動作分類模型 (Classifier)
    功能：判斷這個動作是「殺球」、「平抽」、「挑球」還是「切球」。
    """
    def __init__(self):
        # 初始化：程式啟動時會執行這裡
        # self.model = torch.load("c:/models/classifier_v1.pth") # 真實載入方式
        
        # 定義我們支援的動作類別
        self.classes = ["Smash", "Drive", "Toss", "Drop", "Other"]
        logger.info("Loaded Classifier Model (Mock)") # 紀錄：模型載入完成

    def predict(self, frames: List[IMUFrame]):
        """
        推論 (Predict) 函式
        輸入：一連串的 IMU 資料 (frames)
        輸出：預測的動作名稱 (predicted_class) 和信心度 (confidence)
        """
        # 這裡應該要寫真實的 AI 推論程式碼...
        
        # (模擬行為 Mock)
        # 隨機選一個動作，假設殺球 (Smash) 機率最高 (0.3)
        predicted_class = random.choices(
            self.classes, weights=[0.3, 0.2, 0.2, 0.2, 0.1], k=1
        )[0]
        # 隨機產生一個信心度 (0.7 ~ 0.99 之間)
        confidence = random.uniform(0.7, 0.99)
        return predicted_class, confidence

class SpeedRegressor:
    """
    球速預測模型 (Regressor)
    功能：如果動作是「殺球」，就進一步預測球速幾公里。
    """
    def __init__(self):
        # self.model = torch.load("c:/models/speed_regressor_v1.pth")
        logger.info("Loaded Speed Model (Mock)")

    def predict(self, frames: List[IMUFrame]):
        """
        輸入：一連串的 IMU 資料
        輸出：預測的球速 (float)
        """
        # (模擬行為)
        # 這裡用一個簡單的物理公式來假裝算球速：加速度越快，球速越快
        # 先找出這一連串資料中，加速度最大值 (Max Magnitude)
        max_acc = 0
        for f in frames:
            # 算出合力大小：sqrt(x^2 + y^2 + z^2)
            mag = (f.acc[0]**2 + f.acc[1]**2 + f.acc[2]**2) ** 0.5
            if mag > max_acc:
                max_acc = mag
        
        # 隨機乘上一個倍數，讓球速看起來合理 (例如 150 ~ 250 km/h)
        speed = max_acc * random.uniform(8, 12) 
        return round(speed, 1) # 四雪五入到小數下一位

# --- 程式啟動初始化 ---
# 這裡一次把兩個模型載入到記憶體 (RAM) 中
# 這樣之後每次有人傳資料來，就不用重新讀檔，速度會快很多
try:
    classifier = SwingClassifier()
    speed_model = SpeedRegressor()
except Exception as e:
    # 如果載入失敗 (例如檔案找不到)，就印出錯誤並停止程式
    logger.error(f"Failed to load models: {e}")
    raise e

# --- WebSocket 路由 (Endpoint) ---
# 定義一個網址：wss://你的網址/ws/predict
# 手機 APP 會連線到這個網址來傳送資料

@app.websocket("/ws/predict")
async def websocket_endpoint(websocket: WebSocket):
    # 當有手機連上來時，先接受連線
    await websocket.accept()
    logger.info("Client connected") # 紀錄：有人連線了
    
    try:
        # 使用無窮迴圈 (while True) 來持續接收資料
        # 只要連線沒斷，就會一直跑要在這裡
        while True:
            # 1. 等待並接收手機傳來的文字資料 (receive_text)
            # await 代表「等待」，在等待期間伺服器可以去處理別人的請求 (非同步)
            data = await websocket.receive_text()
            
            # 使用 json 模組把文字轉成 Python 字典 (Dictionary)
            payload = json.loads(data)
            
            # 從字典中取出資料
            # .get("key", default) 的寫法是：如果找不到這個 key，就給預設值
            client_id = payload.get("client_id", "unknown")
            raw_frames = payload.get("data", [])
            
            # 如果資料是空的，就跳過這次迴圈，繼續等下一筆
            if not raw_frames:
                continue

            logger.info(f"Received {len(raw_frames)} frames from {client_id}")

            # 將原始字典資料轉換成我們定義好的 IMUFrame 物件
            # 這樣操作起來比較方便 (可以使用 frames[0].acc 這樣存取)
            frames = [
                IMUFrame(ts=f["ts"], acc=f["acc"], gyro=f["gyro"]) 
                for f in raw_frames
            ]

            # 2. 執行 AI 推論 (Inference)
            # 呼叫分類器，猜它是什麼動作
            action_type, confidence = classifier.predict(frames)
            
            # 3. 準備回傳結果 (Response)
            # 先填好基本資料
            response = {
                "timestamp": frames[-1].ts,  # 使用最後一筆資料的時間戳記
                "type": action_type,         # 動作類型 (Smash, Drive...)
                "confidence": round(confidence, 2), # 信心度
                "speed": None,    # 預設沒有球速
                "display": False, # 預設不顯示 (除非信心足夠)
                "message": ""     # 給使用者看的訊息
            }

            # 設定信心門檻：只有信心度 > 0.6 我們才把它當真
            if confidence > 0.6:
                response["display"] = True # 告訴 APP：請顯示這個結果
                
                # 只有殺球 (Smash) 才去計算球速
                if action_type == "Smash":
                    speed = speed_model.predict(frames)
                    response["speed"] = speed
                    response["message"] = f"Smash! {speed} km/h"
                    logger.info(f"SMASH: {speed} km/h")
                else:
                    # 其他球路只顯示名稱
                    response["message"] = f"{action_type}"
                    logger.info(f"Detected: {action_type}")
            else:
                # 信心不足，當作沒發生或雜訊
                response["display"] = False
                response["message"] = "Low confidence"

            # 4. 將結果回傳給手機
            # json.dumps 把字典轉回 JSON 文字字串
            await websocket.send_text(json.dumps(response))
            
    except WebSocketDisconnect:
        # 手機斷線了 (例如使用者關掉 APP)
        logger.info("Client disconnected")
    except Exception as e:
        # 發生未預期的錯誤
        logger.error(f"Error: {e}")
        await websocket.close() # 關閉連線

# --- 健康檢查 API ---
# 可以用瀏覽器打開 http://localhost:8000/ 確認伺服器有沒有活著
@app.get("/")
def health_check():
    return {"status": "ok", "version": "v3.0"}

# --- 程式進入點 ---
if __name__ == "__main__":
    import uvicorn
    # 啟動伺服器
    # host="0.0.0.0" 代表監聽所有網路介面 (讓區域網路內的其他裝置可以連線)
    # port=8000 是連接埠
    uvicorn.run(app, host="0.0.0.0", port=8000)
