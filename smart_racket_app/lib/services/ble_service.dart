import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/imu_data.dart';

class BleService extends ChangeNotifier {
  // ===== Target =====
  //
  // BLE 掃描/連線的「唯一目標」：以裝置廣播名稱過濾（platformName）。
  // UUID 必須和韌體端一致：
  // - SERVICE_UUID：自訂 service
  // - CHAR_IMU_UUID：IMU notify characteristic（由裝置持續推資料）
  static const String targetName = 'SmartRacket';

  static const String SERVICE_UUID = "0769bb8e-b496-4fdd-b53b-87462ff423d0";
  static const String CHAR_IMU_UUID = "8ee82f5b-76c7-4170-8f49-fff786257090";

  final Guid _serviceUuid = Guid(SERVICE_UUID);
  final Guid _imuCharUuid = Guid(CHAR_IMU_UUID);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _imuChar;

  // Scan results (只留目標 0~1 台)
  //
  // UI 端用 scanResults 顯示候選裝置；這裡刻意只保留 targetName 第一台，
  // 讓 UI 邏輯與自動連線流程更單純（避免多台同名裝置的狀態分裂）。
  final List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  // Connection state stream
  //
  // connCtrl 是 broadcast，讓多個 consumer（Provider/UI/debug）都能訂閱連線狀態。
  // 同時也保留 _lastConnState，方便同步查詢與 UI mapping。
  final StreamController<BluetoothConnectionState> _connCtrl =
  StreamController<BluetoothConnectionState>.broadcast(sync: false);
  Stream<BluetoothConnectionState> get connectionStateStream => _connCtrl.stream;

  BluetoothConnectionState _lastConnState = BluetoothConnectionState.disconnected;
  BluetoothConnectionState get lastConnState => _lastConnState;

  bool get isConnected =>
      _device != null && _lastConnState == BluetoothConnectionState.connected;

  // IMU stream
  //
  // 由 BLE notify chunk -> ring buffer 組包 -> IMUData.fromPacket -> emit 到 imuDataStream。
  // 這條 stream 是 app 內唯一的 IMU 真實來源（後續 UI、record、detector 都靠它）。
  final StreamController<IMUData> _imuCtrl =
  StreamController<IMUData>.broadcast(sync: false);
  Stream<IMUData> get imuDataStream => _imuCtrl.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _devConnSub;
  StreamSubscription<List<int>>? _imuNotifySub;

  bool _isConnecting = false;
  bool _didSubscribe = false;
  bool _disposed = false;

  // ===== Packet format =====
  //
  // 韌體端 IMU 封包固定 30 bytes（u32 ts + 6x f32 + u16 mv），由 IMUData 解析。
  // notify chunk 可能不是 30 的倍數，因此需要 ring buffer 做組包與 resync。
  static const int _packetLen = 30;

  // ===== Ring buffer =====
  //
  // BLE notify 在 Android/iOS 可能分段、可能 MTU 改變，chunk 長度不固定；
  // 以固定大小 ring buffer 收集 raw bytes，並在 drain() 中按 30 bytes 切包解析。
  //
  // _head/_tail/_len：典型環狀佇列游標/長度；避免頻繁 allocation。
  static const int _ringSize = 8192;
  final Uint8List _ring = Uint8List(_ringSize);
  int _head = 0;
  int _tail = 0;
  int _len = 0;

  // ===== Drain scheduling =====
  //
  // drain 採用「排程一次、批次處理」模式：
  // - _drainScheduled：避免每個 notify chunk 都同步 drain（造成回呼過深/卡 UI thread）
  // - _maxPacketsPerDrain：單次 drain 最多解析幾包，避免長時間佔用事件迴圈
  // - _maxResyncStep：錯位時最多 drop 幾次，超過就 reset（避免無限 resync）
  bool _drainScheduled = false;
  static const int _maxPacketsPerDrain = 24;
  static const int _maxResyncStep = 256;

  // ===== Output rate limit =====
  //
  // 某些裝置端可能實際輸出頻率 > 100Hz，或 notify 合併導致 burst；
  // 這裡用 microseconds 節流，固定最大輸出率 ~100Hz，降低上層 UI/record 壓力。
  static const int _emitIntervalUs = 10000; // 10ms => 100Hz
  int _lastEmitUs = 0;

