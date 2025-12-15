import 'package:flutter/foundation.dart';
import 'package:smart_racket_app/models/imu_data.dart';

@immutable
class IMUFrame {
  final double timestamp; // 時間戳（秒），供 UI 繪圖 / 視窗切片 / 推論序列使用
  final List<double> acc; // 加速度三軸（g），已套用 offset 與數值防呆
  final List<double> gyro; // 角速度三軸（dps），已套用 offset 與數值防呆
  final double voltage; // 電壓（V），供電源狀態顯示或記錄

  const IMUFrame({
    required this.timestamp,
    required this.acc,
    required this.gyro,
    required this.voltage,
  });

  factory IMUFrame.fromIMUData(
      IMUData raw, {
        List<double>? accOffset,
        List<double>? gyroOffset,
      }) {
    // Offset 用於校正感測器零偏；若未提供或長度不足，視為 0 向量
    final ao = (accOffset != null && accOffset.length >= 3)
        ? accOffset
        : const [0.0, 0.0, 0.0];
    final go = (gyroOffset != null && gyroOffset.length >= 3)
        ? gyroOffset
        : const [0.0, 0.0, 0.0];

    // 防止 NaN / Infinity 汙染下游：UI 繪圖、觸發判定、序列化、模型推論等流程
    double safe(double v) => (v.isFinite && !v.isNaN) ? v : 0.0;

    // 加速度套用 offset（零偏校正）並做安全化處理
    final ax = safe(raw.accX - ao[0]);
    final ay = safe(raw.accY - ao[1]);
    final az = safe(raw.accZ - ao[2]);

    // 角速度套用 offset（零偏校正）並做安全化處理
    final gx = safe(raw.gyroX - go[0]);
    final gy = safe(raw.gyroY - go[1]);
    final gz = safe(raw.gyroZ - go[2]);

    // 原始時間戳由 ms 轉為 s，統一資料時間單位以利視窗化與同步
    final ts = safe(raw.timestampMs / 1000.0);
    final vv = safe(raw.voltage);

    return IMUFrame(
      timestamp: ts,
      acc: [ax, ay, az],
      gyro: [gx, gy, gz],
      voltage: vv,
    );
  }

  /// ✅ 供 WebSocket / 後端 / 記錄用途的資料格式（與既有 websocket_service.dart schema 對齊）
  Map<String, Object?> toJson() => <String, Object?>{
    'ts': timestamp,
    'acc': acc,
    'gyro': gyro,
    'voltage': voltage,
  };

  @override
  String toString() {
    // 用於 debug log：統一小數位，便於快速檢查數值漂移與感測器狀態
    return 'ts=${timestamp.toStringAsFixed(3)} '
        'acc=${acc.map((e) => e.toStringAsFixed(3)).toList()} '
        'gyro=${gyro.map((e) => e.toStringAsFixed(1)).toList()} '
        'voltage=${voltage.toStringAsFixed(3)}';
  }
}
