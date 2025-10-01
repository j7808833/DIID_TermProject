#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BLE IMU GUI 程式
使用tkinter創建GUI介面，連接nRF52840並顯示IMU資料
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import threading
import queue
import struct
import time
import math
from bleak import BleakClient, BleakScanner
import asyncio
import nest_asyncio

# 允許嵌套事件循環
nest_asyncio.apply()

class BLEIMUGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("BLE IMU 資料監控程式")
        self.root.geometry("800x600")
        
        # BLE相關變數
        self.client = None
        self.connected = False
        self.data_queue = queue.Queue()
        self.running = False
        
        # IMU資料
        self.accel = [0.0, 0.0, 0.0]
        self.gyro = [0.0, 0.0, 0.0]
        self.voltage = 0.0
        self.timestamp = 0
        self.data_count = 0
        
        # BLE設定
        self.device_name = "SmartRacket"
        self.service_uuid = "0769bb8e-b496-4fdd-b53b-87462ff423d0"
        self.characteristic_uuid = "8ee82f5b-76c7-4170-8f49-fff786257090"
        
        # 創建GUI
        self.create_widgets()
        
        # 啟動資料更新
        self.update_data()
    
    def create_widgets(self):
        """創建GUI元件"""
        # 主框架
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 配置網格權重
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        
        # 標題
        title_label = ttk.Label(main_frame, text="BLE IMU 資料監控程式", 
                               font=("Arial", 16, "bold"))
        title_label.grid(row=0, column=0, columnspan=3, pady=(0, 20))
        
        # 連接控制區域
        conn_frame = ttk.LabelFrame(main_frame, text="BLE 連接控制", padding="10")
        conn_frame.grid(row=1, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=(0, 10))
        
        # 設備名稱輸入
        ttk.Label(conn_frame, text="設備名稱:").grid(row=0, column=0, sticky=tk.W, padx=(0, 5))
        self.device_name_var = tk.StringVar(value=self.device_name)
        device_entry = ttk.Entry(conn_frame, textvariable=self.device_name_var, width=20)
        device_entry.grid(row=0, column=1, sticky=(tk.W, tk.E), padx=(0, 10))
        
        # 連接按鈕
        self.connect_btn = ttk.Button(conn_frame, text="搜尋並連接", 
                                     command=self.toggle_connection)
        self.connect_btn.grid(row=0, column=2, padx=(0, 5))
        
        # 狀態標籤
        self.status_var = tk.StringVar(value="未連接")
        status_label = ttk.Label(conn_frame, textvariable=self.status_var, 
                                foreground="red", font=("Arial", 10, "bold"))
        status_label.grid(row=0, column=3, padx=(10, 0))
        
        # 資料顯示區域
        data_frame = ttk.LabelFrame(main_frame, text="IMU 資料顯示", padding="10")
        data_frame.grid(row=2, column=0, columnspan=3, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(0, 10))
        data_frame.columnconfigure(1, weight=1)
        
        # 加速度計資料
        ttk.Label(data_frame, text="加速度計 (g):", font=("Arial", 12, "bold")).grid(row=0, column=0, sticky=tk.W, pady=(0, 5))
        self.accel_frame = ttk.Frame(data_frame)
        self.accel_frame.grid(row=1, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        
        ttk.Label(self.accel_frame, text="X:").grid(row=0, column=0, padx=(0, 5))
        self.accel_x_var = tk.StringVar(value="0.000")
        ttk.Label(self.accel_frame, textvariable=self.accel_x_var, 
                 font=("Arial", 12), foreground="red").grid(row=0, column=1, padx=(0, 20))
        
        ttk.Label(self.accel_frame, text="Y:").grid(row=0, column=2, padx=(0, 5))
        self.accel_y_var = tk.StringVar(value="0.000")
        ttk.Label(self.accel_frame, textvariable=self.accel_y_var, 
                 font=("Arial", 12), foreground="green").grid(row=0, column=3, padx=(0, 20))
        
        ttk.Label(self.accel_frame, text="Z:").grid(row=0, column=4, padx=(0, 5))
        self.accel_z_var = tk.StringVar(value="0.000")
        ttk.Label(self.accel_frame, textvariable=self.accel_z_var, 
                 font=("Arial", 12), foreground="blue").grid(row=0, column=5)
        
        # 陀螺儀資料
        ttk.Label(data_frame, text="陀螺儀 (度/秒):", font=("Arial", 12, "bold")).grid(row=2, column=0, sticky=tk.W, pady=(0, 5))
        self.gyro_frame = ttk.Frame(data_frame)
        self.gyro_frame.grid(row=3, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        
        ttk.Label(self.gyro_frame, text="X:").grid(row=0, column=0, padx=(0, 5))
        self.gyro_x_var = tk.StringVar(value="0.00")
        ttk.Label(self.gyro_frame, textvariable=self.gyro_x_var, 
                 font=("Arial", 12), foreground="red").grid(row=0, column=1, padx=(0, 20))
        
        ttk.Label(self.gyro_frame, text="Y:").grid(row=0, column=2, padx=(0, 5))
        self.gyro_y_var = tk.StringVar(value="0.00")
        ttk.Label(self.gyro_frame, textvariable=self.gyro_y_var, 
                 font=("Arial", 12), foreground="green").grid(row=0, column=3, padx=(0, 20))
        
        ttk.Label(self.gyro_frame, text="Z:").grid(row=0, column=4, padx=(0, 5))
        self.gyro_z_var = tk.StringVar(value="0.00")
        ttk.Label(self.gyro_frame, textvariable=self.gyro_z_var, 
                 font=("Arial", 12), foreground="blue").grid(row=0, column=5)
        
        # 電壓資料
        ttk.Label(data_frame, text="電池電壓 (V):", font=("Arial", 12, "bold")).grid(row=4, column=0, sticky=tk.W, pady=(0, 5))
        self.voltage_var = tk.StringVar(value="0.00")
        voltage_label = ttk.Label(data_frame, textvariable=self.voltage_var, 
                                 font=("Arial", 14), foreground="orange")
        voltage_label.grid(row=4, column=1, sticky=tk.W, pady=(0, 10))
        
        # 統計資訊
        stats_frame = ttk.Frame(data_frame)
        stats_frame.grid(row=5, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(10, 0))
        
        ttk.Label(stats_frame, text="資料包計數:").grid(row=0, column=0, padx=(0, 5))
        self.count_var = tk.StringVar(value="0")
        ttk.Label(stats_frame, textvariable=self.count_var, 
                 font=("Arial", 12)).grid(row=0, column=1, padx=(0, 20))
        
        ttk.Label(stats_frame, text="時間戳:").grid(row=0, column=2, padx=(0, 5))
        self.timestamp_var = tk.StringVar(value="0")
        ttk.Label(stats_frame, textvariable=self.timestamp_var, 
                 font=("Arial", 12)).grid(row=0, column=3)
        
        # 日誌區域
        log_frame = ttk.LabelFrame(main_frame, text="連接日誌", padding="10")
        log_frame.grid(row=3, column=0, columnspan=3, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(0, 10))
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        
        self.log_text = scrolledtext.ScrolledText(log_frame, height=8, width=80)
        self.log_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 配置主框架網格權重
        main_frame.rowconfigure(3, weight=1)
    
    def log_message(self, message):
        """在日誌區域添加訊息"""
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"[{timestamp}] {message}\n")
        self.log_text.see(tk.END)
        self.root.update_idletasks()
    
    def toggle_connection(self):
        """切換連接狀態"""
        if not self.connected:
            self.start_connection()
        else:
            self.disconnect()
    
    def start_connection(self):
        """開始BLE連接"""
        self.device_name = self.device_name_var.get()
        self.connect_btn.config(text="連接中...", state="disabled")
        self.status_var.set("搜尋中...")
        
        # 在背景線程中執行連接
        thread = threading.Thread(target=self.connect_ble)
        thread.daemon = True
        thread.start()
    
    def connect_ble(self):
        """在背景線程中連接BLE"""
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            
            self.log_message("正在掃描BLE設備...")
            devices = loop.run_until_complete(BleakScanner.discover(timeout=10.0))
            
            target_device = None
            self.log_message(f"找到 {len(devices)} 個BLE設備:")
            
            for device in devices:
                device_info = f"  - {device.name or 'Unknown'} ({device.address})"
                self.log_message(device_info)
                if device.name and self.device_name in device.name:
                    target_device = device
                    self.log_message(f"  [OK] 找到目標設備: {device.name}")
            
            if not target_device:
                self.log_message(f"未找到設備: {self.device_name}")
                self.root.after(0, self.connection_failed)
                return
            
            self.log_message(f"正在連接到 {target_device.name}...")
            self.client = BleakClient(target_device.address)
            loop.run_until_complete(self.client.connect())
            
            self.log_message("BLE連接成功!")
            self.connected = True
            self.running = True
            
            # 啟動IMU服務的通知
            self.log_message("啟動IMU服務通知...")
            loop.run_until_complete(self.client.start_notify(self.characteristic_uuid, self.notification_handler))
            
            self.log_message("開始接收IMU資料...")
            self.root.after(0, self.connection_success)
            
            # 保持連接
            while self.running and self.connected:
                try:
                    if not self.client.is_connected:
                        self.log_message("BLE連接已斷開!")
                        self.connected = False
                        break
                    loop.run_until_complete(asyncio.sleep(0.01))
                except Exception as e:
                    self.log_message(f"BLE連接監控錯誤: {e}")
                    self.connected = False
                    break
            
        except Exception as e:
            self.log_message(f"BLE連接失敗: {e}")
            self.root.after(0, self.connection_failed)
    
    def notification_handler(self, sender, data):
        """BLE通知處理器"""
        try:
            if len(data) == 30:
                # 解析二進位資料
                timestamp = struct.unpack('<I', data[0:4])[0]
                accelX = struct.unpack('<f', data[4:8])[0]
                accelY = struct.unpack('<f', data[8:12])[0]
                accelZ = struct.unpack('<f', data[12:16])[0]
                gyroX = struct.unpack('<f', data[16:20])[0]
                gyroY = struct.unpack('<f', data[20:24])[0]
                gyroZ = struct.unpack('<f', data[24:28])[0]
                voltageRaw = struct.unpack('<H', data[28:30])[0]
                
                # 將資料放入佇列
                imu_data = {
                    'accel': [accelX, accelY, accelZ],
                    'gyro': [gyroX, gyroY, gyroZ],
                    'voltage': voltageRaw / 100.0,
                    'timestamp': timestamp
                }
                self.data_queue.put(imu_data)
                
        except Exception as e:
            self.log_message(f"BLE資料解析錯誤: {e}")
    
    def connection_success(self):
        """連接成功後更新UI"""
        self.connect_btn.config(text="斷開連接", state="normal")
        self.status_var.set("已連接")
        self.status_var.set("已連接")
    
    def connection_failed(self):
        """連接失敗後更新UI"""
        self.connect_btn.config(text="搜尋並連接", state="normal")
        self.status_var.set("連接失敗")
    
    def disconnect(self):
        """斷開BLE連接"""
        self.running = False
        self.connected = False
        
        if self.client:
            try:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                loop.run_until_complete(self.client.disconnect())
            except:
                pass
            self.client = None
        
        self.connect_btn.config(text="搜尋並連接", state="normal")
        self.status_var.set("已斷開")
        self.log_message("BLE連接已斷開")
    
    def update_data(self):
        """更新資料顯示"""
        try:
            # 處理BLE資料佇列
            while not self.data_queue.empty():
                data = self.data_queue.get_nowait()
                self.accel = data['accel']
                self.gyro = data['gyro']
                self.voltage = data['voltage']
                self.timestamp = data['timestamp']
                self.data_count += 1
                
                # 更新UI
                self.accel_x_var.set(f"{self.accel[0]:.3f}")
                self.accel_y_var.set(f"{self.accel[1]:.3f}")
                self.accel_z_var.set(f"{self.accel[2]:.3f}")
                
                self.gyro_x_var.set(f"{self.gyro[0]:.2f}")
                self.gyro_y_var.set(f"{self.gyro[1]:.2f}")
                self.gyro_z_var.set(f"{self.gyro[2]:.2f}")
                
                self.voltage_var.set(f"{self.voltage:.2f}")
                self.count_var.set(str(self.data_count))
                self.timestamp_var.set(str(self.timestamp))
                
        except queue.Empty:
            pass
        except Exception as e:
            self.log_message(f"資料更新錯誤: {e}")
        
        # 每50ms更新一次
        self.root.after(50, self.update_data)
    
    def on_closing(self):
        """程式關閉時的清理"""
        self.running = False
        if self.connected:
            self.disconnect()
        self.root.destroy()

def main():
    """主函數"""
    root = tk.Tk()
    app = BLEIMUGUI(root)
    
    # 設定關閉事件
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    
    # 啟動GUI
    root.mainloop()

if __name__ == "__main__":
    main()
