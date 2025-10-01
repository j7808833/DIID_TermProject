#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BLE IMU 3D 視覺化程式
接收Arduino BLE藍牙資料，即時顯示立體三軸指標
"""

import time
import math
import numpy as np
import pygame
from pygame.locals import *
from OpenGL.GL import *
from OpenGL.GLU import *
import struct
from bleak import BleakClient, BleakScanner
import asyncio

class BLEIMUVisualizer:
    def __init__(self):
        """初始化BLE IMU視覺化器"""
        self.running = True
        self.connected = False
        self.client = None
        
        # IMU資料
        self.accel = [0, 0, 0]  # 加速度
        self.gyro = [0, 0, 0]   # 角速度
        self.temp = 0           # 溫度
        
        # 姿態角度（歐拉角）
        self.roll = 0   # 繞X軸旋轉
        self.pitch = 0  # 繞Y軸旋轉
        self.yaw = 0    # 繞Z軸旋轉
        
        # BLE設定
        self.device_name = "SmartRacket"
        self.service_uuid = "0769bb8e-b496-4fdd-b53b-87462ff423d0"
        self.characteristic_uuid = "8ee82f5b-76c7-4170-8f49-fff786257090"
        
        # 初始化Pygame和OpenGL
        self.init_display()
        
    def init_display(self):
        """初始化顯示視窗"""
        pygame.init()
        self.screen = pygame.display.set_mode((800, 600), DOUBLEBUF | OPENGL)
        pygame.display.set_caption("BLE IMU 3D 視覺化 - SmartRacket")
        
        # 設定OpenGL視角
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_LIGHTING)
        glEnable(GL_LIGHT0)
        glEnable(GL_COLOR_MATERIAL)
        
        # 設定光源
        glLightfv(GL_LIGHT0, GL_POSITION, [0, 0, 1, 0])
        glLightfv(GL_LIGHT0, GL_AMBIENT, [0.3, 0.3, 0.3, 1])
        glLightfv(GL_LIGHT0, GL_DIFFUSE, [0.8, 0.8, 0.8, 1])
        
        # 設定視角
        gluPerspective(45, 800/600, 0.1, 50.0)
        glTranslatef(0.0, 0.0, -5.0)
    
    async def scan_and_connect(self):
        """掃描並連接BLE設備"""
        print("正在掃描BLE設備...")
        
        try:
            devices = await BleakScanner.discover(timeout=5.0)
            target_device = None
            
            for device in devices:
                if device.name and self.device_name in device.name:
                    target_device = device
                    print(f"找到設備: {device.name} ({device.address})")
                    break
            
            if not target_device:
                print(f"未找到設備: {self.device_name}")
                return False
            
            self.client = BleakClient(target_device.address)
            await self.client.connect()
            print("BLE連接成功!")
            self.connected = True
            return True
        except Exception as e:
            print(f"BLE掃描/連接失敗: {e}")
            print("將使用模擬資料模式")
            return False
    
    def notification_handler(self, sender, data):
        """BLE通知處理器"""
        try:
            if len(data) == 30:
                # 解析二進位資料
                timestamp = struct.unpack('<I', data[0:4])[0]  # 4 bytes timestamp
                accelX = struct.unpack('<f', data[4:8])[0]     # 4 bytes accelX
                accelY = struct.unpack('<f', data[8:12])[0]    # 4 bytes accelY
                accelZ = struct.unpack('<f', data[12:16])[0]   # 4 bytes accelZ
                gyroX = struct.unpack('<f', data[16:20])[0]    # 4 bytes gyroX
                gyroY = struct.unpack('<f', data[20:24])[0]    # 4 bytes gyroY
                gyroZ = struct.unpack('<f', data[24:28])[0]    # 4 bytes gyroZ
                tempC = struct.unpack('<f', data[28:30] + b'\x00\x00')[0]  # 2 bytes tempC
                
                self.accel = [accelX, accelY, accelZ]
                self.gyro = [gyroX, gyroY, gyroZ]
                self.temp = tempC
                
                # 計算姿態角度
                self.calculate_attitude()
        except Exception as e:
            print(f"資料解析錯誤: {e}")
    
    def calculate_attitude(self):
        """計算姿態角度"""
        # 使用加速度計計算俯仰角和滾轉角
        ax, ay, az = self.accel
        
        # 計算俯仰角 (pitch) 和滾轉角 (roll)
        self.pitch = math.atan2(-ax, math.sqrt(ay*ay + az*az)) * 180 / math.pi
        self.roll = math.atan2(ay, az) * 180 / math.pi
        
        # 使用陀螺儀積分計算偏航角 (yaw)
        # 注意：這只是簡化版本，實際應用需要更複雜的融合算法
        self.yaw += self.gyro[2] * 0.02  # 假設20ms更新間隔
    
    def draw_axes(self):
        """繪製三軸指標"""
        glPushMatrix()
        
        # 旋轉到當前姿態
        glRotatef(self.roll, 1, 0, 0)   # 繞X軸旋轉
        glRotatef(self.pitch, 0, 1, 0)  # 繞Y軸旋轉
        glRotatef(self.yaw, 0, 0, 1)    # 繞Z軸旋轉
        
        # 繪製X軸（紅色）
        glColor3f(1, 0, 0)
        glBegin(GL_LINES)
        glVertex3f(0, 0, 0)
        glVertex3f(2, 0, 0)
        glEnd()
        
        # 繪製Y軸（綠色）
        glColor3f(0, 1, 0)
        glBegin(GL_LINES)
        glVertex3f(0, 0, 0)
        glVertex3f(0, 2, 0)
        glEnd()
        
        # 繪製Z軸（藍色）
        glColor3f(0, 0, 1)
        glBegin(GL_LINES)
        glVertex3f(0, 0, 0)
        glVertex3f(0, 0, 2)
        glEnd()
        
        # 繪製軸端箭頭
        self.draw_arrow(2, 0, 0, 1, 0, 0)  # X軸箭頭
        self.draw_arrow(0, 2, 0, 0, 1, 0)  # Y軸箭頭
        self.draw_arrow(0, 0, 2, 0, 0, 1)  # Z軸箭頭
        
        glPopMatrix()
    
    def draw_arrow(self, x, y, z, r, g, b):
        """繪製箭頭"""
        glColor3f(r, g, b)
        glBegin(GL_TRIANGLES)
        # 簡化的箭頭形狀
        glVertex3f(x, y, z)
        glVertex3f(x-0.1, y-0.1, z-0.1)
        glVertex3f(x-0.1, y+0.1, z-0.1)
        glEnd()
    
    def draw_reference_grid(self):
        """繪製參考網格"""
        glColor3f(0.3, 0.3, 0.3)
        glBegin(GL_LINES)
        
        # 繪製網格線
        for i in range(-5, 6):
            # X方向網格線
            glVertex3f(i, -5, 0)
            glVertex3f(i, 5, 0)
            # Y方向網格線
            glVertex3f(-5, i, 0)
            glVertex3f(5, i, 0)
        
        glEnd()
    
    def render(self):
        """渲染場景"""
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        
        # 繪製三軸指標
        self.draw_axes()
        
        # 繪製參考網格
        self.draw_reference_grid()
        
        pygame.display.flip()
    
    def handle_events(self):
        """處理事件"""
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    self.running = False
                elif event.key == pygame.K_r:
                    # 重置姿態
                    self.roll = self.pitch = self.yaw = 0
    
    async def run(self):
        """主執行迴圈"""
        # 連接BLE設備
        if not await self.scan_and_connect():
            print("無法連接BLE設備，使用模擬資料")
            self.simulate_data = True
        else:
            # 啟動通知
            await self.client.start_notify(self.characteristic_uuid, self.notification_handler)
            self.simulate_data = False
        
        print("BLE IMU 3D 視覺化程式啟動")
        print("按 ESC 退出，按 R 重置姿態")
        
        clock = pygame.time.Clock()
        
        while self.running:
            # 處理事件
            self.handle_events()
            
            # 模擬資料（如果沒有BLE連接）
            if self.simulate_data:
                self.simulate_imu_data()
            
            # 渲染場景
            self.render()
            
            # 控制幀率
            clock.tick(60)
            
            # 讓出控制權給asyncio
            await asyncio.sleep(0.001)
        
        # 清理資源
        if self.client and self.connected:
            await self.client.disconnect()
        pygame.quit()
    
    def simulate_imu_data(self):
        """模擬IMU資料（用於測試）"""
        t = time.time()
        self.roll = 30 * math.sin(t)
        self.pitch = 20 * math.cos(t * 0.7)
        self.yaw = 15 * math.sin(t * 0.5)

async def main():
    """主函數"""
    visualizer = BLEIMUVisualizer()
    await visualizer.run()

if __name__ == "__main__":
    asyncio.run(main())