import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';
import '../services/websocket_service.dart';
import '../services/data_buffer_manager.dart';
import '../models/imu_frame.dart';

class HomeProvider extends ChangeNotifier {
  final BLEService _bleService = BLEService();
  final WebSocketService _wsService = WebSocketService();
  final DataBufferManager _bufferManager = DataBufferManager();

  // State Variables
  bool isScanning = false;
  bool isConnected = false;
  String connectionStatus = "Disconnected"; // BLE Status
  String serverStatus = "Disconnected"; // Server Status
  double batteryVoltage = 0.0;
  
  // Real-time Graph Data
  List<IMUFrame> recentFrames = [];
  
  // Recognition Result
  String lastResultType = "--";
  String lastResultSpeed = "--";
  String lastResultMessage = "Ready";
  
  // Configuration (Dynamic)
  double sensitivity = 2.0; // Default threshold
  // String serverIp = "192.168.1.100"; // Local
  String serverIp = "diid-termproject-v2.onrender.com"; // Cloud

  // Calibration State
  bool isCalibrating = false;
  List<IMUFrame> _calibrationFrames = [];
  List<double> accOffset = [0.0, 0.0, 0.0];
  List<double> gyroOffset = [0.0, 0.0, 0.0];
  bool isCalibrated = false;
  
  HomeProvider() {
    _init();
  }
  
  void _init() async {
    await _bleService.init();
    
    // Listen to IMU stream
    _bleService.imuStream.listen((frame) {
      _handleNewFrame(frame);
    });
    
    // Listen to WebSocket stream (Server responses)
    // We connect immediately to wake up the server (Render sleeps on free tier)
    _connectToServer();
  }
  
  // --- Actions ---
  
  void startCalibration() {
    isCalibrating = true;
    _calibrationFrames.clear();
    notifyListeners();
    print("Calibration Started...");
  }

  Future<void> startScan() async {
    // 1. Request Permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      connectionStatus = "Permission Denied";
      notifyListeners();
      return;
    }

    isScanning = true;
    connectionStatus = "Scanning...";
    notifyListeners();
    
    // 2. Start Scan
    await _bleService.startScan();
    