  // 用 Stopwatch 比 DateTime.now 便宜
  final Stopwatch _sw = Stopwatch()..start();

  // 用 generation token 中止舊 drain
  //
  // 任何 resetRx/disconnect 都會遞增 _rxGen。
  // drain(gen) 在進入與迴圈中都會檢查 gen 是否仍有效，確保舊 drain 不會在斷線後繼續吐資料。
  int _rxGen = 0;

  // Debug throttling
  int _lastLogMs = 0;

  // reusable packet buffer (避免每包 new Uint8List)
  //
  // drain 時把 ring 內的 30 bytes copy 到這個固定緩衝，再交給 parser。
  // 好處：避免高頻 new Uint8List/ByteData 造成 GC 抖動。
  final Uint8List _pktBuf = Uint8List(_packetLen);

  // ---------------- public API ----------------
  //
  // startScan：
  // - 先 stopScan 清理上一輪 scan subscription
  // - startScan 8 秒 timeout
  // - 只保留 targetName 第一台裝置
  // - autoConnect：找到目標後自動 stopScan + connectToDevice
  Future<void> startScan({bool autoConnect = true}) async {
    await stopScan();
    _scanResults.clear();
    if (!_disposed) notifyListeners();

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      final racket = results.where((r) => r.device.platformName == targetName).toList();
      if (racket.isEmpty) return;

      _scanResults
        ..clear()
        ..add(racket.first);

      if (!_disposed) notifyListeners();

      if (autoConnect && !_isConnecting && !isConnected) {
        await stopScan();
        await connectToDevice(racket.first.device);
      }
    });
  }

  // stopScan：取消 scan subscription + 呼叫 FlutterBluePlus.stopScan()
  // stopScan() 可能在某些狀況 throw，因此用 try-catch 吃掉例外，避免 UI 中斷。
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    if (!_disposed) notifyListeners();
  }

  // connectToDevice：
  // - 重入保護（_isConnecting）
  // - reset RX 狀態、清掉舊 notify subscription/characteristic
  // - 若已連到另一台 device，先 disconnect
  // - 綁定 device.connectionState stream：在 connected 時 requestMtu + discover/subscribe
  // - 最後呼叫 device.connect(timeout)
  //
  // 這裡把「連線」與「subscribe notify」綁在 connectionState=connected 事件裡，
  // 避免 connect() 完成但 services 尚未 ready 的競態。
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;

    _resetRx();
    _didSubscribe = false;

    await _imuNotifySub?.cancel();
    _imuNotifySub = null;
    _imuChar = null;

    if (_device != null && _device!.remoteId != device.remoteId) {
      await disconnect();
    }
    _device = device;

    await _devConnSub?.cancel();
    _devConnSub = _device!.connectionState.listen((s) async {
      _lastConnState = s;
      if (!_connCtrl.isClosed) _connCtrl.add(s);
      if (!_disposed) notifyListeners();

      if (s == BluetoothConnectionState.connected) {
        try {
          try {
            final mtu = await _device!.requestMtu(185);
            if (kDebugMode) debugPrint('BLE MTU = $mtu');
          } catch (_) {}

          await _discoverAndSubscribeOnce();
        } catch (e) {
          if (kDebugMode) debugPrint('discover/subscribe failed: $e');
          await disconnect();
        }
      }

      if (s == BluetoothConnectionState.disconnected) {
        _resetRx();
        _didSubscribe = false;

        await _imuNotifySub?.cancel();
        _imuNotifySub = null;
        _imuChar = null;

        _scanResults.clear();
        if (!_disposed) notifyListeners();
      }
    });

    try {
      await _device!.connect(timeout: const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('connect failed: $e');
      await disconnect();
    } finally {
      _isConnecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // disconnect：
  // - 停止掃描
  // - reset RX + 清掉 subscribe 狀態
  // - cancel notify/connection subscriptions
  // - device.disconnect()
  // - 發出 disconnected 狀態到 conn stream
  // - 清空 scanResults
  //
  // 多層 try-catch 的目標是「斷線永遠不該讓 UI crash」：即使部分清理失敗也要完成主要狀態切換。
  Future<void> disconnect() async {
    try {
      await stopScan();
    } catch (_) {}

    _resetRx();
    _didSubscribe = false;

    try {
      await _imuNotifySub?.cancel();
    } catch (_) {}
    _imuNotifySub = null;

    try {
      await _devConnSub?.cancel();
    } catch (_) {}
    _devConnSub = null;

    try {
      if (_device != null) {
        await _device!.disconnect();
      }
    } catch (_) {}

    _device = null;
    _imuChar = null;

    _lastConnState = BluetoothConnectionState.disconnected;
    if (!_connCtrl.isClosed) _connCtrl.add(_lastConnState);

    _scanResults.clear();
    if (!_disposed) notifyListeners();
  }

  // ---------------- internal: discover/notify ----------------
  //
  // discoverServices() 後，鎖定指定 service UUID，再找指定 characteristic UUID。
  // 找到後 setNotifyValue(true) + onValueReceived.listen(_onNotifyChunk)。
  // _didSubscribe 用來保證只訂閱一次（避免重複 listen 造成資料重複與資源洩漏）。
  Future<void> _discoverAndSubscribeOnce() async {
    if (_didSubscribe) return;
    final d = _device;
    if (d == null) return;

    final services = await d.discoverServices();

    BluetoothCharacteristic? imuChar;
    for (final s in services) {
      if (s.uuid == _serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid == _imuCharUuid) {
            imuChar = c;
            break;
          }
        }
      }
      if (imuChar != null) break;
    }

    if (imuChar == null) throw StateError('IMU characteristic not found');

    _imuChar = imuChar;
    await _imuChar!.setNotifyValue(true);

    await _imuNotifySub?.cancel();
    _imuNotifySub = _imuChar!.onValueReceived.listen(
      _onNotifyChunk,
      onError: (e) {
        if (kDebugMode) debugPrint('notify error: $e');
      },
      cancelOnError: false,
    );

    _didSubscribe = true;
    if (!_disposed) notifyListeners();
  }

  // ---------------- RX + drain ----------------
  //
  // resetRx：
  // - 遞增 generation token 中止舊 drain
  // - 清空 ring buffer 游標/長度
  // - 重置排程旗標與輸出節流狀態
  void _resetRx() {
    _rxGen++; // ✅ 讓舊 drain 自動停
    _head = 0;
    _tail = 0;
    _len = 0;
    _drainScheduled = false;
    _lastEmitUs = 0;
  }

  // _onNotifyChunk：
  // - 將 notify chunk 逐 byte append 到 ring
  // - overflow：直接 resetRx（避免 ring wrap 後產生不可預期的錯位）
  // - 用 Timer.run() 排程 drain（把解析工作延後到事件迴圈，避免阻塞 notify callback）
  void _onNotifyChunk(List<int> chunk) {
    if (chunk.isEmpty) return;

    if (kDebugMode) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastLogMs > 1200) {
        _lastLogMs = nowMs;
        debugPrint('IMU notify len=${chunk.length} ringLen=$_len');
      }
    }

    // append into ring
    for (int i = 0; i < chunk.length; i++) {
      if (_len >= _ringSize) {
        _resetRx(); // overflow -> reset
        return;
      }
      _ring[_tail] = chunk[i];
      _tail = (_tail + 1) % _ringSize;
      _len++;
    }

    if (!_drainScheduled) {
      _drainScheduled = true;
      final gen = _rxGen;
      Timer.run(() => _drain(gen));
    }
  }

  // 便宜校驗：先不丟 exception，擋掉大多數錯位情況
  //
  // fromPacket() 會丟 exception（成本高）；這裡先做快速 plausibility 檢查：
  // - ts != 0
  // - voltage(mV) 在合理範圍
  // - 6 個 float 都 finite 且不爆值
  // 用來降低 resync 情境下大量 throw 的成本。
  bool _looksLikePacket(Uint8List pkt) {
    // packet layout:
    // u32 ts(ms) + f32 acc*3 + f32 gyro*3 + u16 voltage(mV)
    final bd = ByteData.sublistView(pkt);

    final ts = bd.getUint32(0, Endian.little);
    // ts 不要全部 0（你若允許 0，可把這行拿掉）
    if (ts == 0) return false;

    final v = bd.getUint16(28, Endian.little);
    // 電壓合理區間 (保守放大，避免誤殺)
    if (v < 2000 || v > 6000) return false;

    // float 檢查：只要 NaN/Inf 就判無效；範圍先放寬
    for (int off = 4; off <= 24; off += 4) {
      final f = bd.getFloat32(off, Endian.little);
      if (!f.isFinite || f.isNaN) return false;
      if (f.abs() > 20000) return false; // 極端值通常是錯位
    }
    return true;
  }

  // ring -> _pktBuf copy（固定 30 bytes），避免每次解析都 allocate 新 buffer。
  void _readPacketIntoBuf() {
    // copy 30 bytes into _pktBuf (no allocation)
    for (int j = 0; j < _packetLen; j++) {
      _pktBuf[j] = _ring[(_head + j) % _ringSize];
    }
  }

  // resync 時逐 byte drop（典型的 framed stream 對齊策略）
  void _drop1() {
    _head = (_head + 1) % _ringSize;
    _len -= 1;
  }

  // 成功解析一包就 consume 30 bytes
  void _consumePacket() {
    _head = (_head + _packetLen) % _ringSize;
    _len -= _packetLen;
  }

  // drain：
  // - 批次處理 ring 內的封包（最多 _maxPacketsPerDrain）
  // - 每包先 _looksLikePacket()，不合理就 resync drop1
  // - 合理再 IMUData.fromPacket()；若仍失敗就 drop1
  // - resyncSteps 超過上限則 resetRx（視為資料流已嚴重錯位/破損）
  // - 成功解析後做輸出節流（100Hz），再 emit 到 imu stream
  //
  // 這裡刻意使用 generation token（gen）避免 disconnect/reset 後舊 drain 繼續跑。
  void _drain(int gen) {
    // ✅ 若 resetRx/disconnect 發生，舊 drain 直接停止
    if (gen != _rxGen) return;

    _drainScheduled = false;

    int processed = 0;
    int resyncSteps = 0;

    while (_len >= _packetLen && processed < _maxPacketsPerDrain) {
      if (gen != _rxGen) return; // 中途也可中止

      _readPacketIntoBuf();

      // ✅ 先做便宜校驗，避免 fromPacket 大量 throw
      if (!_looksLikePacket(_pktBuf)) {
        _drop1();
        resyncSteps++;
        if (resyncSteps >= _maxResyncStep) {
          _resetRx();
          return;
        }
        continue;
      }

      IMUData imu;
      try {
        imu = IMUData.fromPacket(_pktBuf);
      } catch (_) {
        // fromPacket 還是失敗 -> resync drop 1
        _drop1();
        resyncSteps++;
        if (resyncSteps >= _maxResyncStep) {
          _resetRx();
          return;
        }
        continue;
      }

      // 成功就重置 resyncSteps（避免偶發錯位累積到上限）
      resyncSteps = 0;

      _consumePacket();

      // output rate limit
      final nowUs = _sw.elapsedMicroseconds;
      if (nowUs - _lastEmitUs >= _emitIntervalUs) {
        _lastEmitUs = nowUs;
        if (!_imuCtrl.isClosed) _imuCtrl.add(imu);
      }

      processed++;
    }

    // 還有很多資料 -> 下一輪再處理
    if (_len >= _packetLen && !_drainScheduled) {
      _drainScheduled = true;
      final g2 = _rxGen;
      Timer.run(() => _drain(g2));
    }
  }

  // ---------------- cleanup ----------------
  //
  // _cleanup：用於 dispose 時的非同步清理流程：
  // - disconnect（包含取消 subs、device disconnect、狀態重置）
  // - 關閉 imu/conn stream controller（避免後續 add 造成例外）
  Future<void> _cleanup() async {
    await disconnect();
    try {
      await _imuCtrl.close();
    } catch (_) {}
    try {
      await _connCtrl.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _resetRx(); // ✅ 確保中止 drain
    unawaited(_cleanup());
    super.dispose();
  }
}
