#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BLE IMU 資料接收程式
同時監聽自定義IMU服務和UART服務
"""

import asyncio
import struct
from bleak import BleakClient, BleakScanner
import nest_asyncio

# 允許嵌套事件循環（Spyder需要）
nest_asyncio.apply()

class BLEIMUReceiver:
    def __init__(self):
        self.device_name = "SmartRacket"
        
        # 自定義IMU服務
        self.imu_service_uuid = "0769bb8e-b496-4fdd-b53b-87462ff423d0"
        self.imu_characteristic_uuid = "8ee82f5b-76c7-4170-8f49-fff786257090"
        
        # UART服務
        self.uart_service_uuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        self.uart_tx_uuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        
        self.connected = False
        self.data_count = 0
        self.buffer = ""  # 用於拼接被截斷的UART資料
        
    def imu_notification_handler(self, sender, data):
        """自定義IMU服務通知處理器"""
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
                voltage = struct.unpack('<H', data[28:30])[0] / 100.0
                
                self.data_count += 1
                print(f"IMU資料包 #{self.data_count:4d}:")
                print(f"  時間戳: {timestamp}")
                print(f"  加速度: [{accelX:.6f}, {accelY:.6f}, {accelZ:.6f}]")
                print(f"  角速度: [{gyroX:.6f}, {gyroY:.6f}, {gyroZ:.6f}]")
                print(f"  電壓: {voltage:.2f}V")
                print("-" * 50)
            else:
                print(f"IMU資料長度錯誤: {len(data)} bytes")
        except Exception as e:
            print(f"IMU資料解析錯誤: {e}")
    
    def uart_notification_handler(self, sender, data):
        """UART服務通知處理器"""
        try:
            # 將bytes轉換為字串
            message = data.decode('utf-8')
            
            # 拼接資料到緩衝區
            self.buffer += message
            
            # 檢查是否有完整的行
            while '\n' in self.buffer:
                line, self.buffer = self.buffer.split('\n', 1)
                line = line.strip()
                
                if line and ',' in line:
                    parts = line.split(',')
                    if len(parts) >= 8:
                        self.data_count += 1
                        timestamp = parts[0]
                        accelX, accelY, accelZ = parts[1], parts[2], parts[3]
                        gyroX, gyroY, gyroZ = parts[4], parts[5], parts[6]
                        voltage = parts[7]
                        
                        print(f"UART資料包 #{self.data_count:4d}:")
                        print(f"  時間戳: {timestamp}")
                        print(f"  加速度: [{accelX}, {accelY}, {accelZ}]")
                        print(f"  角速度: [{gyroX}, {gyroY}, {gyroZ}]")
                        print(f"  電壓: {voltage}")
                        print("-" * 50)
                    else:
                        print(f"UART資料不完整: {line}")
                        
        except Exception as e:
            print(f"UART資料解析錯誤: {e}")
    
    async def scan_and_connect(self):
        """掃描並連接BLE設備"""
        print("正在掃描BLE設備...")
        
        try:
            devices = await BleakScanner.discover(timeout=10.0)
            target_device = None
            
            print(f"找到 {len(devices)} 個BLE設備:")
            for device in devices:
                print(f"  - {device.name or 'Unknown'} ({device.address})")
                if device.name and self.device_name in device.name:
                    target_device = device
                    print(f"  [OK] 找到目標設備: {device.name}")
            
            if not target_device:
                print(f"未找到設備: {self.device_name}")
                return False
            
            print(f"正在連接到 {target_device.name}...")
            self.client = BleakClient(target_device.address)
            await self.client.connect()
            print("BLE連接成功!")
            self.connected = True
            return True
            
        except Exception as e:
            print(f"BLE掃描/連接失敗: {e}")
            return False
    
    async def run(self):
        """主執行迴圈"""
        if not await self.scan_and_connect():
            return
        
        try:
            # 啟動兩種服務的通知
            print("啟動IMU服務通知...")
            await self.client.start_notify(self.imu_characteristic_uuid, self.imu_notification_handler)
            
            print("啟動UART服務通知...")
            await self.client.start_notify(self.uart_tx_uuid, self.uart_notification_handler)
            
            print("開始接收資料...")
            print("按 Ctrl+C 停止")
            print("=" * 60)
            
            # 保持連接
            while True:
                await asyncio.sleep(1)
                
        except KeyboardInterrupt:
            print("\n停止接收...")
        except Exception as e:
            print(f"執行錯誤: {e}")
        finally:
            if self.client and self.connected:
                await self.client.disconnect()
                print("BLE連接已斷開")

def run_ble_receiver():
    """Spyder專用執行函數"""
    async def main():
        receiver = BLEIMUReceiver()
        await receiver.run()
    
    # 在Spyder中運行
    asyncio.run(main())

if __name__ == "__main__":
    run_ble_receiver()
