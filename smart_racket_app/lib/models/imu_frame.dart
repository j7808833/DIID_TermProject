import 'imu_data.dart';

class IMUFrame {
  // ---- Feature / inference input frame ----
  //
  // IMUFrame 是「模型/推論/視窗化」用的資料單位，和 IMUData 的差別在於：
  // - IMUData：忠實對應 BLE 原始封包欄位（timestampMs + acc/gyro 分量 + voltage），偏資料蒐集與上傳
  // - IMUFrame：轉成推論友善的表示（秒制 timestamp、向量化 acc/gyro、可套用 offset 校正）
  //
  // 常見用途：
  // - 組成滑動視窗（List<IMUFrame>）送到 WebSocket/本地模型
  // - 做即時顯示或統計（向量形式更好處理）
  final double timestamp; // seconds
  final List<double> acc; // [x,y,z] in g
  final List<double> gyro; // [x,y,z] in dps
  final double voltage; // V

  const IMUFrame({
    required this.timestamp,
    required this.acc,
    required this.gyro,
    required this.voltage,
  });

  // ---- Conversion from raw sample with calibration offsets ----
  //
  // 這個 factory 以 IMUData 為輸入，並套用 accOffset / gyroOffset（通常來自校正或靜止估計）：
  // - offset 設計成 List<double> 以便 UI/設定層用同一種資料結構管理三軸偏移
  // - offset 可能為空或不足三個元素，因此每個軸都用長度檢查做防呆（缺值視為 0）
  //
  // 產出：
  // - timestamp：直接採 raw.timestampSec（秒）
  // - acc/gyro：三軸向量化後回傳，方便後續 windowing / JSON / 向量運算
  factory IMUFrame.fromIMUData(
      IMUData raw, {
        required List<double> accOffset,
        required List<double> gyroOffset,
      }) {
    final ax = raw.accX - (accOffset.isNotEmpty ? accOffset[0] : 0);
    final ay = raw.accY - (accOffset.length > 1 ? accOffset[1] : 0);
    final az = raw.accZ - (accOffset.length > 2 ? accOffset[2] : 0);

    final gx = raw.gyroX - (gyroOffset.isNotEmpty ? gyroOffset[0] : 0);
    final gy = raw.gyroY - (gyroOffset.length > 1 ? gyroOffset[1] : 0);
    final gz = raw.gyroZ - (gyroOffset.length > 2 ? gyroOffset[2] : 0);

    return IMUFrame(
      timestamp: raw.timestampSec,
      acc: [ax, ay, az],
      gyro: [gx, gy, gz],
      voltage: raw.voltage,
    );
  }

  // ---- Serialization (WebSocket / backend friendly) ----
  //
  // 這個 JSON schema 相對精簡：
  // - ts：秒制 timestamp
  // - acc/gyro：直接用向量（List<double>），對模型端或伺服器端組 tensor 很方便
  // - v：電壓（保留基本監控資訊）
  Map<String, dynamic> toJson() => {
    'ts': timestamp,
    'acc': acc,
    'gyro': gyro,
    'v': voltage,
  };

  // ---- Debug / logging ----
  //
  // 以固定小數位輸出，方便在 console 或 log 快速比對：
  // - timestamp：3 位
  // - acc：3 位
  // - gyro：1 位
  // - voltage：3 位
  @override
  String toString() {
    return 'ts=${timestamp.toStringAsFixed(3)} '
        'acc=${acc.map((e) => e.toStringAsFixed(3)).toList()} '
        'gyro=${gyro.map((e) => e.toStringAsFixed(1)).toList()} '
        'v=${voltage.toStringAsFixed(3)}';
  }
}
