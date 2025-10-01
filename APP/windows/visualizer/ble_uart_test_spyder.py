#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BLE UART 測試程式 - Spyder版本
使用Nordic UART Service (NUS) 接收Arduino資料
專門為Spyder環境優化
"""

import asyncio
import struct
from bleak import BleakClient, BleakScanner
import nest_asyncio

# 允許嵌套事件循環（Spyder需要）
nest_asyncio.apply()

class BLEUARTTest:
    def __init__(self):
        self.device_name = "SmartRacket"
        self.uart_service_uuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        self.uart_tx_uuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        self.uart_rx_uuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
        self.connected = False
        self.data_count = 0
        
    def uart_notification_handler(self, sender, data):
        """UART通知處理器"""
        try:
            # 將bytes轉換為字串
            message = data.decode('utf-8')
            self.data_count += 1
            
            print(f"資料包 #{self.data_count:4d}: {message.strip()}")
            
            # 如果是CSV格式，可以解析
            if ',' in message:
                parts = message.strip().split(',')
                if len(parts) >= 8:
                    timestamp = parts[0]
                    accelX, accelY, accelZ = parts[1], parts[2], parts[3]
                    gyroX, gyroY, gyroZ = parts[4], parts[5], parts[6]
                    voltage = parts[7]
                    
                    print(f"  時間戳: {timestamp}")
                    print(f"  加速度: [{accelX}, {accelY}, {accelZ}]")
                    print(f"  角速度: [{gyroX}, {gyroY}, {gyroZ}]")
                    print(f"  電壓: {voltage}")
                    print("-" * 50)
                    
        except Exception as e:
            print(f"資料解析錯誤: {e}")
    
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
            # 啟動UART通知
            await self.client.start_notify(self.uart_tx_uuid, self.uart_notification_handler)
            print("開始接收UART資料...")
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

def run_ble_test():
    """Spyder專用執行函數"""
    async def main():
        test = BLEUARTTest()
        await test.run()
    
    # 在Spyder中運行
    asyncio.run(main())

if __name__ == "__main__":
    run_ble_test()