    // 3. Auto-Connect Logic (Listen to Scan Results here)
    // We listen to the global FlutterBluePlus stream for simplicity
    FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
            // Check for SmartRacket
            if (r.device.platformName == "SmartRacket" && !isConnected) {
                print("Found SmartRacket! Connecting...");
                await _bleService.stopScan(); // Stop scanning
                await connectToDevice(r.device); // Connect
                break; 
            }
        }
    });
    
    // Safety timeout
    Future.delayed(const Duration(seconds: 10), () {
        if (isScanning && !isConnected) {
            isScanning = false;
            connectionStatus = "Device Not Found";
            _bleService.stopScan();
            notifyListeners();
        }
    });
  }
  
  Future<void> connectToDevice(BluetoothDevice device) async {
    isScanning = false;
    connectionStatus = "Connecting...";
    notifyListeners();
    
    try {
      await _bleService.connect(device);
      isConnected = true;
      connectionStatus = "Connected";
      notifyListeners();
      
      await _connectToServer();
    } catch (e) {
      connectionStatus = "Connection Failed";
      isConnected = false;
      notifyListeners();
    }
  }
  
  Future<void> disconnect() async {
    await _bleService.disconnect();
    _wsService.disconnect();
    isConnected = false;
    connectionStatus = "Disconnected";
    notifyListeners();
  }
  
  void updateSettings(double newThreshold, String newIp) {
    sensitivity = newThreshold;
    serverIp = newIp;
    
    _bufferManager.setThreshold(sensitivity);
    _connectToServer(); // Reconnect if IP changed
    notifyListeners();
  }

  // --- Internal ---
  
  Future<void> _connectToServer() async {
    // Check if serverIp is a full URL or just an IP
    String url;
    if (serverIp.contains("render.com")) {
      url = "wss://$serverIp/ws/predict";
    } else {
      url = "ws://$serverIp:8000/ws/predict";
    }
    
    serverStatus = "Connecting...";
    notifyListeners();
    
    try {
      await _wsService.connect(url);
      serverStatus = "Connected";
      notifyListeners();
      
      _wsService.stream?.listen((message) {
         _handleServerResponse(message);
      }, onDone: () {
          serverStatus = "Disconnected";
          notifyListeners();
      }, onError: (err) {
          serverStatus = "Error";
          notifyListeners();
      });
      
    } catch (e) {
      print("Server Connect Error: $e");
      serverStatus = "Failed";
      notifyListeners();
    }
  }

  void _handleNewFrame(IMUFrame frame) {
    IMUFrame processedFrame = frame;

    // 0. Calibration Logic
    if (isCalibrating) {
      _calibrationFrames.add(frame);
      // Collect 50 frames (approx 1 sec if 50Hz)
      if (_calibrationFrames.length >= 50) {
        _finishCalibration();
      }
      return; // Do not process or graph during calibration
    }
    
    // Apply Calibration
    if (isCalibrated) {
      processedFrame = IMUFrame(
        timestamp: frame.timestamp,
        acc: [
          frame.acc[0] - accOffset[0],
          frame.acc[1] - accOffset[1],
          frame.acc[2] - accOffset[2],
        ],
        gyro: [
          frame.gyro[0] - gyroOffset[0],
          frame.gyro[1] - gyroOffset[1],
          frame.gyro[2] - gyroOffset[2],
        ],
        voltage: frame.voltage,
      );
    }

    // 1. Update Real-time Graph (Keep last 50 points for display)
    recentFrames.add(processedFrame);
    if (recentFrames.length > 50) {
      recentFrames.removeAt(0);
    }
    batteryVoltage = processedFrame.voltage;
    
    // 2. Add to Buffer Manager
    List<IMUFrame>? window = _bufferManager.addFrame(processedFrame);
    
    // 3. Trigger?
    if (window != null) {
      // Send to Server
      print("Provider: Triggered! Sending ${window.length} frames...");
      _wsService.sendWindow("device_001", window);
      lastResultMessage = "Analyzing...";
    }
    
    // Notify UI (high frequency! might need optimization using StreamBuilder in UI)
    notifyListeners();
  }
  
  void _finishCalibration() {
    // Calculate Averages
    double sumAx = 0, sumAy = 0, sumAz = 0;
    double sumGx = 0, sumGy = 0, sumGz = 0;
    int count = _calibrationFrames.length;

    for (var f in _calibrationFrames) {
      sumAx += f.acc[0];
      sumAy += f.acc[1];
      sumAz += f.acc[2];
      
      sumGx += f.gyro[0];
      sumGy += f.gyro[1];
      sumGz += f.gyro[2];
    }

    // Average
    double avgAx = sumAx / count;
    double avgAy = sumAy / count;
    double avgAz = sumAz / count;
    
    double avgGx = sumGx / count;
    double avgGy = sumGy / count;
    double avgGz = sumGz / count;

    // Set Offsets
    // Target: calibrated_Z = measured_Z - offset_Z => 1.0 = avgAz - offset_Z => offset_Z = avgAz - 1.0
    // Target: calibrated_X = measured_X - offset_X => 0.0 = avgAx - offset_X => offset_X = avgAx
    
    accOffset = [avgAx, avgAy, avgAz - 1.0];
    gyroOffset = [avgGx, avgGy, avgGz];
    
    isCalibrating = false;
    isCalibrated = true;
    _calibrationFrames.clear();

    print("Calibration Done!");
    print("Acc Offset: $accOffset");
    print("Gyro Offset: $gyroOffset");
    
    notifyListeners();
  }

  void _handleServerResponse(dynamic message) {
    // Parse JSON
    // {"type": "Smash", "speed": 185.5, "display": true, "message": "..."}
    try {
        final Map<String, dynamic> data = jsonDecode(message);
        bool display = data['display'] ?? false;
        
        if (display) {
            lastResultType = data['type'] ?? "Unknown";
            var spd = data['speed'];
            lastResultSpeed = (spd != null) ? "$spd km/h" : "";
            lastResultMessage = data['message'] ?? "";
            notifyListeners();
        }
    } catch (e) {
        print("JSON Error: $e");
    }
  }
}
