import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/imu_data.dart';
import '../models/imu_frame.dart';
import '../services/ble_service.dart';
import '../services/data_buffer_manager.dart';
import '../services/firebase_service.dart';
import '../services/websocket_service.dart';

class HomeProvider extends ChangeNotifier {
  // ---- Dependencies (injected by ProxyProvider) ----
  //
  // HomeProvider 是整個 App 的「協調層 / 統一狀態入口」：
  // - _ble：BLE 掃描/連線/即時 IMU stream
  // - _firebase：錄製 session 與上傳（研究/資料蒐集流程）
  // - _ws：推論服務通道（window -> server -> result 回來）
  // - _bufferMgr：把即時 frame 聚合成滑動視窗/segment、觸發送出條件（threshold 等）
  //
  // 這些依賴不在 constructor 直接注入，而是由 updateDeps() 在 Provider update 階段注入，
  // 確保 service instance 更新時 HomeProvider 不必重建（狀態可保留）。
  BleService? _ble;
  FirebaseService? _firebase;
  WebSocketService? _ws;
  DataBufferManager? _bufferMgr;

  // ---- Stream subscriptions ----
  //
  // 只保留一條 BLE IMU stream 的 listen：同時支援 UI 顯示、Detector/windowing、以及錄製寫入。
  // WebSocket stream 也是單一路徑進來，集中在 _onWsMessage() 解析與更新 UI state。
  StreamSubscription<IMUData>? _imuSub;
  StreamSubscription<dynamic>? _wsMsgSub;

  // ---- Live data cache + recent frames buffer (UI snapshot) ----
  //
  // _recentFrames：最近一段時間的 IMUFrame ring buffer（ListQueue，避免頻繁搬移）
  // _recentSnapshot / _recentSnapshotSeq：提供 UI “不可變快照” 的資料給 chart/realtime panel，
  //   並用 seq 讓 UI 判斷是否有新資料（比直接暴露 queue 更安全）
  final ListQueue<IMUFrame> _recentFrames = ListQueue<IMUFrame>();
  IMUData? latestData;

  IMUFrame? _latestFrame;
  IMUFrame? get latestFrame => _latestFrame;

  // ---- Battery voltage (UI friendly) ----
  //
  // 直接從 latestData 取電壓，並做 finite/NaN 防呆，避免 UI 顯示炸掉或統計被污染。
  double get batteryVoltage {
    final v = latestData?.voltage;
    if (v == null || !v.isFinite || v.isNaN) return 0.0;
    return v;
  }

  List<IMUFrame> _recentSnapshot = const [];
  int _recentSnapshotSeq = 0;
  List<IMUFrame> get recentFramesSnapshot => _recentSnapshot;
  int get recentFramesSnapshotSeq => _recentSnapshotSeq;

  // ---- UI throttling / batching ----
  //
  // _dirty：表示狀態有更新，但不一定要每次 IMU 來就 notify
  // _uiTimer：固定頻率把 _recentFrames 轉 snapshot，並做一次 notifyListeners()
  // 目的：避免高頻 IMU stream 造成 rebuild/GC 壓力，讓 UI 更新維持可控節奏。
  bool _dirty = false;
  Timer? _uiTimer;

  // ---- Calibration offsets ----
  //
  // _accOffset/_gyroOffset：校正用偏移量（通常在靜止時取樣一次）
  // _isCalibrated：UI 顯示與流程 gating（例如顯示已校正狀態、或在 Detector 端做補償）
  final List<double> _accOffset = [0, 0, 0];
  final List<double> _gyroOffset = [0, 0, 0];
  bool _isCalibrated = false;
  bool get isCalibrated => _isCalibrated;

  // ---- Swing counters (classification result aggregation) ----
  //
  // 這些計數由 WS 回傳的 shot type 累積（Smash/Drive/Drop/Clear/Net），
  // 提供 Stats/Record UI 顯示與 reset。
  int smash = 0, drive = 0, drop = 0, clear = 0, net = 0;

  Map<String, int> get swingCounts => {
    'Smash': smash,
    'Drive': drive,
    'Drop': drop,
    'Clear': clear,
    'Net': net,
  };

  int get totalSwings => smash + drive + drop + clear + net;

  void resetSwingCounts() {
    smash = 0;
    drive = 0;
    drop = 0;
    clear = 0;
    net = 0;
    _markDirty();
  }

