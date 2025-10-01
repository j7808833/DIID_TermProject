#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IMU 3D 視覺化程式
接收Arduino串列資料，即時顯示立體三軸指標
"""

import serial
import time
import math
import numpy as np
import pygame
from pygame.locals import *
from OpenGL.GL import *
from OpenGL.GLU import *

class IMUVisualizer:
    def __init__(self, port='COM3', baudrate=9600):
        """初始化IMU視覺化器"""
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.running = True
        
        # IMU資料
        self.accel = [0, 0, 0]  # 加速度
        self.gyro = [0, 0, 0]   # 角速度
        self.temp = 0           # 溫度
        
        # 姿態角度（歐拉角）
        self.roll = 0   # 繞X軸旋轉
        self.pitch = 0  # 繞Y軸旋轉
        self.yaw = 0    # 繞Z軸旋轉
        
        # 初始化Pygame和OpenGL
        self.init_display()
        
    def init_display(self):
        """初始化顯示視窗"""
        pygame.init()
        self.screen = pygame.display.set_mode((800, 600), DOUBLEBUF | OPENGL)
        pygame.display.set_caption("IMU 3D 視覺化 - SmartRacket")
        
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
        
    def connect_serial(self):
        """連接串列埠"""
        try:
            self.serial_conn = serial.Serial(self.port, self.baudrate, timeout=1)
            print(f"已連接到 {self.port}，波特率: {self.baudrate}")
            time.sleep(2)  # 等待Arduino重啟
            return True
        except Exception as e:
            print(f"串列連接失敗: {e}")
            return False
    
    def read_imu_data(self):
        """讀取IMU資料"""
        if not self.serial_conn or not self.serial_conn.in_waiting:
            return False
            
        try:
            line = self.serial_conn.readline().decode('utf-8').strip()
            if line and ',' in line:
                data = line.split(',')
                if len(data) >= 8:
                    # 解析資料：timestamp,accelX,accelY,accelZ,gyroX,gyroY,gyroZ,temp
                    self.accel = [float(data[1]), float(data[2]), float(data[3])]
                    self.gyro = [float(data[4]), float(data[5]), float(data[6])]
                    self.temp = float(data[7])
                    
                    # 計算姿態角度（簡化版）
                    self.calculate_attitude()
                    return True
        except Exception as e:
            print(f"資料讀取錯誤: {e}")
            
        return False
    
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
    
    def draw_info_panel(self):
        """繪製資訊面板"""
        # 這裡可以添加文字顯示，但需要額外的文字渲染庫
        pass
    
    def render(self):
        """渲染場景"""
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        
        # 繪製三軸指標
        self.draw_axes()
        
        # 繪製參考網格
        self.draw_reference_grid()
        
        pygame.display.flip()
    
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
    
    def run(self):
        """主執行迴圈"""
        if not self.connect_serial():
            print("無法連接串列埠，使用模擬資料")
            self.simulate_data = True
        else:
            self.simulate_data = False
        
        print("IMU 3D 視覺化程式啟動")
        print("按 ESC 退出，按 R 重置姿態")
        
        clock = pygame.time.Clock()
        
        while self.running:
            # 處理事件
            self.handle_events()
            
            # 讀取IMU資料
            if not self.simulate_data:
                self.read_imu_data()
            else:
                # 模擬資料（用於測試）
                self.simulate_imu_data()
            
            # 渲染場景
            self.render()
            
            # 控制幀率
            clock.tick(60)
        
        # 清理資源
        if self.serial_conn:
            self.serial_conn.close()
        pygame.quit()
    
    def simulate_imu_data(self):
        """模擬IMU資料（用於測試）"""
        t = time.time()
        self.roll = 30 * math.sin(t)
        self.pitch = 20 * math.cos(t * 0.7)
        self.yaw = 15 * math.sin(t * 0.5)

def main():
    """主函數"""
    # 根據您的系統調整串列埠
    # Windows: 'COM3', 'COM4', etc.
    # Linux/Mac: '/dev/ttyUSB0', '/dev/ttyACM0', etc.
    
    port = 'COM14'  # 您的Arduino連接埠
    baudrate = 9600  # 波特率
    
    visualizer = IMUVisualizer(port=port, baudrate=baudrate)
    visualizer.run()

if __name__ == "__main__":
    main()
