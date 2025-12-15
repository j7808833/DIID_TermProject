import asyncio
import websockets
import json
import time
import random
import math
import argparse
# import pandas as pd # 如果要讀 Excel

# --- 設定 ---
# SERVER_URL = "ws://localhost:8000/ws/predict"
SERVER_URL = "wss://diid-termproject-v2.onrender.com/ws/predict"
WINDOW_SIZE = 40  # 模擬每次傳送 40 frames
SAMPLE_RATE = 50  # 50 Hz

# --- 產生假資料 (Dummy Data Generator) ---
def generate_dummy_window(start_time):
    """
    產生一個模擬的揮拍視窗資料。
    偶爾產生一個「大動作」來模擬殺球。
    """
    frames = []
    is_smash = random.random() < 0.3 # 30% 機率產生大數據
    
    base_acc = 10.0 if is_smash else 1.0
    
    for i in range(WINDOW_SIZE):
        t = start_time + (i * 0.02) # 20ms 一筆
        
        # 用 Sin 波模擬揮動
        progress = i / WINDOW_SIZE
        wave = math.sin(progress * math.pi) * base_acc
        
        frame = {
            "ts": t,
            "acc": [
                random.uniform(-1, 1) + wave, # X
                random.uniform(-1, 1) + wave * 2, # Y (主力軸)
                random.uniform(9, 10) # Z (重力)
            ],
            "gyro": [
                random.uniform(-100, 100) + wave * 100,
                random.uniform(-100, 100),
                random.uniform(-100, 100)
            ]
        }
        frames.append(frame)
    
    return frames

async def simulate_app():
    print(f"Connecting to {SERVER_URL}...")
    try:
        async with websockets.connect(SERVER_URL) as websocket:
            print("Connected! Start sending data (Press Ctrl+C to stop)...")
            
            sequence = 0
            while True:
                # 1. 準備數據
                current_time = time.time()
                window_data = generate_dummy_window(current_time)
                
                payload = {
                    "client_id": "simulated_device_001",
                    "data": window_data
                }
                
                # 2. 發送 Request
                # 模擬真實情況：動作發生後才會發送，所以我們每隔幾秒發送一次
                print(f"[{sequence}] Sending {len(window_data)} frames...")
                await websocket.send(json.dumps(payload))
                
                # 3. 等待回應
                response_txt = await websocket.recv()
                response = json.loads(response_txt)
                
                # 4. 顯示結果
                if response["display"]:
                    print(f"\n>>> UI UPDATE REQUIRED! <<<")
                    print(f"   TYPE: {response['type']}")
                    print(f"   SPEED: {response['speed']} km/h")
                    print(f"   MSG: {response['message']}\n")
                else:
                    print(f"   Result: {response['type']} (Hidden)")
                
                sequence += 1
                
                # 模擬人類擊球間隔 (2-4秒一次)
                delay = random.uniform(2, 4)
                print(f"Waiting {delay:.1f}s for next swing...")
                await asyncio.sleep(delay)
                
    except ConnectionRefusedError:
        print("Error: Could not connect to server. Make sure 'server/main.py' is running.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    try:
        # Check if we should install dependencies first? 
        # No, leave that to user.
        print("== Badminton App Simulator ==")
        asyncio.run(simulate_app())
    except KeyboardInterrupt:
        print("\nStopped.")