  // ---- Last inference result (UI binding) ----
  //
  // lastResultType/speed/message：讓 UI 可以顯示「最近一次辨識結果」。
  // _setLastResult() 只在輸入字串非空時更新，避免把已存在資訊覆蓋成空值。
  String _lastResultType = '—';
  String _lastResultSpeed = '—';
  String _lastResultMessage = 'No result yet';

  String get lastResultType => _lastResultType;
  String get lastResultSpeed => _lastResultSpeed;
  String get lastResultMessage => _lastResultMessage;

  void _setLastResult({String? type, String? speed, String? message}) {
    if (type != null && type.trim().isNotEmpty) _lastResultType = type.trim();
    if (speed != null && speed.trim().isNotEmpty) _lastResultSpeed = speed.trim();
    if (message != null && message.trim().isNotEmpty) _lastResultMessage = message.trim();
  }

  // ---- Shot popup trigger (ephemeral UI event) ----
  //
  // shotPopupSeq：用「序號遞增」觸發一次性 UI 動畫/提示（避免只靠字串變動被去重）
  // shotPopupType：提示要顯示哪一種球種
  int _shotPopupSeq = 0;
  String _shotPopupType = '';

  int get shotPopupSeq => _shotPopupSeq;
  String get shotPopupType => _shotPopupType;

  void _bumpShotPopup(String type) {
    _shotPopupType = type;
    _shotPopupSeq++;
  }

  // ===== settings =====
  //
  // sensitivity：對應 DataBufferManager 的 trigger threshold（例如 g 門檻）
  // serverIp：UI 輸入欄位保存（可為 domain/IP/含 scheme）
  double _sensitivity = 2.0;
  String _serverIp = '';

  double get sensitivity => _sensitivity;
  String get serverIp => _serverIp;

  // ---- Settings update pipeline ----
  //
  // 1) 更新本地設定
  // 2) 把 sensitivity 寫進 bufferMgr 的 threshold（影響 segment 觸發）
  // 3) 解析 ws URL，若有效就重連（避免 UI 還留在舊 server）
  // 4) 通知 UI（通常 Settings/Realtime 頁會反映）
  void updateSettings(double sensitivity, String ip) {
    _sensitivity = sensitivity;
    _serverIp = ip.trim();

    setTriggerThreshold(_sensitivity);

    final url = _toWsUrl(_serverIp);
    if (url.isNotEmpty) {
      // ignore: discarded_futures
      _reconnectWs(url);
    }

    _markDirtyAndNotifySoon();
  }

  // ---- WebSocket reconnection helper ----
  //
  // 保守做法：先 disconnect 再 connect，避免重複連線/殘留 subscription。
  // disconnect/connect 都用 try-catch 吃掉錯誤，讓 UI 不因偶發連線失敗整段崩掉。
  Future<void> _reconnectWs(String url) async {
    try {
      await _ws?.disconnect();
    } catch (_) {}
    try {
      await _ws?.connect(url);
    } catch (_) {}
  }

  // ---- URL normalization ----
  //
  // 支援輸入：
  // - ws:// / wss://（原樣）
  // - http:// / https://（轉成 ws:// / wss://）
  // - 裸 IP / localhost（預設 ws://）
  // - 裸 domain（預設 wss://）
  //
  // 目的：讓 UI 不需要要求使用者一定要填 scheme，也能直覺輸入。
  String _toWsUrl(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';

    if (s.startsWith('ws://') || s.startsWith('wss://')) return s;
    if (s.startsWith('http://')) return 'ws://${s.substring('http://'.length)}';
    if (s.startsWith('https://')) return 'wss://${s.substring('https://'.length)}';

    final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$').hasMatch(s);
    final isLocal = s.startsWith('localhost') || s.startsWith('127.');
    final scheme = (isIp || isLocal) ? 'ws://' : 'wss://';
    return '$scheme$s';
  }

  // ===== connection UI =====
  //
  // isConnected：給 UI 判斷連線狀態（按鈕顯示/掃描行為）
  // connectionStatus：把 ble 的 connection state 映射成 UI 字串（容錯保留未知狀態）
  bool get isConnected => _ble?.isConnected ?? false;

  String get connectionStatus {
    final s = _ble?.lastConnState;
    if (s == null) return '';
    final n = s.name;

    if (n == 'connected') return 'Connected';
    if (n == 'disconnected') return 'Disconnected';

    // 如果你的 ble_service 仍會出現 connecting/disconnecting，就顯示文字；
    // 若你想消掉 warning，warning 應該在 ble_service 裡，不在這裡。
    if (n == 'connecting') return 'Connecting...';
    if (n == 'disconnecting') return 'Disconnecting...';
    return n;
  }

