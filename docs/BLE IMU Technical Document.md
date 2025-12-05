# 🏸 Smart Badminton Racket IMU Sensor System - Complete Technical Documentation

## 📋 Table of Contents

1. [System Overview](#system-overview)
2. [Hardware Specifications](#hardware-specifications)
3. [BLE Communication Protocol](#ble-communication-protocol)
4. [Data Format Specifications](#data-format-specifications)
5. [Mobile BLE Receiver Development Guide](#mobile-ble-receiver-development-guide)
6. [Mobile App Results Display & UI Design](#mobile-app-results-display--ui-design)
7. [Pose Calibration Function](#pose-calibration-function)
8. [Firebase Data Transmission](#firebase-data-transmission)
9. [Database Design](#database-design)
10. [AI Training Data Preparation](#ai-training-data-preparation)
11. [System Architecture Flowchart](#system-architecture-flowchart)
12. [Development Notes](#development-notes)
13. [Troubleshooting](#troubleshooting)

---

## System Overview

This system is an intelligent badminton racket sensor that uses an IMU (Inertial Measurement Unit) sensor embedded in the racket handle to collect acceleration and angular velocity data in real-time during racket swings. The data is transmitted to a mobile App via BLE (Bluetooth Low Energy), then uploaded to Firebase Firestore cloud database, and finally used for AI model training to identify different stroke types.

### Core Function Flow

```
Badminton Racket Sensor → BLE Transmission → Mobile App → Zero-Point Calibration → Real-time Display → Chart Visualization → Firebase Upload → Remote AI Recognition → Results Display
```

### Mobile App Core Features

The Android mobile App provides the following key features:

1. **BLE Connection Management**: Connect to specific racket device (SmartRacket)
2. **Zero-Point Calibration**: Manual calibration to zero sensor readings when racket is stationary
3. **Real-time Data Display**: Display six-axis sensor values in real-time
4. **Chart Visualization**: Display six-axis curves with 100ms sampling interval
5. **Firebase Data Upload**: Batch upload calibrated data for AI training
6. **CSV Local Data Storage**: Save data in CSV format for easy Excel access
7. **Smart Disconnection Handling**: Automatically stop recording and clean up resources on BLE disconnection
8. **Remote AI Recognition**: Receive recognition results from server (5 stroke types + smash speed)

### Stroke Recognition Types

The system recognizes **5 stroke types**:
- **smash** - Smash shot
- **drive** - Drive shot
- **toss** - Toss shot
- **drop** - Drop shot
- **other** - Other strokes

Additionally, for smash shots, the system calculates and displays the **ball speed**.

---

## Hardware Specifications

### Core Components

| Component | Model | Specifications | Function |
|-----------|-------|----------------|----------|
| **Main Board** | Seeed XIAO nRF52840 Sense | 20×17.5×5 mm | ARM Cortex-M4F, 256KB Flash, 32KB RAM |
| **Sensor** | LSM6DS3TR | - | Six-axis IMU (Accelerometer + Gyroscope) |
| **Battery** | 501230 | - | 3.7V Lithium Battery, 150mAh |
| **Charging Interface** | Type-C | 5×8.5×3.5 mm | USB Charging Interface |

### IMU Sensor Parameters

| Parameter | Accelerometer | Gyroscope |
|-----------|---------------|-----------|
| **Data Output Rate (ODR)** | 416 Hz | 416 Hz |
| **Measurement Range** | ±16G | ±2000 dps |
| **Bandwidth Setting** | 100 Hz | 400 Hz |
| **I²C Transmission Rate** | 400 kHz | 400 kHz |
| **Resolution** | 16-bit | 16-bit |

### Hardware Connection Configuration

```
Racket Handle Internal Configuration:
├── Type-C Interface (Charging)
├── Main Board (XIAO nRF52840 Sense)
│   ├── I2C Connection to LSM6DS3 (SDA, SCL)
│   ├── A0 Analog Input (Voltage Monitoring, P0.31/AIN7)
│   ├── P0_14 Digital Output (VBAT_ENABLE, controls voltage divider circuit)
│   └── P0_13 Digital Output (Charging Mode Control)
└── Battery (501230, 3.7V, 150mAh)
```

---

## BLE Communication Protocol

### Device Identification Information

- **Device Name**: `SmartRacket`
- **Bluetooth Version**: Bluetooth 5.0 (BLE)
- **Connection Mode**: Master-Slave Mode (Mobile phone as master, sensor as slave)

### BLE Service Architecture

#### 1. Service UUID
```
0769bb8e-b496-4fdd-b53b-87462ff423d0
```

#### 2. Characteristic UUID
```
8ee82f5b-76c7-4170-8f49-fff786257090
```

#### 3. Characteristic Properties
- **Read**: Supported
- **Notify**: Supported (Main method for receiving data)
- **Write**: Not Supported

### BLE Connection Flow

```
1. Sensor Startup → Initialize BLE Service → Start Advertising
2. Mobile App → Scan BLE Devices → Find "SmartRacket"
3. Mobile App → Initiate Connection Request
4. Sensor → Accept Connection → Establish BLE Connection
5. Mobile App → Subscribe to Notify
6. Sensor → Start Sending IMU Data (every 20ms)
```

### BLE Data Transmission Parameters

- **Transmission Frequency**: 50 Hz (transmit every 20ms)
- **Single Data Size**: 30 bytes
- **Transmission Method**: BLE Notification (Push mode, no need for mobile to actively read)
- **Advertising Interval**: 100ms (when not connected)

### Connection Status Management

```python
Connection Status Check Flow:
1. Continuously monitor connection status
2. Automatically re-advertise when connection is interrupted
3. Automatically disconnect and notify mobile when battery is low
4. Sensor enters power-saving mode after mobile disconnects
```

---

## Data Format Specifications

### Data Packet Structure (30 bytes)

#### Binary Format (Little-Endian)

| Offset | Length | Data Type | Field Name | Description |
|--------|--------|-----------|------------|-------------|
| 0-3 | 4 bytes | `uint32_t` | `timestamp` | Timestamp (millis(), unit: milliseconds) |
| 4-7 | 4 bytes | `float` | `accelX` | X-axis acceleration (unit: g, calibrated) |
| 8-11 | 4 bytes | `float` | `accelY` | Y-axis acceleration (unit: g, calibrated) |
| 12-15 | 4 bytes | `float` | `accelZ` | Z-axis acceleration (unit: g, calibrated, gravity subtracted) |
| 16-19 | 4 bytes | `float` | `gyroX` | X-axis angular velocity (unit: dps, calibrated) |
| 20-23 | 4 bytes | `float` | `gyroY` | Y-axis angular velocity (unit: dps, calibrated) |
| 24-27 | 4 bytes | `float` | `gyroZ` | Z-axis angular velocity (unit: dps, calibrated) |
| 28-29 | 2 bytes | `uint16_t` | `voltageRaw` | Raw voltage reading (10-bit: 0-1023, needs to be converted to 12-bit: 0-4095, using formula: V_BAT = RESULT × 8.11 / 4096) |

### Data Parsing Example (Python)

```python
import struct

def parse_imu_data(data: bytes) -> dict:
    """
    Parse 30 bytes IMU data packet
    
    Args:
        data: 30 bytes of binary data
    
    Returns:
        dict: Dictionary containing all sensor data
    """
    if len(data) != 30:
        raise ValueError(f"Data length error, should be 30 bytes, actually {len(data)} bytes")
    
    # Parse using Little-Endian format
    timestamp = struct.unpack('<I', data[0:4])[0]      # uint32_t
    accelX = struct.unpack('<f', data[4:8])[0]         # float
    accelY = struct.unpack('<f', data[8:12])[0]        # float
    accelZ = struct.unpack('<f', data[12:16])[0]       # float
    gyroX = struct.unpack('<f', data[16:20])[0]        # float
    gyroY = struct.unpack('<f', data[20:24])[0]        # float
    gyroZ = struct.unpack('<f', data[24:28])[0]        # float
    voltageRaw = struct.unpack('<H', data[28:30])[0]   # uint16_t (10-bit: 0-1023)
    
    # Convert 10-bit to 12-bit (nRF52840 SAADC is actually 12-bit)
    voltageRaw12bit = voltageRaw
    if voltageRaw <= 1023:
        voltageRaw12bit = voltageRaw * 4  # 10-bit to 12-bit
    
    # Calculate actual voltage value
    # Battery: 501230, 3.7V, 150mAh
    # Using nRF52840 SAADC formula: V_BAT = RESULT × K / 4096
    # Calibration constant K = 8.11 (adjusted based on actual measurements, 2025-01-24)
    voltage = voltageRaw12bit * 8.11 / 4096.0
    
    return {
        'timestamp': timestamp,        # milliseconds
        'accelX': accelX,             # g (gravity acceleration unit)
        'accelY': accelY,             # g
        'accelZ': accelZ,             # g
        'gyroX': gyroX,               # dps (degrees per second)
        'gyroY': gyroY,               # dps
        'gyroZ': gyroZ,               # dps
        'voltage': voltage             # V (volts)
    }
```

### Data Parsing Example (JavaScript/TypeScript)

```typescript
interface IMUData {
    timestamp: number;
    accelX: number;
    accelY: number;
    accelZ: number;
    gyroX: number;
    gyroY: number;
    gyroZ: number;
    voltage: number;
}

function parseIMUData(buffer: ArrayBuffer): IMUData {
    const view = new DataView(buffer);
    
    let offset = 0;
    const timestamp = view.getUint32(offset, true); offset += 4;
    const accelX = view.getFloat32(offset, true); offset += 4;
    const accelY = view.getFloat32(offset, true); offset += 4;
    const accelZ = view.getFloat32(offset, true); offset += 4;
    const gyroX = view.getFloat32(offset, true); offset += 4;
    const gyroY = view.getFloat32(offset, true); offset += 4;
    const gyroZ = view.getFloat32(offset, true); offset += 4;
    const voltageRaw = view.getUint16(offset, true); offset += 2;
    
    // Calculate actual voltage value
    // Battery: 501230, 3.7V, 150mAh
    // Using nRF52840 SAADC formula:
    // V_BAT = RESULT × K / 4096
    // Where:
    // - RESULT: 12-bit ADC value (0-4095)
    // - K: Calibration constant = 8.11 (adjusted based on actual measurements, 2025-01-24)
    // Note: Arduino analogRead() returns 10-bit (0-1023), needs to be converted to 12-bit
    let voltageRaw12bit = voltageRaw;
    if (voltageRaw <= 1023) {
        voltageRaw12bit = voltageRaw * 4;  // 10-bit to 12-bit
    }
    const voltage = voltageRaw12bit * 8.11 / 4096.0;
    
    return {
        timestamp,
        accelX,
        accelY,
        accelZ,
        gyroX,
        gyroY,
        gyroZ,
        voltage
    };
}
```

### Data Unit Description

- **Acceleration**: 
  - Unit: `g` (gravity acceleration, 1g ≈ 9.8 m/s²)
  - Range: Usually ±16g
  - At rest, Z-axis is approximately 1g (gravity)

- **Angular Velocity**:
  - Unit: `dps` (degrees per second)
  - Range: ±2000 dps
  - At rest, all axes should be close to 0 dps

- **Timestamp**:
  - Unit: milliseconds
  - Source: Arduino `millis()` function
  - Accumulated from system startup

- **Voltage**:
  - Unit: `V` (Volts)
  - Range: 2.5V - 4.5V (Battery 501230, 3.7V, 150mAh)
  - Reading frequency: Updated every 10 seconds (Arduino side)
  - Reading method: Read 30 voltage samples and average them each time
  - Conversion formula: `V_BAT = RESULT × 8.11 / 4096`
    - RESULT: 12-bit ADC value (0-4095)
    - Calibration constant: 8.11 (adjusted based on actual measurements, 2025-01-24)
  - Android side filtering: Dual-layer filter (moving average + EMA) to smooth readings

### Voltage Reading and Filtering Mechanism (Updated 2025-01-24)

#### Arduino Side Voltage Reading

1. **Reading Frequency Optimization**:
   - Reduced from 50Hz (every 20ms) to once every 10 seconds
   - Significantly reduces power consumption and extends battery life

2. **Reading Method**:
   - Use `readVoltageAverage()` function
   - Read 30 voltage samples each time and calculate average
   - Enable voltage divider circuit before reading (P0.14 = LOW)
   - Disable voltage divider circuit immediately after reading (P0.14 = HIGH) to save power

3. **ADC Conversion**:
   - Arduino `analogRead()` returns 10-bit value (0-1023)
   - nRF52840 SAADC is actually 12-bit (0-4095)
   - Conversion formula: `12bit_value = 10bit_value × 4`

4. **Voltage Calculation**:
   - Use nRF52840 SAADC formula: `V_BAT = RESULT × K / 4096`
   - Calibration constant K = 8.11 (adjusted based on actual measurements)

#### Android Side Voltage Filtering

1. **Dual-Layer Filter Architecture**:
   - **First Layer**: Moving Average (100 samples, approximately 2 seconds)
   - **Second Layer**: Exponential Moving Average (EMA, alpha = 0.15)

2. **Outlier Handling**:
   - Automatically filter outliers (< 0.1V or > 5.0V)
   - Detect USB power mode or reading errors

3. **UI Display**:
   - Display both filtered and raw values simultaneously
   - Format: `Voltage: X.XXX V (Raw: X.XXX V)`

**Implementation Locations**:
- Arduino: `src/main/main.ino` - `readVoltageAverage()` function
- Android: `APP/android/app/src/main/java/com/example/smartbadmintonracket/filter/VoltageFilter.java`

### IMU Calibration Mechanism

**Note**: This project uses **manual trigger calibration**, not automatic calibration. Users need to click the "Zero-Point Calibration" button to trigger the calibration process.

**Actual Implementation**:
1. **Accelerometer Calibration**:
   - Collect 200 data points to calculate average (approximately 4 seconds)
   - Subtract 1g from Z-axis (gravity acceleration)
   - Used to compensate for offset in resting state

2. **Gyroscope Calibration**:
   - Collect 200 data points to calculate average
   - Used as zero-point offset compensation

3. **Calibration Data Storage**:
   - Stored locally using SharedPreferences + Gson
   - Calibration values are automatically loaded and applied after app restart

---

## Mobile BLE Receiver Development Guide

### Development Environment Recommendations

#### Android (Java) - Used in This Project

**Project Technology Stack**:
- **Development Language**: Java
- **Framework**: Native Android (AndroidX)
- **Minimum SDK**: API Level 26
- **Target SDK**: API Level 36
- **Main Dependencies**:
  - Android Native BLE API (`android.bluetooth`)
  - MPAndroidChart v3.1.0 (Chart Display)
  - Firebase Firestore (Cloud Database)
  - Gson 2.10.1 (JSON Serialization)
  - Material Design 3

**Actual Implementation Locations**:
- `APP/android/app/src/main/java/com/example/smartbadmintonracket/`
  - `BLEManager.java` - BLE Connection Management
  - `IMUDataParser.java` - Data Parsing
  - `MainActivity.java` - Main Activity

#### Android (Kotlin/Java) - General Examples

**Required Permissions (AndroidManifest.xml)**
```xml
<!-- Bluetooth Permissions -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Location Permissions (Required for Android 12 and below) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- WiFi and Network Permissions -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

**Gradle Dependencies (build.gradle)**
```gradle
dependencies {
    // BLE Support (using Android BLE API)
    implementation 'com.polidea.rxandroidble2:rxandroidble:1.17.2'
    
    // Or use Google's BLE library
    implementation 'no.nordicsemi.android:ble:2.6.1'
    
    // HTTP Requests (for data upload)
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    implementation 'com.google.code.gson:gson:2.10.1'
}
```

### Data Buffering and Processing (Android Java Implementation)

Since the data transmission frequency is 50Hz, the actual implementation uses the following methods to manage data:

**Actual Implementation Locations**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/`

```java
// ChartManager.java - Chart data buffering (downsampling)
public class ChartManager {
    private static final int MAX_DATA_POINTS = 50;  // 5 seconds * 10Hz = 50 points
    private static final long UPDATE_INTERVAL_MS = 100;  // Update every 100ms
    private List<IMUData> dataBuffer = new ArrayList<>();
    private long lastUpdateTime = 0;
    
    public void addDataPoint(IMUData data) {
        long currentTime = System.currentTimeMillis();
        
        // Downsampling: take latest data point every 100ms
        if (currentTime - lastUpdateTime >= UPDATE_INTERVAL_MS) {
            dataBuffer.add(data);
            
            // Maintain 5 seconds of data (approximately 50 points)
            if (dataBuffer.size() > MAX_DATA_POINTS) {
                dataBuffer.remove(0);
            }
            
            lastUpdateTime = currentTime;
            updateCharts();
        }
    }
}

// FirebaseManager.java - Firebase batch upload buffering
public class FirebaseManager {
    private List<IMUData> pendingData = new ArrayList<>();
    private static final int BATCH_SIZE = 100;  // 100 data points
    private static final int UPLOAD_INTERVAL_MS = 5000;  // 5 seconds
    
    public void addData(IMUData data) {
        if (!isRecordingMode) return;
        
        pendingData.add(data);
        
        // Check upload conditions: 5 seconds or 100 points
        if (pendingData.size() >= BATCH_SIZE || 
            (System.currentTimeMillis() - lastUploadTime) >= UPLOAD_INTERVAL_MS) {
            uploadBatch();
        }
    }
}
```

---

## Mobile App Results Display & UI Design

### Display Function Requirements

The mobile App needs to simultaneously complete the following functions during demonstrations:

1. **Real-time Data Collection**: Continuously receive IMU sensor data transmitted via BLE
2. **Real-time AI Inference**: Use local TensorFlow Lite model for real-time stroke recognition
3. **Results Display**: Present recognition results to users in a visual way
4. **Test Records**: Save detailed data and recognition results for each stroke

### UI Design Recommendations

#### 1. Main Interface Architecture

It is recommended to use Tab navigation or bottom navigation bar design, mainly including the following pages:

```
┌─────────────────────────────────┐
│  Smart Badminton Analysis       │
│         System                  │
├─────────────────────────────────┤
│                                 │
│  ┌─────┐  ┌─────┐  ┌─────┐    │
│  │Home │  │Analy│  │Hist │    │
│  └─────┘  └─────┘  └─────┘    │
│                                 │
└─────────────────────────────────┘
```

#### 2. Real-time Test Page (Home Page)

This is the main page for demonstrations, recommended design as follows:

**Upper Section: Connection Status & Real-time Data Display**
```
┌─────────────────────────────────┐
│  📶 SmartRacket  ✓ Connected   │
│  Battery: ████████░░ 80%       │
├─────────────────────────────────┤
│  Real-time Sensor Data          │
│  ┌─────────────────────────┐  │
│  │ Acceleration: X Y Z     │  │
│  │ Angular Vel: X Y Z       │  │
│  └─────────────────────────┘  │
└─────────────────────────────────┘
```

**Middle Section: AI Recognition Results Display Area (Key Focus)**
```
┌─────────────────────────────────┐
│      🎾 Stroke Recognition      │
│                                 │
│    ┌─────────────────────┐    │
│    │                     │    │
│    │    [SMASH]          │    │
│    │                     │    │
│    │  Confidence: 85%    │    │
│    │                     │    │
│    └─────────────────────┘    │
│                                 │
│  [Ready] [Start Test] [Stop]   │
└─────────────────────────────────┘
```

**Lower Section: Real-time Waveform Chart**
```
┌─────────────────────────────────┐
│  Real-time Data Waveform        │
│  ┌─────────────────────────┐  │
│  │  ▁▂▃▅▇█▇▅▃▂▁          │  │
│  │  (Dynamic waveform)      │  │
│  └─────────────────────────┘  │
└─────────────────────────────────┘
```

**UI Element Recommendations:**
- Result cards use large size display, with colors distinguishing different stroke types:
  - Smash: Red tones (#FF4444)
  - Drive: Blue tones (#4488FF)
  - Other: Gray tones (#888888)
- Confidence displayed as progress bar or circular progress indicator
- Add animation effects when displaying results (such as pop-up, fade-in, etc.)
- Results freeze display for 3-5 seconds to allow users to clearly see recognition results

#### 3. Test Results Detail Page (To Be Implemented)

Display detailed information for each stroke. This feature is currently not implemented and can be added in the future with a detailed results display page.

#### 4. History Records Page

Display list of all test records:

```
┌─────────────────────────────────┐
│  Test Records                   │
├─────────────────────────────────┤
│  🎾 Smash  85%  [Today 14:23]  │
│  🎾 Drive  72%  [Today 14:20]  │
│  🎾 Other  45%  [Today 14:15]  │
│  🎾 Smash  90%  [Today 14:10]  │
│  🎾 Drive  68%  [Today 14:05]  │
└─────────────────────────────────┘
```

#### 5. Chart Visualization Specifications

**Chart Requirements**:
- **Time Range**: Last 5 seconds of data
- **Update Frequency**: Every 100ms (downsampled from 50Hz)
- **Chart Count**: 6 independent charts (one for each axis)
- **Chart Type**: Line Chart

**Data Downsampling**:
Since data arrives at 50Hz (every 20ms), but charts update at 10Hz (every 100ms), we need to downsample:
- Take 1 data point every 5 data points (50Hz / 5 = 10Hz)
- This gives us 50 data points for 5 seconds (10Hz * 5s = 50 points)

**Chart Implementation (Android - MPAndroidChart)**:
```java
public class ChartManager {
    private static final int MAX_DATA_POINTS = 50;  // 5 seconds * 10Hz = 50 points
    private static final long UPDATE_INTERVAL_MS = 100;  // Update every 100ms
    private List<IMUData> dataBuffer = new ArrayList<>();
    private long lastUpdateTime = 0;
    
    public void addDataPoint(IMUData data) {
        long currentTime = System.currentTimeMillis();
        
        // Downsampling: take latest data point every 100ms
        if (currentTime - lastUpdateTime >= UPDATE_INTERVAL_MS) {
            dataBuffer.add(data);
            
            // Maintain 5 seconds of data (approximately 50 points)
            if (dataBuffer.size() > MAX_DATA_POINTS) {
                dataBuffer.remove(0);
            }
            
            lastUpdateTime = currentTime;
            updateCharts();
        }
    }
    
    private void updateCharts() {
        // Update all 6 charts with new data
        accelXChart.updateData(dataBuffer, IMUData::getAccelX);
        accelYChart.updateData(dataBuffer, IMUData::getAccelY);
        accelZChart.updateData(dataBuffer, IMUData::getAccelZ);
        gyroXChart.updateData(dataBuffer, IMUData::getGyroX);
        gyroYChart.updateData(dataBuffer, IMUData::getGyroY);
        gyroZChart.updateData(dataBuffer, IMUData::getGyroZ);
    }
}
```

**Chart Styling (Actual Implementation)**:
- Each axis uses a different color:
  - Acceleration X: Blue (#2196F3)
  - Acceleration Y: Green (#4CAF50)
  - Acceleration Z: Purple (#9C27B0)
  - Gyro X: Orange (#FF9800)
  - Gyro Y: Red (#F44336)
  - Gyro Z: Cyan (#00BCD4)
- Cubic Bezier smooth curves
- Grid lines for readability
- Axis labels with units
- Y-axis range: Acceleration ±20g, Gyro ±2500 dps
- Auto-scale X-axis range (0-5 seconds)

#### 6. Animation Effects (To Be Implemented)

Currently, the UI has implemented basic Material Design 3 design. Animation effects can be added in future versions. Future implementations can use Android's `ObjectAnimator` or `ValueAnimator` for result pop-up animations.

### Display Mode Design

For better demonstration effects, it is recommended to design the following modes:

#### 1. Test Mode
- Clear start/stop buttons
- Display real-time data during testing
- Immediately display results after each stroke
- Results persist for 3-5 seconds then automatically clear, ready for next test

#### 2. Demo Mode
- Auto-record mode, no manual operation required
- Continuously test multiple stroke actions
- Automatically save all results
- Can replay the test process

### State Management (Android Java Implementation)

The actual implementation uses the following methods to manage state:

```java
// MainActivity.java - Main state management
public class MainActivity extends AppCompatActivity {
    private BLEManager bleManager;
    private CalibrationManager calibrationManager;
    private ChartManager chartManager;
    private FirebaseManager firebaseManager;
    private VoltageFilter voltageFilter;
    
    private boolean isConnected = false;
    private int dataCount = 0;
    
    // State managed through callback interfaces
    private void setupBLECallbacks() {
        bleManager.setDataCallback(data -> {
            // Apply calibration
            IMUData calibratedData = calibrationManager.applyCalibration(data);
            
            // Update charts
            chartManager.addDataPoint(calibratedData);
            
            // Upload to Firebase (if recording mode is enabled)
            firebaseManager.addData(calibratedData);
            
            // Update UI
            updateDataDisplay(calibratedData);
        });
    }
}
```

### Performance Optimization Recommendations

1. **Chart Update Frequency**: Waveform chart recommended to update 10-20 times per second, no need for 50Hz
2. **Result Caching**: Cache recognition results for display, avoid frequent recalculation
3. **Background Processing**: AI inference runs on background thread to avoid blocking UI

---

## Zero-Point Calibration Function

### Function Necessity Description

Zero-point calibration is an important function to ensure accurate sensor readings and AI model recognition because:

1. **Sensor Installation Differences**: Different rackets or different installation angles will cause sensor coordinate system to be inconsistent with actual stroke action coordinate system
2. **Sensor Offset**: IMU sensors have inherent offsets that need to be compensated
3. **Gravity Compensation**: When the racket is stationary and flat, the Z-axis should read approximately 1g (gravity), not 0
4. **Improve Recognition Accuracy**: Calibrated data can significantly improve AI model recognition accuracy

### Calibration Principle

When the racket is stationary and placed flat:
- **Accelerometer**: 
  - X-axis: Should be 0 (after calibration)
  - Y-axis: Should be 0 (after calibration)
  - Z-axis: Should be approximately 1g (gravity) when stationary, so we subtract 1g to get 0
- **Gyroscope**: 
  - X/Y/Z axes: Should all be 0 (after calibration)

### Calibration Flow Design

#### 1. Calibration Mode Trigger (Android Java Implementation)

A "Zero-Point Calibration" button is provided in the main interface:

**Actual Implementation Location**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/MainActivity.java`

```java
// MainActivity.java
private void setupCalibrationButton() {
    calibrateButton.setOnClickListener(v -> {
        if (!isConnected) {
            Toast.makeText(this, "Please connect device first", Toast.LENGTH_SHORT).show();
            return;
        }
        
        if (calibrationManager.isCalibrating()) {
            // Cancel calibration
            calibrationManager.cancelCalibration();
        } else {
            // Start calibration
            showCalibrationDialog();
        }
    });
}

private void showCalibrationDialog() {
    new android.app.AlertDialog.Builder(this)
        .setTitle("Zero-Point Calibration")
        .setMessage("Please place the racket stationary and flat on a flat surface, keep it still.\n\nClick \"Start Calibration\" when ready")
        .setPositiveButton("Start Calibration", (dialog, which) -> {
            startCalibration();
        })
        .setNegativeButton("Cancel", null)
        .show();
}
```

#### 2. Calibration Step Design

**Step 1: Preparation Phase**
```
┌─────────────────────────────────┐
│  Pose Calibration               │
├─────────────────────────────────┤
│                                 │
│  Please place racket on flat   │
│  surface                        │
│  Keep racket still              │
│                                 │
│  Click "Start Calibration"      │
│  when ready                     │
│                                 │
│      [Cancel]  [Start]           │
└─────────────────────────────────┘
```

**Step 2: Static State Sampling (Android Java Implementation)**

**Actual Implementation Location**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/calibration/CalibrationManager.java`

```java
// CalibrationManager.java
public class CalibrationManager {
    private static final int REQUIRED_SAMPLES = 200;  // Collect 200 data points (approximately 4 seconds)
    private List<IMUData> calibrationSamples = new ArrayList<>();
    private boolean isCalibrating = false;
    private CalibrationCallback callback;
    
    public void startCalibration(CalibrationCallback callback) {
        this.callback = callback;
        isCalibrating = true;
        calibrationSamples.clear();
    }
    
    public void addCalibrationSample(IMUData data) {
        if (!isCalibrating) return;
        
        calibrationSamples.add(data);
        
        // Update progress
        if (callback != null) {
            callback.onProgress(calibrationSamples.size(), REQUIRED_SAMPLES);
        }
        
        // Complete calibration
        if (calibrationSamples.size() >= REQUIRED_SAMPLES) {
            completeCalibration();
        }
    }
    
    private void completeCalibration() {
        // Calculate calibration parameters
        CalibrationData calData = calculateCalibration(calibrationSamples);
        
        // Save calibration parameters
        storage.saveCalibration(calData);
        
        isCalibrating = false;
        
        if (callback != null) {
            callback.onComplete(calData);
        }
    }
    
    private CalibrationData calculateCalibration(List<IMUData> samples) {
        // Calculate average as offset
        float sumAX = 0, sumAY = 0, sumAZ = 0;
        float sumGX = 0, sumGY = 0, sumGZ = 0;
        
        for (IMUData data : samples) {
            sumAX += data.accelX;
            sumAY += data.accelY;
            sumAZ += data.accelZ;
            sumGX += data.gyroX;
            sumGY += data.gyroY;
            sumGZ += data.gyroZ;
        }
        
        int count = samples.size();
        float accelXOffset = sumAX / count;
        float accelYOffset = sumAY / count;
        float accelZMean = sumAZ / count;
        float accelZOffset = accelZMean - 1.0f;  // Z-axis subtract 1g (gravity)
        
        float gyroXOffset = sumGX / count;
        float gyroYOffset = sumGY / count;
        float gyroZOffset = sumGZ / count;
        
        return new CalibrationData(
            accelXOffset, accelYOffset, accelZOffset,
            gyroXOffset, gyroYOffset, gyroZOffset
        );
    }
    
    public IMUData applyCalibration(IMUData rawData) {
        CalibrationData calData = storage.loadCalibration();
        if (calData == null) {
            return rawData;  // Return original data if not calibrated
        }
        
        return new IMUData(
            rawData.timestamp,
            rawData.accelX - calData.accelXOffset,
            rawData.accelY - calData.accelYOffset,
            rawData.accelZ - calData.accelZOffset,
            rawData.gyroX - calData.gyroXOffset,
            rawData.gyroY - calData.gyroYOffset,
            rawData.gyroZ - calData.gyroZOffset,
            rawData.voltage
        );
    }
}
```

**Calibration Progress Display:**
```
┌─────────────────────────────────┐
│  Calibrating...                 │
│                                 │
│  ████████░░░░░░░░░░ 40%         │
│                                 │
│  Please keep racket still       │
│  Remaining time: 2.4 seconds    │
│                                 │
└─────────────────────────────────┘
```

#### 3. Calibration Data Application (Implemented)

Calibrated data needs to be applied to all received data. The actual implementation has been completed in `CalibrationManager.java`, see the code example above.

**Application Timing**:
- All displayed data is calibrated
- All data uploaded to Firebase is calibrated
- All chart displayed data is calibrated

**Important Notes**:
- All displayed data should be calibrated
- All uploaded data should be calibrated
- Calibration values are stored locally and persist across app restarts

#### 4. Calibration Data Storage (Implemented)

Use SharedPreferences + Gson to save calibration parameters:

**Actual Implementation Location**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/calibration/CalibrationStorage.java`

```java
public class CalibrationStorage {
    private static final String CALIBRATION_KEY = "imu_calibration_data";
    private SharedPreferences prefs;
    private Gson gson;
    
    public CalibrationStorage(Context context) {
        prefs = context.getSharedPreferences("CalibrationPrefs", Context.MODE_PRIVATE);
        gson = new Gson();
    }
    
    public void saveCalibration(CalibrationData data) {
        SharedPreferences.Editor editor = prefs.edit();
        String json = gson.toJson(data);
        editor.putString(CALIBRATION_KEY, json);
        editor.apply();
    }
    
    public CalibrationData loadCalibration() {
        String json = prefs.getString(CALIBRATION_KEY, null);
        if (json == null) return null;
        
        return gson.fromJson(json, CalibrationData.class);
    }
    
    public void clearCalibration() {
        prefs.edit().remove(CALIBRATION_KEY).apply();
    }
}
```

### Calibration Timing Recommendations

1. **Manual Trigger**: Users can calibrate anytime by clicking the "Zero-Point Calibration" button
2. **Device Replacement**: After changing racket or reinstalling sensor
3. **Regular Calibration**: Recommend calibration when sensor readings seem inaccurate
4. **Calibration Persistence**: Calibration values are saved locally and persist across app restarts

### Calibration Validation (To Be Implemented)

After calibration is complete, simple validation can be performed. In the current implementation, calibration values are directly saved and applied. Validation logic can be added in the future.

**Java Implementation Example (To Be Implemented)**:
```java
public boolean validateCalibration(CalibrationData calData) {
    // Validate if accelerometer offset is within reasonable range
    if (Math.abs(calData.accelXOffset) > 2.0f || 
        Math.abs(calData.accelYOffset) > 2.0f || 
        Math.abs(calData.accelZOffset) > 2.0f) {
        return false; // Accelerometer offset too large
    }
    
    // Validate if gyroscope offset is within reasonable range
    if (Math.abs(calData.gyroXOffset) > 50.0f || 
        Math.abs(calData.gyroYOffset) > 50.0f || 
        Math.abs(calData.gyroZOffset) > 50.0f) {
        return false; // Gyroscope offset too large
    }
    
    return true;
}
```

### Advanced Calibration Functions (Optional)

For higher precision, multi-directional calibration can be implemented:

1. **Multi-angle Calibration**: Allow users to place racket at different angles for calibration
2. **Dynamic Calibration**: Perform specific actions (such as standard stroke) for calibration
3. **Personalized Calibration**: Personalized adjustment based on user's stroke habits

---

## Firebase Data Transmission

### Data Upload Strategy

#### 1. Batch Upload (Recommended for Training Data Collection)

Upload data in batches to Firebase Firestore:

```java
public class FirebaseManager {
    private Firestore db;
    private List<IMUData> pendingData = new ArrayList<>();
    private Handler uploadHandler;
    private static final int UPLOAD_INTERVAL = 5000;  // 5 seconds
    private static final int BATCH_SIZE = 100;         // 100 data points
    private long lastUploadTime = 0;
    private boolean isRecordingMode = false;
    
    public void initialize() {
        db = FirebaseFirestore.getInstance();
        uploadHandler = new Handler(Looper.getMainLooper());
    }
    
    public void addData(IMUData data) {
        if (!isRecordingMode) {
            return;  // Only upload in recording mode
        }
        
        pendingData.add(data);
        checkUploadCondition();
    }
    
    private void checkUploadCondition() {
        long currentTime = System.currentTimeMillis();
        boolean timeCondition = (currentTime - lastUploadTime) >= UPLOAD_INTERVAL;
        boolean sizeCondition = pendingData.size() >= BATCH_SIZE;
        
        if (timeCondition || sizeCondition) {
            uploadBatch();
        }
    }
    
    private void uploadBatch() {
        if (pendingData.isEmpty()) return;
        
        List<IMUData> dataToUpload = new ArrayList<>(pendingData);
        pendingData.clear();
        lastUploadTime = System.currentTimeMillis();
        
        // Upload to Firestore
        for (IMUData data : dataToUpload) {
            Map<String, Object> docData = new HashMap<>();
            docData.put("device_id", "SmartRacket_001");
            docData.put("session_id", getCurrentSessionId());
            docData.put("timestamp", data.timestamp);
            docData.put("accelX", data.accelX);
            docData.put("accelY", data.accelY);
            docData.put("accelZ", data.accelZ);
            docData.put("gyroX", data.gyroX);
            docData.put("gyroY", data.gyroY);
            docData.put("gyroZ", data.gyroZ);
            docData.put("voltage", data.voltage);
            docData.put("received_at", data.receivedAt);
            docData.put("calibrated", true);
            docData.put("uploaded_at", FieldValue.serverTimestamp());
            
            db.collection("imu_data")
                .add(docData)
                .addOnSuccessListener(documentReference -> {
                    Log.d(TAG, "Data uploaded: " + documentReference.getId());
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Upload failed", e);
                    // Save to local database for retry
                    saveToLocalDatabase(dataToUpload);
                });
        }
    }
    
    public void setRecordingMode(boolean enabled) {
        this.isRecordingMode = enabled;
    }
}
```

#### 2. Upload Mode Control

Data upload only occurs in **Recording/Test Mode**:

- **Recording Mode ON**: Data is collected and uploaded to Firebase
- **Recording Mode OFF**: Data is only displayed, not uploaded
- Users can toggle recording mode with "Start Recording" / "Stop Recording" buttons

### Upload Trigger Conditions

Data is uploaded when **either** condition is met:
1. **Time Condition**: 5 seconds have passed since last upload
2. **Size Condition**: 100 data points have been accumulated

### Offline Data Cache (To Be Implemented)

Currently, when Firebase upload fails, errors are logged in Logcat, but local database storage has not been implemented. Future implementations can consider using Room database for offline caching and retry mechanisms.

---

## CSV Local Data Storage

### Feature Overview

The Android App provides local CSV file storage functionality, saving IMU data in CSV format to external storage for easy analysis and processing. CSV files use Excel-friendly timestamp format and support automatic file splitting.

### CSV File Format

#### Timestamp Format

- **Format**: `yyyy/MM/dd HH:mm:ss.SSS`
- **Example**: `2025/12/05 23:34:51.123`
- **Advantage**: Excel can directly recognize this format without manual conversion

#### CSV Field Structure

```csv
timestamp,receivedAt,accelX,accelY,accelZ,gyroX,gyroY,gyroZ
2025/12/05 23:34:51.123,2025/12/05 23:34:51.145,-1.016414,-0.006844,-0.023593,-0.087150,0.118300,0.036750
```

- **timestamp**: Sensor timestamp (converted to absolute time)
- **receivedAt**: Android reception timestamp
- **accelX/Y/Z**: Acceleration three axes (unit: g)
- **gyroX/Y/Z**: Angular velocity three axes (unit: dps)

### File Naming Convention

#### First File

- Named using the reception time of the first data point
- Format: `imu_data_YYYYMMDD_HHmmss.csv`
- Example: Recording starts at `23:34:51.123` → `imu_data_20251205_233451.csv`

#### Subsequent Files

- Named using 5-minute interval boundary times
- Format: `imu_data_YYYYMMDD_HHmmss.csv` (time aligned to 5-minute multiples)
- Examples:
  - First file: `imu_data_20251205_233451.csv` (starts at 23:34:51)
  - Second file: `imu_data_20251205_233500.csv` (starts at 23:35:00)
  - Third file: `imu_data_20251205_234000.csv` (starts at 23:40:00)

### Automatic File Splitting

#### Split Interval

- **Time Interval**: 5 minutes (300,000 milliseconds)
- **Trigger Condition**: Automatically switches files when data's `receivedAt` time crosses a 5-minute boundary

#### Split Logic

```java
// First file: Named using first data point time
if (isFirstFile) {
    openNewFile(firstDataTime);  // e.g., 23:34:51
    currentFileStartTime = alignTo5Minutes(firstDataTime);  // 23:35:00
}

// Subsequent files: Check if crossing 5-minute boundary
long nextFileStartTime = alignTo5Minutes(data.receivedAt);
if (nextFileStartTime != currentFileStartTime) {
    // Switch to new file
    flushAndCloseFile();
    openNewFile(getCurrent5MinuteBlock(data.receivedAt));
    currentFileStartTime = nextFileStartTime;
}
```

#### Example Scenario

Recording from 23:34:51 to 23:40:00 will produce 3 files:

1. `imu_data_20251205_233451.csv` (23:34:51 - 23:35:00)
2. `imu_data_20251205_233500.csv` (23:35:00 - 23:40:00)
3. `imu_data_20251205_234000.csv` (starts at 23:40:00)

### Batch Write Mechanism

- **Write Frequency**: Batch write every 2 seconds
- **Advantage**: Reduces I/O operations, improves efficiency
- **Data Buffering**: Uses `pendingData` list to temporarily store data to be written

### Storage Location

- **Directory**: External storage app-specific directory `/Android/data/com.example.smartbadmintonracket/files/IMU_Data/`
- **Permission**: No special permissions required (uses app-specific directory)

### Implementation Location

- **CSVManager.java**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/csv/CSVManager.java`

---

## BLE Disconnection Handling

### Disconnection Detection

The system uses Android BLE protocol's `onConnectionStateChange` callback to detect connection state changes:

```java
@Override
public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
    if (newState == BluetoothProfile.STATE_DISCONNECTED) {
        // Disconnection detected
        handleDisconnection(gatt);
    }
}
```

### Disconnection Handling Flow

#### 1. Resource Cleanup

- Close GATT connection (`gatt.disconnect()` and `gatt.close()`)
- Reset data buffers
- Reset time synchronization state
- Clear timeout callbacks
- Set `bluetoothGatt` to `null` (avoid using closed connection)

#### 2. Automatic Recording Stop

When disconnection is detected, if recording is active, the system will automatically:

- **Stop Firebase Recording**: `firebaseManager.setRecordingMode(false)`
- **Stop CSV Recording**: `csvManager.setRecordingMode(false)`
- **Close CSV File**: Ensure all data is written

#### 3. UI Updates

- Update connection status display ("Disconnected")
- Update recording button state ("Start Recording")
- Show notification: "Device disconnected, recording automatically stopped"
- Stop chart updates
- Reset voltage filter

### Disconnection Cause Handling

#### Common Disconnection Causes

1. **Physical Disconnection**: Cable breakage, device moved out of range
2. **Battery Depletion**: Device automatically shuts down
3. **Manual Disconnect**: User actively disconnects
4. **BLE Protocol Layer Disconnection**: Connection supervision timeout

#### Connection Supervision Timeout

- BLE protocol uses "Connection Supervision Timeout" mechanism to detect if connection is still valid
- Default timeout is usually several seconds to tens of seconds (determined by BLE stack)
- Will not determine disconnection due to a few milliseconds of data reception delay

### Recovery After Disconnection

#### Manual Reconnection

- User can click "Scan Device" button to rescan and reconnect
- System will automatically clean up old connection state

#### Automatic Reconnection (To Be Implemented)

- Automatic reconnection is not currently implemented
- Future implementations can consider automatically rescanning and reconnecting after disconnection

### Implementation Locations

- **BLEManager.java**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/BLEManager.java`
  - `onConnectionStateChange()` method
- **MainActivity.java**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/MainActivity.java`
  - `onDisconnected()` callback handling

---

## Database Design

### Recommended Database Structure (MySQL/PostgreSQL)

#### Main Data Table: `imu_raw_data`

```sql
CREATE TABLE imu_raw_data (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    device_id VARCHAR(50) NOT NULL,
    timestamp BIGINT NOT NULL,
    accel_x FLOAT NOT NULL,
    accel_y FLOAT NOT NULL,
    accel_z FLOAT NOT NULL,
    gyro_x FLOAT NOT NULL,
    gyro_y FLOAT NOT NULL,
    gyro_z FLOAT NOT NULL,
    voltage FLOAT,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uploaded_at TIMESTAMP,
    INDEX idx_device_timestamp (device_id, timestamp),
    INDEX idx_received_at (received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Training Data Table: `training_data`

```sql
CREATE TABLE training_data (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    session_id VARCHAR(100) NOT NULL,
    device_id VARCHAR(50) NOT NULL,
    label VARCHAR(20) NOT NULL,  -- 'smash', 'drive', 'other'
    start_timestamp BIGINT NOT NULL,
    end_timestamp BIGINT NOT NULL,
    data_frame JSON,  -- Store array of 40 data points
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_session (session_id),
    INDEX idx_label (label)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Stroke Recognition Results Table: `stroke_recognition`

```sql
CREATE TABLE stroke_recognition (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    device_id VARCHAR(50) NOT NULL,
    session_id VARCHAR(100) NOT NULL,
    predicted_label VARCHAR(20) NOT NULL,
    confidence FLOAT NOT NULL,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_device_session (device_id, session_id),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### RESTful API Design Recommendations

#### 1. Upload Single IMU Data
```
POST /api/v1/imu-data
Content-Type: application/json

Request Body:
{
  "device_id": "SmartRacket_001",
  "timestamp": 1234567890,
  "accelX": 0.123,
  "accelY": -0.456,
  "accelZ": 0.789,
  "gyroX": 12.34,
  "gyroY": -56.78,
  "gyroZ": 90.12,
  "voltage": 3.65,
  "received_at": 1234567890123
}

Response:
{
  "status": "success",
  "data_id": 12345,
  "message": "Data uploaded successfully"
}
```

#### 2. Batch Upload IMU Data
```
POST /api/v1/imu-data/batch
Content-Type: application/json

Request Body:
{
  "device_id": "SmartRacket_001",
  "data": [
    { "timestamp": 1234567890, "accelX": 0.123, ... },
    { "timestamp": 1234567910, "accelX": 0.124, ... },
    ...
  ]
}

Response:
{
  "status": "success",
  "uploaded_count": 50,
  "message": "Batch data uploaded successfully"
}
```

#### 3. Upload Labeled Training Data
```
POST /api/v1/training-data
Content-Type: application/json

Request Body:
{
  "session_id": "session_20241201_001",
  "device_id": "SmartRacket_001",
  "label": "smash",
  "start_timestamp": 1234567890,
  "end_timestamp": 1234568690,
  "data_frame": [
    { "timestamp": 1234567890, "accelX": 0.123, ... },
    { "timestamp": 1234567910, "accelX": 0.124, ... },
    ... (40 data points)
  ]
}

Response:
{
  "status": "success",
  "training_data_id": 67890,
  "message": "Training data saved successfully"
}
```

---

## AI Training Data Preparation

### Data Format Requirements

#### 1. Time Window Segmentation

AI models require fixed-length input, it is recommended to use **40 data points** as one analysis window (corresponding to approximately 0.8 seconds of data):

```python
def create_data_frames(raw_data, window_size=40):
    """
    Segment raw data into fixed-length frames
    
    Args:
        raw_data: List[dict] - Raw IMU data list
        window_size: int - Number of data points per frame (default 40)
    
    Returns:
        List[List[dict]] - List of segmented data frames
    """
    frames = []
    for i in range(len(raw_data) - window_size + 1):
        frame = raw_data[i:i + window_size]
        frames.append(frame)
    return frames
```

#### 2. Feature Extraction

Each frame needs to be converted to model input format `[1, 40, 6, 1]`:

- **Batch Size**: 1
- **Time Points**: 40 (40 data points)
- **Feature Count**: 6 (accelX, accelY, accelZ, gyroX, gyroY, gyroZ)
- **Channels**: 1

```python
import numpy as np

def frame_to_model_input(frame):
    """
    Convert data frame to model input format
    
    Args:
        frame: List[dict] - 40 IMU data points
    
    Returns:
        numpy.ndarray - Array with shape (1, 40, 6, 1)
    """
    features = []
    for data in frame:
        features.append([
            data['accelX'],
            data['accelY'],
            data['accelZ'],
            data['gyroX'],
            data['gyroY'],
            data['gyroZ']
        ])
    
    # Convert to numpy array
    array = np.array(features, dtype=np.float32)
    
    # Reshape to (1, 40, 6, 1)
    array = array.reshape(1, 40, 6, 1)
    
    return array
```

### Data Labeling Process

#### 1. Automatic Peak Detection

Identify stroke actions based on sensor data peaks:

```python
def detect_peak_frames(data, threshold_std=2.0):
    """
    Detect peaks through standard deviation (stroke actions)
    
    Args:
        data: List[dict] - IMU data list
        threshold_std: float - Standard deviation threshold
    
    Returns:
        List[int] - List of peak indices
    """
    # Extract gY axis data as main judgment basis
    gyY_values = [d['gyroY'] for d in data]
    
    mean = np.mean(gyY_values)
    std = np.std(gyY_values)
    
    peaks = []
    for i in range(len(gyY_values)):
        if abs(gyY_values[i] - mean) > threshold_std * std:
            peaks.append(i)
    
    return peaks

def create_labeled_frames(raw_data, peak_indices, label):
    """
    Create labeled data frames based on peaks
    
    Args:
        raw_data: List[dict] - Raw data
        peak_indices: List[int] - Peak indices
        label: str - Label ('smash', 'drive', 'other')
    
    Returns:
        List[dict] - List of labeled frames
    """
    frames = []
    for peak_idx in peak_indices:
        # 19 points before peak + peak + 20 points after = 40 points
        start_idx = max(0, peak_idx - 19)
        end_idx = min(len(raw_data), peak_idx + 21)
        
        frame = raw_data[start_idx:end_idx]
        
        if len(frame) == 40:
            frames.append({
                'label': label,
                'data': frame,
                'peak_index': peak_idx
            })
    
    return frames
```

#### 2. Manual Labeling Tool

It is recommended to develop a labeling tool that allows users to:
- Visually display IMU data waveforms
- Manually mark start and end times of stroke actions
- Select stroke category (smash, drive, other)

### Data Preprocessing

#### 1. Data Normalization

```python
def normalize_frame(frame, mean=None, std=None):
    """
    Normalize data frame (Z-score normalization)
    
    Args:
        frame: numpy.ndarray - Raw data frame
        mean: numpy.ndarray - Pre-calculated mean (for test data)
        std: numpy.ndarray - Pre-calculated standard deviation (for test data)
    
    Returns:
        tuple: (normalized frame, mean, std)
    """
    if mean is None or std is None:
        mean = np.mean(frame, axis=0, keepdims=True)
        std = np.std(frame, axis=0, keepdims=True)
    
    # Avoid division by zero
    std = np.where(std == 0, 1, std)
    
    normalized = (frame - mean) / std
    
    return normalized, mean, std
```

#### 2. Data Augmentation

```python
def augment_data(frames, noise_factor=0.01):
    """
    Add noise for data augmentation
    
    Args:
        frames: List[numpy.ndarray] - Raw frame list
        noise_factor: float - Noise intensity
    
    Returns:
        List[numpy.ndarray] - Augmented frame list
    """
    augmented = []
    for frame in frames:
        noise = np.random.normal(0, noise_factor, frame.shape)
        augmented_frame = frame + noise
        augmented.append(augmented_frame)
    
    return augmented
```

### Dataset Organization

```
training_data/
├── smash/
│   ├── frame_001.npy
│   ├── frame_002.npy
│   └── ...
├── drive/
│   ├── frame_001.npy
│   ├── frame_002.npy
│   └── ...
└── other/
    ├── frame_001.npy
    ├── frame_002.npy
    └── ...
```

---

## Remote AI Recognition

### Recognition Architecture

The Android App uses **remote AI recognition** instead of local TensorFlow Lite models. The recognition process works as follows:

1. **Action Detection**: The app detects stroke actions based on sensor data peaks
2. **Data Frame Collection**: When an action is detected, collect 40 data points (0.8 seconds)
3. **API Request**: Send the data frame to the recognition server via HTTP POST
4. **Result Display**: Receive and display the recognition results on the mobile screen

### Action Detection

The app detects stroke actions using threshold-based detection:

```java
public class ActionDetector {
    private static final double ACCEL_THRESHOLD = 5.0;  // 5g threshold
    private static final double GYRO_THRESHOLD = 500.0; // 500 dps threshold
    
    public boolean detectAction(IMUData data) {
        // Calculate acceleration magnitude
        double accelMagnitude = Math.sqrt(
            data.accelX * data.accelX +
            data.accelY * data.accelY +
            data.accelZ * data.accelZ
        );
        
        // Calculate angular velocity magnitude
        double gyroMagnitude = Math.sqrt(
            data.gyroX * data.gyroX +
            data.gyroY * data.gyroY +
            data.gyroZ * data.gyroZ
        );
        
        return accelMagnitude > ACCEL_THRESHOLD || 
               gyroMagnitude > GYRO_THRESHOLD;
    }
}
```

### Recognition API

**Endpoint**: `POST /api/v1/recognize`

**Request Format**:
```json
{
  "device_id": "SmartRacket_001",
  "data_frame": [
    {
      "timestamp": 1234567890,
      "accelX": 0.123,
      "accelY": -0.456,
      "accelZ": 0.789,
      "gyroX": 12.34,
      "gyroY": -56.78,
      "gyroZ": 90.12
    },
    ... (40 data points)
  ]
}
```

**Response Format**:
```json
{
  "status": "success",
  "prediction": "smash",
  "confidence": 0.85,
  "speed": 120.5
}
```

**Response Fields**:
- `prediction`: One of `smash`, `drive`, `toss`, `drop`, `other`
- `confidence`: Confidence score (0.0 to 1.0)
- `speed`: Ball speed in km/h (only for smash shots, null for others)

### Recognition Result Display

**Display Requirements**:
- Show stroke type name (smash, drive, toss, drop, other)
- Show confidence as percentage (e.g., 85%)
- Show ball speed for smash shots (e.g., 120 km/h)
- Freeze display for 3-5 seconds
- Use animations (pop-up, fade-in)
- Color coding:
  - Smash: Red (#FF4444)
  - Drive: Blue (#4488FF)
  - Toss: Green (#4CAF50)
  - Drop: Orange (#FF9800)
  - Other: Gray (#888888)

### Smash Speed Calculation

**Suggested Formula**:
```java
public double calculateSmashSpeed(List<IMUData> dataFrame) {
    // Find peak acceleration
    double maxAccel = 0;
    for (IMUData data : dataFrame) {
        double accelMagnitude = Math.sqrt(
            data.accelX * data.accelX +
            data.accelY * data.accelY +
            data.accelZ * data.accelZ
        );
        if (accelMagnitude > maxAccel) {
            maxAccel = accelMagnitude;
        }
    }
    
    // Simplified formula: speed = sqrt(accel_peak) * k
    // k is an empirical coefficient, suggested value: 15-20
    double k = 18.0;  // Adjust based on actual test data
    double speed = Math.sqrt(maxAccel) * k;
    
    return speed;  // Unit: km/h
}
```

**Note**: The speed calculation formula should be adjusted based on actual test data. Alternative methods:
- Method 1: Based on acceleration peak `speed = sqrt(peak_accel) * k`
- Method 2: Based on acceleration integral `speed = integral(accel) * dt * k`
- Method 3: Based on angular velocity and racket length `speed = angular_velocity * racket_length * k`

### Recognition Implementation

```java
public class RecognitionManager {
    private static final String API_URL = "https://your-server.com/api/v1/recognize";
    private List<IMUData> dataBuffer = new ArrayList<>();
    private ActionDetector actionDetector = new ActionDetector();
    
    public void processData(IMUData data) {
        dataBuffer.add(data);
        
        // Maintain 40 data points window
        if (dataBuffer.size() > 40) {
            dataBuffer.remove(0);
        }
        
        // Detect action
        if (actionDetector.detectAction(data)) {
            // Send recognition request
            requestRecognition(new ArrayList<>(dataBuffer));
        }
    }
    
    private void requestRecognition(List<IMUData> dataFrame) {
        // Prepare request data
        JSONObject request = new JSONObject();
        request.put("device_id", "SmartRacket_001");
        
        JSONArray dataArray = new JSONArray();
        for (IMUData data : dataFrame) {
            JSONObject dataPoint = new JSONObject();
            dataPoint.put("timestamp", data.timestamp);
            dataPoint.put("accelX", data.accelX);
            dataPoint.put("accelY", data.accelY);
            dataPoint.put("accelZ", data.accelZ);
            dataPoint.put("gyroX", data.gyroX);
            dataPoint.put("gyroY", data.gyroY);
            dataPoint.put("gyroZ", data.gyroZ);
            dataArray.put(dataPoint);
        }
        request.put("data_frame", dataArray);
        
        // Send HTTP POST request
        OkHttpClient client = new OkHttpClient();
        RequestBody body = RequestBody.create(
            request.toString(),
            MediaType.parse("application/json")
        );
        Request httpRequest = new Request.Builder()
            .url(API_URL)
            .post(body)
            .build();
        
        client.newCall(httpRequest).enqueue(new Callback() {
            @Override
            public void onResponse(Call call, Response response) throws IOException {
                if (response.isSuccessful()) {
                    String responseBody = response.body().string();
                    RecognitionResult result = parseResponse(responseBody);
                    // Update UI on main thread
                    updateUI(result);
                }
            }
            
            @Override
            public void onFailure(Call call, IOException e) {
                Log.e(TAG, "Recognition request failed", e);
            }
        });
    }
}
```

---

## System Architecture Flowchart

### Complete Data Flow

```
┌─────────────────┐
│ Badminton Racket│
│   Sensor        │
│  (Arduino IMU)  │
└────────┬────────┘
         │ BLE (50Hz)
         │ 30 bytes/packet
         ▼
┌─────────────────┐
│   Mobile App    │
│   Receiver      │
│  (BLE Client)   │
│  - Parse Data   │
│  - Calibration  │
│  - Validate     │
└────────┬────────┘
         │
         ├─────────────────┐
         │                 │
         ▼                 ▼
┌─────────────────┐  ┌─────────────────┐
│  Real-time      │  │  Firebase Upload│
│  Display        │  │  (Firestore)    │
│  - Value Display│  │  - Batch Upload │
│  - Chart Display│  │  - Recording Mode│
│  - Voltage Filter│  │                 │
└─────────────────┘  └────────┬────────┘
                              │
                              ▼
                      ┌─────────────────┐
                      │  Firebase       │
                      │  Firestore      │
                      │  (Cloud Database)│
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │  AI Training    │
                      │    Module       │
                      │  - Preprocessing│
                      │  - Model Train  │
                      │  - Model Deploy │
                      └─────────────────┘
```

### Mobile App Module Architecture

```
┌─────────────────────────────────────┐
│      Mobile App Architecture         │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────┐                  │
│  │  BLE Manager │                  │
│  │  - Scan Dev  │                  │
│  │  - Connect   │                  │
│  │  - Recv Data │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ┌──────▼───────┐                  │
│  │ Data Parser  │                  │
│  │  - Parse30B  │                  │
│  │  - Validate  │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ┌──────▼───────┐                  │
│  │ Calibration  │                  │
│  │  - Zero-Point│                  │
│  │  - Apply     │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ├──────┴───────┬──────────────────┤
│  │              │                  │
│  ▼              ▼                  │
│  ┌──────────┐  ┌──────────────┐   │
│  │ Chart     │  │  Firebase    │   │
│  │ Manager   │  │  - Firestore │   │
│  │ - Charts  │  │  - Batch Up  │   │
│  │ - Downsample│ │  - Recording │   │
│  └──────────┘  └──────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

---

## Development Notes

### BLE Connection Notes

1. **Connection Timeout Handling**:
   - Set reasonable connection timeout (recommended 15 seconds)
   - Provide retry mechanism when connection fails

2. **Disconnection Reconnection Mechanism**:
   - Monitor connection state changes
   - Automatically rescan and reconnect
   - Display connection status to users

3. **Data Reception Stability**:
   - Check received data length (must be 30 bytes)
   - Handle data parsing errors
   - Record error logs for debugging

### Network Transmission Notes

1. **WiFi Status Check**:
   - Check WiFi connection status before upload
   - Cache data locally when WiFi is not connected

2. **Data Upload Failure Handling**:
   - Implement retry mechanism (maximum 3 times)
   - Store failed data in local database
   - Periodically check and re-upload unsuccessful data

3. **Battery Consumption Optimization**:
   - Batch upload to reduce network requests
   - Use background tasks for upload processing
   - Avoid excessive network requests

### Data Processing Notes

1. **Timestamp Synchronization**:
   - Difference between mobile reception time and sensor time
   - Recommend recording mobile local timestamp
   - Server side uniformly uses UTC time

2. **Data Quality Control**:
   - Check sensor data valid ranges
   - Filter outliers (such as all zeros or extreme values)
   - Validate timestamp continuity

3. **Memory Management**:
   - Avoid accumulating too much data in memory
   - Regularly clean processed data
   - Use appropriate data structure sizes

---

## Troubleshooting

### BLE Connection Issues

#### Issue 1: Unable to Scan Device

**Possible Causes**:
- Sensor not started or BLE not advertising
- Mobile Bluetooth not enabled
- Device too far away

**Solutions**:
1. Check if Arduino program is correctly uploaded
2. Confirm sensor LED indicator status
3. Check mobile Bluetooth permissions
4. Move closer to sensor (recommended within 1 meter)

#### Issue 2: Immediate Disconnection After Connection

**Possible Causes**:
- BLE service UUID mismatch
- Characteristic UUID mismatch
- Mobile BLE driver issues

**Solutions**:
1. Check if UUIDs are completely consistent (including case)
2. Confirm if BLE services and characteristics are correctly discovered
3. Try restarting mobile Bluetooth
4. Check BLE settings in Arduino program

#### Issue 3: Unstable Data Reception

**Possible Causes**:
- Transmission frequency too high
- BLE signal interference
- Insufficient mobile processing performance

**Solutions**:
1. Reduce data transmission frequency (modify Arduino program)
2. Stay away from interference sources like WiFi routers
3. Check if mobile has other BLE connections occupying bandwidth
4. Optimize data reception processing logic

### Data Parsing Issues

#### Issue 1: Data Length Error

**Symptom**: Received data that is not 30 bytes

**Solution**:
```java
if (data.length != 30) {
    Log.w(TAG, "Warning: Received data with abnormal length " + data.length + " bytes");
    return; // Skip this data point
}
```

#### Issue 2: Abnormal Data Values

**Symptom**: Acceleration or angular velocity values exceed reasonable range

**Solution**:
```java
public boolean validateData(IMUData data) {
    // Acceleration range: -20g ~ +20g (relaxed range)
    if (Math.abs(data.accelX) > 20.0f || 
        Math.abs(data.accelY) > 20.0f || 
        Math.abs(data.accelZ) > 20.0f) {
        return false;
    }
    
    // Angular velocity range: -2500 ~ +2500 dps (relaxed range)
    if (Math.abs(data.gyroX) > 2500.0f || 
        Math.abs(data.gyroY) > 2500.0f || 
        Math.abs(data.gyroZ) > 2500.0f) {
        return false;
    }
    
    return true;
}
```

### Network Transmission Issues

#### Issue 1: Upload failure

**Possible Causes**:
- Unstable network connection
- Server API error
- Data format error

**Solution**:
1. Implement a retry mechanism
2. Check HTTP status codes and error messages
3. Verify that the JSON format is correct
4. Check server logs

#### Issue 2: Data loss

**Possible Causes**:
- Upload failed but not saved
- Local database write failed
- Application closed unexpectedly

**Solution**:
1. All data must first be saved to the local database
2. Only mark as uploaded after successful upload
3. Periodically check and re-upload unsuccessful data
4. Use transactions to ensure data consistency

---

## Reference Resources

### Official Documentation

- [Seeed XIAO nRF52840 Sense Documentation](https://wiki.seeedstudio.com/XIAO_BLE/)
- [ArduinoBLE Library Documentation](https://www.arduino.cc/reference/en/libraries/arduinoble/)
- [Android BLE Official Documentation](https://developer.android.com/guide/topics/connectivity/bluetooth/ble-overview)
- [MPAndroidChart Documentation](https://github.com/PhilJay/MPAndroidChart)
- [Firebase Firestore Android Documentation](https://firebase.google.com/docs/firestore/quickstart)
- [BLE Specification Documentation](https://www.bluetooth.com/specifications/specs/core-specification/)

### Example Code Locations

- **Arduino Main Program**: `src/main/main.ino`
- **Android App Main Program**: `APP/android/app/src/main/java/com/example/smartbadmintonracket/`
  - `MainActivity.java` - Main Activity
  - `BLEManager.java` - BLE Connection Management
  - `IMUDataParser.java` - Data Parsing
  - `CalibrationManager.java` - Zero-Point Calibration
  - `ChartManager.java` - Chart Management
  - `FirebaseManager.java` - Firebase Upload
  - `VoltageFilter.java` - Voltage Filtering
- **Windows Receiver Program**: `APP/windows/visualizer/ble_imu_receiver.py`
- **Past Project Examples**: `examples/Past_Student_Projects/codes/`

### Recommended Development Tools

- **BLE Scan Tools**: 
  - Android: nRF Connect
  - iOS: LightBlue
- **Data Visualization**: 
  - Python: Matplotlib, Plotly
  - Android: MPAndroidChart v3.1.0
- **API Testing**: Postman, curl

---

## Contact Information

For technical issues, please contact the project team or refer to the project README file.

---

**Document Version**: v1.3  
**Last Updated**: January 2025  
**Maintainer**: DIID Term Project Team  
**Update Content**: 
- ✅ Updated System Overview: WiFi → Firebase Firestore
- ✅ Removed all Flutter/Dart related content, only Android (Java) implementation retained
- ✅ Updated Zero-Point Calibration: Manual trigger, collect 200 data points, use SharedPreferences + Gson storage
- ✅ Updated Chart Visualization: MPAndroidChart implementation, 6 independent charts, 50Hz → 10Hz downsampling
- ✅ Updated Firebase Data Transmission: Batch upload (5 seconds or 100 points), recording mode toggle
- ✅ Updated Voltage Related Technology: Calibration constant 8.11, reading frequency every 10 seconds, 30 samples average, dual-layer filter
- ✅ Updated Data Parsing Examples: 10-bit to 12-bit conversion, correct voltage calculation formula
- ✅ Updated UI Design: Material Design 3, status cards, control button cards
- ✅ Updated State Management: Java implementation examples
- ✅ Updated System Architecture Flowchart: Reflect actual implementation  