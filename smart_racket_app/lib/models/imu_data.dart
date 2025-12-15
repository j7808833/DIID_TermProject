import 'dart:typed_data';

class IMUData {
  // ---- Data model ----
  //
  // 這個 class 是「單筆 IMU 取樣」的不可變資料模型（immutable record）。
  // 用途：
  // - BLE notify 收到的封包 -> 解析成 IMUData
  // - UI / Buffer / Firebase 上傳都以這個型別做統一資料介面
  // - toJson() 直接對應資料庫欄位，避免各層自己拼 JSON 造成欄位不一致
  final int timestampMs;
  final double accX, accY, accZ;   // g
  final double gyroX, gyroY, gyroZ; // dps
  final double voltage;            // V

  const IMUData({
    required this.timestampMs,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.voltage,
  });

  // ---- Convenience derived value ----
  //
  // 對 UI/顯示與 log 較友善的秒制時間戳；資料本體仍維持 ms（與封包一致）。
  double get timestampSec => timestampMs / 1000.0;

  // ---- Serialization ----
  //
  // 將資料轉成可直接寫入 Firebase/JSON 的 Map。
  // key 命名固定（ts_ms / accX / gyroZ ...），讓後端與分析 pipeline 有穩定 schema。
  Map<String, dynamic> toJson() => {
    'ts_ms': timestampMs,
    'accX': accX,
    'accY': accY,
    'accZ': accZ,
    'gyroX': gyroX,
    'gyroY': gyroY,
    'gyroZ': gyroZ,
    'voltage': voltage,
  };

  // ---- Packet parsing entrypoint ----
  //
  // BLE 通知資料進來後，從原始 bytes 解析出 IMUData。
  // 支援兩種長度：
  // - 30 bytes：標準格式（完整一筆）
  // - 34 bytes：容錯情境（前面可能多了 4 bytes header / 對齊偏移），所以會嘗試 offset=0 與 offset=4
  //
  // 策略：
  // 1) 先嘗試 _parseAt(b, 0)
  // 2) 若長度 >= 34，再嘗試 _parseAt(b, 4)
  // 3) 用 plausibility score 挑比較合理的一個，避免錯位解析成 NaN/極端值還被接受
  static IMUData fromPacket(List<int> bytes) {
    final b = Uint8List.fromList(bytes);

    if (b.length != 30 && b.length != 34) {
      throw FormatException('Invalid IMU packet length: ${b.length}');
    }

    IMUData? a;
    IMUData? c;

    try {
      a = _parseAt(b, 0);
    } catch (_) {}

    if (b.length >= 34) {
      try {
        c = _parseAt(b, 4);
      } catch (_) {}
    }

    final pick = _pickMorePlausible(a, c);
    if (pick == null) throw FormatException('Cannot parse IMU packet');
    return pick;
  }

  // ---- Candidate selection ----
  //
  // a/b 代表不同 offset 解析結果；這裡做：
  // - 任一為 null：回傳另一個
  // - 兩者皆存在：用 _score 做 plausibility 打分，挑分數高者
  static IMUData? _pickMorePlausible(IMUData? a, IMUData? b) {
    if (a == null && b == null) return null;
    if (a != null && b == null) return a;
    if (a == null && b != null) return b;

    final sa = _score(a!);
    final sb = _score(b!);
    return (sb > sa) ? b : a;
  }

  // ---- Plausibility scoring ----
  //
  // 用「範圍合理性」快速判斷解析結果是否可信（避免錯位導致的亂數/爆值）。
  // 注意這是 heuristic，不是校正：因此 range 故意放寬（避免運動瞬間被誤殺）。
  //
  // 分數越高表示越像真實 IMU 數據。
  static int _score(IMUData d) {
    int s = 0;

    // accel plausible range (g) - 放寬避免誤殺
    if (d.accX.abs() < 80) s++;
    if (d.accY.abs() < 80) s++;
    if (d.accZ.abs() < 80) s++;

    // gyro plausible range (dps)
    if (d.gyroX.abs() < 10000) s++;
    if (d.gyroY.abs() < 10000) s++;
    if (d.gyroZ.abs() < 10000) s++;

    // voltage plausible
    if (d.voltage > 2.0 && d.voltage < 5.8) s++;

    // ts non-negative
    if (d.timestampMs >= 0) s++;

    return s;
  }

  // ---- Low-level binary layout parser ----
  //
  // 封包 layout（小端序）：
  // u32 ts(ms)
  // f32 accX, accY, accZ
  // f32 gyroX, gyroY, gyroZ
  // u16 voltage(mV)
  //
  // offset 允許從封包頭開始或跳過 4 bytes（用於容錯/對齊偏移）。
  // 解析後立即做 finite 檢查，避免 NaN/Inf 進入系統造成後續 UI/統計/上傳污染。
  static IMUData _parseAt(Uint8List b, int offset) {
    // Layout: u32 ts(ms) + f32 acc*3 + f32 gyro*3 + u16 voltage(mV)
    final need = offset + 4 + 12 + 12 + 2;
    if (b.length < need) throw FormatException('Not enough bytes');

    final bd = ByteData.sublistView(b);

    final ts = bd.getUint32(offset + 0, Endian.little);

    final ax = bd.getFloat32(offset + 4, Endian.little);
    final ay = bd.getFloat32(offset + 8, Endian.little);
    final az = bd.getFloat32(offset + 12, Endian.little);

    final gx = bd.getFloat32(offset + 16, Endian.little);
    final gy = bd.getFloat32(offset + 20, Endian.little);
    final gz = bd.getFloat32(offset + 24, Endian.little);

    final mv = bd.getUint16(offset + 28, Endian.little);
    final v = mv / 1000.0;

    if (!ax.isFinite || !ay.isFinite || !az.isFinite) {
      throw FormatException('acc not finite');
    }
    if (!gx.isFinite || !gy.isFinite || !gz.isFinite) {
      throw FormatException('gyro not finite');
    }

    return IMUData(
      timestampMs: ts,
      accX: ax,
      accY: ay,
      accZ: az,
      gyroX: gx,
      gyroY: gy,
      gyroZ: gz,
      voltage: v,
    );
  }

  // ---- Debug / logging ----
  //
  // 針對 log、console、debug UI 的人類可讀格式：
  // - ts 以秒顯示（3 位小數）
  // - acc 以 g 顯示（3 位）
  // - gyro 以 dps 顯示（1 位）
  // - voltage 以 V 顯示（3 位）
  @override
  String toString() {
    return 'ts=${timestampSec.toStringAsFixed(3)} '
        'acc=(${accX.toStringAsFixed(3)},${accY.toStringAsFixed(3)},${accZ.toStringAsFixed(3)}) '
        'gyro=(${gyroX.toStringAsFixed(1)},${gyroY.toStringAsFixed(1)},${gyroZ.toStringAsFixed(1)}) '
        'v=${voltage.toStringAsFixed(3)}';
  }
}