  // ===== record UI =====
  //
  // 這三個旗標是 UI 層狀態機：
  // - _isRecordingUi：是否處於錄製狀態
  // - _isPausedUi：錄製中暫停（暫停時仍可收 IMU，但不寫入 Firebase）
  // - _recordOpBusy：避免 start/stop/pause/resume 重入造成 session 狀態錯亂
  bool _isRecordingUi = false;
  bool _isPausedUi = false;
  bool _recordOpBusy = false;

  bool get isRecording => _isRecordingUi;
  bool get isPaused => _isPausedUi;

  // 直接轉接 FirebaseService 的 session & upload counters，供 RecordPage 顯示
  String? get currentSessionId => _firebase?.sessionId;
  int get uploadedCount => _firebase?.uploadedCount ?? 0;
  int get pendingCount => _firebase?.pendingCount ?? 0;

  HomeProvider();

  // ====== THROTTLE ======
  //
  // 多個 throttle timestamp：
  // - _lastUiMs：控制 recentFrames push/trim 的頻率（避免每個 sample 都造成大量資料結構操作）
  // - _lastDetectMs：控制 detector/frame 建立頻率（避免過密）
  // - _lastWsMs：控制 segment 送 WS 的頻率（避免 server 壓力/網路壅塞）
  // - _lastWsParseMs：控制 WS 回傳解析頻率（避免 spam message 造成 UI 螺旋）
  int _lastUiMs = 0;
  int _lastDetectMs = 0;
  int _lastWsMs = 0;
  int _lastWsParseMs = 0;

  void _markDirty() => _dirty = true;

  // 這裡名稱叫 notifySoon，但實作是立即 notify；真正的 “batch” 主要靠 _uiTimer 做。
  void _markDirtyAndNotifySoon() {
    _markDirty();
    notifyListeners();
  }

  // ---------------- deps binding ----------------
  //
  // Provider update 階段呼叫，用來注入依賴並在變更時重新綁定 streams。
  // changed 條件用 instance 比較，避免每次 update() 都重建 subscription。
  void updateDeps({
    required BleService ble,
    required FirebaseService firebase,
    required WebSocketService ws,
    required DataBufferManager bufferMgr,
  }) {
    final changed = _ble != ble || _firebase != firebase || _ws != ws || _bufferMgr != bufferMgr;

    _ble = ble;
    _firebase = firebase;
    _ws = ws;
    _bufferMgr = bufferMgr;

    if (changed) _bindStreams();
  }

  // ---------------- stream wiring ----------------
  //
  // 重新綁定時先 cancel 舊 subscription + timer，避免重複 listen/重複通知。
  // UI timer 以固定 250ms 節奏把 queue 轉成 snapshot 並 notify（只在 dirty 時做）。
  void _bindStreams() {
    _imuSub?.cancel();
    _wsMsgSub?.cancel();
    _uiTimer?.cancel();

    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_dirty) return;
      _dirty = false;
      _recentSnapshot = _recentFrames.toList(growable: false);
      _recentSnapshotSeq++;
      notifyListeners();
    });

    final ble = _ble;
    final ws = _ws;

    if (ble != null) {
      _imuSub = ble.imuDataStream.listen(_onImuData);
    }
    if (ws != null) {
      _wsMsgSub = ws.stream.listen(_onWsMessage);
    }
  }

  // ---------------- BLE actions ----------------
  //
  // 這兩個方法是給 UI 的操作入口：
  // - startScan(autoConnect:true)：掃描並嘗試自動連線指定裝置
  // - disconnectBle()：主動斷線
  Future<void> startScan() async {
    await _ble?.startScan(autoConnect: true);
    _markDirtyAndNotifySoon();
  }

  Future<void> disconnectBle() async {
    await _ble?.disconnect();
    _markDirtyAndNotifySoon();
  }

  // ---------------- IMU live stream (UI/Detector + Recording) ----------------
  //
  // IMUData 進來後同時完成三件事：
  // 1) UI：更新 latestData/latestFrame + recent frames buffer（節流後）
  // 2) 錄製：若錄製中且未暫停，寫入 FirebaseService（同一條 stream，不另外開 listen）
  // 3) Detector/windowing：轉 IMUFrame -> 丟給 bufferMgr 聚合成 segment -> 節流送到 WS
  void _onImuData(IMUData d) {
    latestData = d;

    // ✅ 錄製寫入（同一條 stream，不再開第二個 listen）
    if (_isRecordingUi && !_isPausedUi) {
      _firebase?.addData(d);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // detector throttle
    if (_lastDetectMs != 0 && (nowMs - _lastDetectMs) < 10) return;
    _lastDetectMs = nowMs;

    final f = IMUFrame.fromIMUData(
      d,
      accOffset: _accOffset,
      gyroOffset: _gyroOffset,
    );
    _latestFrame = f;

    final seg = _bufferMgr?.addFrame(f);
    if (seg != null && seg.isNotEmpty) {
      if (_lastWsMs == 0 || (nowMs - _lastWsMs) >= 200) {
        _lastWsMs = nowMs;

        // ✅ 兼容：你的 ws service 可能叫 enqueueWindow 或 sendWindow
        final ws = _ws;
        if (ws != null) {
          try {
            (ws as dynamic).enqueueWindow(seg);
          } catch (_) {
            try {
              (ws as dynamic).sendWindow(seg);
            } catch (_) {}
          }
        }
      }
      _markDirty();
    }

    if (_lastUiMs == 0 || (nowMs - _lastUiMs) >= 20) {
      _lastUiMs = nowMs;

      _recentFrames.addLast(f);
      while (_recentFrames.length > 220) {
        _recentFrames.removeFirst();
      }
      _markDirty();
    }
  }

  // ---------------- calibration ----------------
  //
  // calibration 的策略是「取最新一筆 raw 當 offset」：
  // - 若沒有 latestData：標記未校正
  // - 若有：把 acc/gyro 三軸直接存入 offset
  // 對 detector 來說相當於把後續資料做 baseline subtraction。
  Future<void> startCalibration() async => calibrateOffsets();

  void calibrateOffsets() {
    final d = latestData;
    if (d == null) {
      _isCalibrated = false;
      _markDirtyAndNotifySoon();
      return;
    }

    _accOffset[0] = d.accX;
    _accOffset[1] = d.accY;
    _accOffset[2] = d.accZ;

    _gyroOffset[0] = d.gyroX;
    _gyroOffset[1] = d.gyroY;
    _gyroOffset[2] = d.gyroZ;

    _isCalibrated = true;
    _markDirtyAndNotifySoon();
  }

  // threshold 直接委派給 bufferMgr（讓 windowing/trigger 行為統一在 bufferMgr）
  void setTriggerThreshold(double g) {
    _bufferMgr?.updateThreshold(g);
    _markDirtyAndNotifySoon();
  }

  // ---------------- record controls (UI call) ----------------
  //
  // 這四個是給 UI 用的語意化入口（名稱對齊 UI 按鈕）
  // 內部直接轉呼叫 core 版本的 start/stop/pause/resume。
  Future<void> startRecord({String deviceId = 'SmartRacket'}) async {
    await startRecording(deviceId: deviceId);
  }

  Future<void> stopRecord({String? label}) async {
    await stopRecording(label: label);
  }

  Future<void> pauseRecord() async {
    await pauseRecording();
  }

  Future<void> resumeRecord() async {
    await resumeRecording();
  }

  // ---------------- record controls (core) ----------------
  //
  // startRecording：
  // - busy/重入保護
  // - 必須先 BLE connected（避免建立了 session 卻沒有資料流）
  // - 啟動 Firebase session
  // - 若 ws 支援 setClientId，用 sessionId 當 client_id（server 端可對應同一場錄製）
  // - 更新 UI flag
  Future<void> startRecording({String deviceId = 'SmartRacket'}) async {
    if (_recordOpBusy) return;
    if (_isRecordingUi) return;

    // ✅ 沒連線就不開始（避免看起來有 session 但其實沒資料）
    if (!isConnected) return;

    _recordOpBusy = true;
    try {
      await _firebase?.startSession(deviceId: deviceId, sampleRate: 100);

      final sid = _firebase?.sessionId;
      if (sid != null) {
        // 兼容：若你的 ws 有 setClientId 就用，沒有就略過
        try {
          (_ws as dynamic).setClientId(sid);
        } catch (_) {}
      }

      _isRecordingUi = true;
      _isPausedUi = false;

      _markDirtyAndNotifySoon();
    } catch (_) {
      _isRecordingUi = false;
      _isPausedUi = false;
      _markDirtyAndNotifySoon();
      rethrow;
    } finally {
      _recordOpBusy = false;
    }
  }

  // pause/resume 的語意是「不斷 BLE stream，不寫入 Firebase」
  // 具體做法：只切 UI flag，_onImuData() 會依 flag 擋掉 addData(d)。
  Future<void> pauseRecording() async {
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;
    if (_isPausedUi) return;

    _recordOpBusy = true;
    try {
      _isPausedUi = true; // ✅ 暫停=停止寫入（_onImuData 會擋）
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  Future<void> resumeRecording() async {
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;
    if (!_isPausedUi) return;

    _recordOpBusy = true;
    try {
      _isPausedUi = false; // ✅ 繼續=恢復寫入
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  // stopRecording：
  // - 先把 UI state 關掉（讓 UI 立即回到未錄製狀態）
  // - 再呼叫 firebase endSession 做 flush/完成標記（可能耗時）
  // - label 由 UI 提供，用於後續資料分析/分段標記
  Future<void> stopRecording({String? label}) async {
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;

    _recordOpBusy = true;
    try {
      // ✅ 先把 UI 狀態關掉（你 RecordPage 的「再按一下=結束一段」就靠這裡）
      _isRecordingUi = false;
      _isPausedUi = false;
      _markDirtyAndNotifySoon();

      // ✅ 真的結束 session（flush + completed）
      await _firebase?.endSession(label: label);
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  // clearRecord 是「重置整個 session/UI/統計」的 hard reset：
  // - 取消 firebase session（若存在）
  // - 嘗試清空 bufferMgr（兼容：可能沒有 clear()）
  // - 清空 recent frames / latest frame / inference result / popup state
  // - 重置 throttle timestamp，避免下一輪被錯誤節流
  Future<void> clearRecord() async {
    _isRecordingUi = false;
    _isPausedUi = false;
    _markDirtyAndNotifySoon();

    await _firebase?.cancelSession();

    // 兼容：bufferMgr 可能沒有 clear()
    final bm = _bufferMgr;
    if (bm != null) {
      try {
        (bm as dynamic).clear();
      } catch (_) {}
    }

    _recentFrames.clear();
    _recentSnapshot = const [];
    _recentSnapshotSeq++;

    _latestFrame = null;

    _lastResultType = '—';
    _lastResultSpeed = '—';
    _lastResultMessage = 'No result yet';

    _shotPopupType = '';
    _shotPopupSeq = 0;

    _lastUiMs = 0;
    _lastDetectMs = 0;
    _lastWsMs = 0;
    _lastWsParseMs = 0;

    _markDirtyAndNotifySoon();
  }

  // ---------------- WS message parse ----------------
  //
  // WS 回傳的 msg 可能是：
  // - JSON string（Map，含 shot/type/class/speed/message 等欄位）
  // - 純文字（例如 server 直接回傳 "Smash ..."）
  //
  // 解析後做三件事：
  // 1) type -> 更新 swing counters + 觸發 popup seq
  // 2) 更新 lastResultType/speed/message（UI 直接顯示）
  // 3) 設 dirty 等待 UI timer flush（或必要時由其他流程觸發 notify）
  void _onWsMessage(dynamic msg) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastWsParseMs != 0 && (nowMs - _lastWsParseMs) < 100) return;
    _lastWsParseMs = nowMs;

    String? type;
    String? speed;
    String? message;

    final raw = (msg is String) ? msg : msg.toString();
    final s = raw.trimLeft();
    final looksJson = s.isNotEmpty && (s[0] == '{' || s[0] == '[');

    if (looksJson) {
      try {
        final obj = jsonDecode(raw);
        if (obj is Map) {
          type = (obj['shot'] ?? obj['type'] ?? obj['class'])?.toString();
          speed = (obj['speed'] ?? obj['velocity'])?.toString();
          message = (obj['message'] ?? obj['msg'])?.toString();
        } else {
          message = raw;
        }
      } catch (_) {
        message = raw;
      }
    } else {
      message = raw;
      if (raw.contains('Smash')) type = 'Smash';
      else if (raw.contains('Drive')) type = 'Drive';
      else if (raw.contains('Drop')) type = 'Drop';
      else if (raw.contains('Clear')) type = 'Clear';
      else if (raw.contains('Net')) type = 'Net';
    }

    if (type != null) {
      switch (type) {
        case 'Smash':
          smash++;
          break;
        case 'Drive':
          drive++;
          break;
        case 'Drop':
          drop++;
          break;
        case 'Clear':
          clear++;
          break;
        case 'Net':
          net++;
          break;
      }
      _bumpShotPopup(type);
    }

    _setLastResult(type: type, speed: speed, message: message);
    _markDirty();
  }

  // ---- Lifecycle cleanup ----
  //
  // Provider dispose 時釋放所有 subscriptions/timer，避免記憶體洩漏與重複回呼。
  @override
  void dispose() {
    _imuSub?.cancel();
    _wsMsgSub?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }
}
