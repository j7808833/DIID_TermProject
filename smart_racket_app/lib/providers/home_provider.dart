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

enum ServerDetectState { idle, detecting, success, failed }

class HomeProvider extends ChangeNotifier {
  BleService? _ble;
  FirebaseService? _firebase;
  WebSocketService? _ws;
  DataBufferManager? _bufferMgr;

  // IMU / WS 訂閱：集中在 provider 層綁定與釋放，避免 UI 重建造成重複 listen
  StreamSubscription<IMUData>? _imuSub;
  StreamSubscription<dynamic>? _wsMsgSub;
  StreamSubscription<WsConnState>? _wsStateSub;

  // 即時資料快取：recentFrames 保留短期視窗供圖表/觸發/除錯；latestData 用於電壓/校正
  final ListQueue<IMUFrame> _recentFrames = ListQueue<IMUFrame>();
  IMUData? latestData;

  IMUFrame? _latestFrame;
  IMUFrame? get latestFrame => _latestFrame;

  double get batteryVoltage {
    // 電壓顯示走防呆：避免 NaN/Inf 影響 UI
    final v = latestData?.voltage;
    if (v == null || !v.isFinite || v.isNaN) return 0.0;
    return v;
  }

  // 對 UI 的「快照輸出」：用 seq 提供輕量版的變更偵測（避免 UI 每筆 IMU 都 rebuild）
  List<IMUFrame> _recentSnapshot = const [];
  int _recentSnapshotSeq = 0;
  List<IMUFrame> get recentFramesSnapshot => _recentSnapshot;
  int get recentFramesSnapshotSeq => _recentSnapshotSeq;

  bool _dirty = false;
  Timer? _uiTimer;

  // 校正用 offset：把當前讀值視為零點，供後續 frame 正規化
  final List<double> _accOffset = [0, 0, 0];
  final List<double> _gyroOffset = [0, 0, 0];
  bool _isCalibrated = false;
  bool get isCalibrated => _isCalibrated;

  // 伺服器分類結果統計（五類球路）
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
    // 重置統計（通常用於新一輪測試或 UI 清除）
    smash = 0;
    drive = 0;
    drop = 0;
    clear = 0;
    net = 0;
    _markDirty();
  }

  // 最近一次推論結果：提供 Stats/Result UI 顯示
  String _lastResultType = '—';
  String _lastResultSpeed = '—';
  String _lastResultMessage = 'No result yet';

  String get lastResultType => _lastResultType;
  String get lastResultSpeed => _lastResultSpeed;
  String get lastResultMessage => _lastResultMessage;

  void _setLastResult({String? type, String? speed, String? message}) {
    // 僅在輸入有效時更新，避免空字串覆蓋既有資訊
    if (type != null && type.trim().isNotEmpty) _lastResultType = type.trim();
    if (speed != null && speed.trim().isNotEmpty) {
      _lastResultSpeed = speed.trim();
    }
    if (message != null && message.trim().isNotEmpty) {
      _lastResultMessage = message.trim();
    }
  }

  // Shot popup：以序號驅動一次性提示（UI 監聽 seq 變動即可觸發）
  int _shotPopupSeq = 0;
  String _shotPopupType = '';
  int get shotPopupSeq => _shotPopupSeq;
  String get shotPopupType => _shotPopupType;

  void _bumpShotPopup(String type) {
    _shotPopupType = type;
    _shotPopupSeq++;
  }

  // 觸發靈敏度與伺服器位置（由 UI 設定頁寫入）
  double _sensitivity = 2.0;
  String _serverIp = '';

  double get sensitivity => _sensitivity;
  String get serverIp => _serverIp;

  // ===== WS connection state (3-state, from service) =====
  // WebSocketService 對外的連線狀態映射到 UI 狀態，供按鈕/提示使用
  WsConnState _wsStateUi = WsConnState.disconnected;
  WsConnState get wsState => _wsStateUi;
  bool get wsConnected => _wsStateUi == WsConnState.connected;

  String _lastWsUrl = '';
  String get lastWsUrl => _lastWsUrl;

  // ===== v2/v3 等級的偵測 UI =====
  // 採「探測一次」的 UX：用於快速判斷 URL 是否可連線，不要求 server 實作 pong
  ServerDetectState _serverDetectState = ServerDetectState.idle;
  ServerDetectState get serverDetectState => _serverDetectState;

  String _serverDetectMessage = '—';
  String get serverDetectMessage => _serverDetectMessage;

  int _serverDetectSeq = 0;
  int get serverDetectSeq => _serverDetectSeq;

  bool get serverDetectOk => _serverDetectState == ServerDetectState.success;

  bool get serverDetectBusy => _serverDetectState == ServerDetectState.detecting;

  int _nextDetectAllowedMs = 0; // 偵測冷卻：避免短時間重複 probe

  // ===== BLE UI =====
  bool get isConnected => _ble?.isConnected ?? false;

  String get connectionStatus {
    // BLE 連線狀態轉為 UI 文案
    final s = _ble?.lastConnState;
    if (s == null) return '';
    final n = s.name;
    if (n == 'connected') return 'Connected';
    if (n == 'disconnected') return 'Disconnected';
    if (n == 'connecting') return 'Connecting...';
    if (n == 'disconnecting') return 'Disconnecting...';
    return n;
  }

  // ===== record UI =====
  // provider 層維護錄製狀態，避免 UI 層做過多流程控制
  bool _isRecordingUi = false;
  bool _isPausedUi = false;
  bool _recordOpBusy = false;

  bool get isRecording => _isRecordingUi;
  bool get isPaused => _isPausedUi;

  // Firebase session 狀態與上傳統計（供 RecordPage 顯示）
  String? get currentSessionId => _firebase?.sessionId;
  int get uploadedCount => _firebase?.uploadedCount ?? 0;
  int get pendingCount => _firebase?.pendingCount ?? 0;

  HomeProvider();

  // 節流用時間戳：UI/觸發/WS/解析各自獨立節奏
  int _lastUiMs = 0;
  int _lastDetectMs = 0;
  int _lastWsMs = 0;
  int _lastWsParseMs = 0;

  void _markDirty() => _dirty = true;

  void _markDirtyAndNotifySoon() {
    // 需要立刻反映在 UI 的狀態，直接通知（例如連線狀態/按鈕狀態）
    _markDirty();
    notifyListeners();
  }

  void updateDeps({
    required BleService ble,
    required FirebaseService firebase,
    required WebSocketService ws,
    required DataBufferManager bufferMgr,
  }) {
    // 由 ProxyProvider 注入依賴：變更時重綁 streams，避免舊訂閱殘留
    final changed =
        _ble != ble || _firebase != firebase || _ws != ws || _bufferMgr != bufferMgr;

    _ble = ble;
    _firebase = firebase;
    _ws = ws;
    _bufferMgr = bufferMgr;

    if (changed) _bindStreams();

    // service 切換後，若有 serverIp 且 URL 不同，做一次探測（受冷卻限制）
    final url = _toWsUrl(_serverIp);
    if (url.isNotEmpty && url != _lastWsUrl) {
      // ignore: discarded_futures
      detectServerOnce();
    }
  }

  void _bindStreams() {
    // 重綁前先清掉舊訂閱與 timer，避免資源洩漏與重複事件
    _imuSub?.cancel();
    _wsMsgSub?.cancel();
    _wsStateSub?.cancel();
    _uiTimer?.cancel();

    // UI 更新節奏：集中把 dirty 狀態轉成 snapshot + notify，降低 rebuild 頻率
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

      // WS 連線狀態由 service 驅動，轉成 UI 狀態（按鈕/提示）
      _wsStateSub = ws.stateStream.listen((s) {
        _wsStateUi = s;
        _markDirtyAndNotifySoon();
      });
    }
  }

  Future<void> startScan() async {
    // 走 BleService 掃描/自動連線流程，UI 只需觸發此入口
    await _ble?.startScan(autoConnect: true);
    _markDirtyAndNotifySoon();
  }

  Future<void> disconnectBle() async {
    // 主動中斷 BLE
    await _ble?.disconnect();
    _markDirtyAndNotifySoon();
  }

  void updateSettings(double sensitivity, String ip) {
    // UI 設定入口：更新觸發門檻與伺服器位置，並做一次探測
    _sensitivity = sensitivity;
    _serverIp = ip.trim();

    setTriggerThreshold(_sensitivity);

    // ✅ v2/v3 等級：設定後做一次「3 秒偵測」
    // ignore: discarded_futures
    detectServerOnce();

    _markDirtyAndNotifySoon();
  }

  /// ===== v2/v3 等級偵測：3 秒內只做一次；不要求 pong =====
  Future<void> detectServerOnce() async {
    // 防連點：短時間不重複做 probe
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _nextDetectAllowedMs) return;
    _nextDetectAllowedMs = now + 3000;

    final url = _toWsUrl(_serverIp);
    _lastWsUrl = url;

    if (url.isEmpty) {
      _serverDetectState = ServerDetectState.failed;
      _serverDetectMessage = 'Detection failed';
      _serverDetectSeq++;
      _markDirtyAndNotifySoon();
      return;
    }

    _serverDetectState = ServerDetectState.detecting;
    _serverDetectMessage = 'Detecting...';
    _markDirtyAndNotifySoon();

    // probeOnce 只做「能否建立連線」的判斷；成功不代表推論 API 一定可用，但可排除網址/網路基本問題
    bool ok = false;
    try {
      ok = await _ws?.probeOnce(url, timeout: const Duration(seconds: 3)) ?? false;
    } catch (_) {
      ok = false;
    }

    if (ok) {
      _serverDetectState = ServerDetectState.success;
      _serverDetectMessage = 'Detection succeeded';
    } else {
      _serverDetectState = ServerDetectState.failed;
      _serverDetectMessage = 'Detection failed';
    }

    _serverDetectSeq++;
    _markDirtyAndNotifySoon();
  }

  /// ✅ 預設 ws://；若你要 wss 就在輸入直接填 wss://
  String _toWsUrl(String input) {
    // 將常見輸入（ip/domain/http(s)）轉成 WebSocket URL
    final s = input.trim();
    if (s.isEmpty) return '';

    if (s.startsWith('ws://') || s.startsWith('wss://')) return s;
    if (s.startsWith('http://')) return 'ws://${s.substring('http://'.length)}';
    if (s.startsWith('https://')) return 'wss://${s.substring('https://'.length)}';

    return 'ws://$s';
  }

  void _onImuData(IMUData d) {
    // BLE → 最新 raw data；後續轉 frame、觸發視窗、推送 WS、以及（若錄製）寫入 Firebase
    latestData = d;

    if (_isRecordingUi && !_isPausedUi) {
      _firebase?.addData(d);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 事件節流：避免過高頻率造成 provider 層負載
    if (_lastDetectMs != 0 && (nowMs - _lastDetectMs) < 10) return;
    _lastDetectMs = nowMs;

    // raw → frame（套 offset + 數值防呆），統一資料格式供下游模組使用
    final f = IMUFrame.fromIMUData(
      d,
      accOffset: _accOffset,
      gyroOffset: _gyroOffset,
    );
    _latestFrame = f;

    // 觸發判定：DataBufferManager 回傳一段視窗資料（pre-trigger + window）
    final seg = _bufferMgr?.addFrame(f);
    if (seg != null && seg.isNotEmpty) {
      // 視窗推送節流：避免連續觸發造成 WS 洪水
      if (_lastWsMs == 0 || (nowMs - _lastWsMs) >= 200) {
        _lastWsMs = nowMs;

        final ws = _ws;
        if (ws != null) {
          // 兼容不同 WS service 介面：優先 queue，再 fallback 直接送
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

    // 圖表/UI 緩衝：維持固定長度的 recentFrames，供即時曲線與除錯檢視
    if (_lastUiMs == 0 || (nowMs - _lastUiMs) >= 20) {
      _lastUiMs = nowMs;

      _recentFrames.addLast(f);
      while (_recentFrames.length > 220) {
        _recentFrames.removeFirst();
      }
      _markDirty();
    }
  }

  Future<void> startCalibration() async => calibrateOffsets();

  void calibrateOffsets() {
    // 以當前姿態作為零點：後續 frame 會扣掉 offset（常用於手持靜止校正）
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

  void setTriggerThreshold(double g) {
    // 將 UI 靈敏度映射到觸發門檻（g），由 DataBufferManager 負責判定
    _bufferMgr?.updateThreshold(g);
    _markDirtyAndNotifySoon();
  }

  Future<void> startRecord({String deviceId = 'SmartRacket'}) async {
    // UI 封裝入口
    await startRecording(deviceId: deviceId);
  }

  Future<void> stopRecord({String? label}) async {
    // UI 封裝入口
    await stopRecording(label: label);
  }

  Future<void> pauseRecord() async {
    // UI 封裝入口
    await pauseRecording();
  }

  Future<void> resumeRecord() async {
    // UI 封裝入口
    await resumeRecording();
  }

  Future<void> startRecording({String deviceId = 'SmartRacket'}) async {
    // 錄製 session：初始化 Firebase session，並將 sessionId（若可用）同步給 WS 當 client_id
    if (_recordOpBusy) return;
    if (_isRecordingUi) return;
    if (!isConnected) return;

    _recordOpBusy = true;
    try {
      await _firebase?.startSession(deviceId: deviceId, sampleRate: 100);

      final sid = _firebase?.sessionId;
      if (sid != null) {
        try {
          (_ws as dynamic).setClientId(sid);
        } catch (_) {}
      }

      _isRecordingUi = true;
      _isPausedUi = false;

      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  Future<void> pauseRecording() async {
    // 暫停只影響 app 端是否寫入資料（BLE/WS 仍可繼續）
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;
    if (_isPausedUi) return;

    _recordOpBusy = true;
    try {
      _isPausedUi = true;
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  Future<void> resumeRecording() async {
    // 恢復寫入
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;
    if (!_isPausedUi) return;

    _recordOpBusy = true;
    try {
      _isPausedUi = false;
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  Future<void> stopRecording({String? label}) async {
    // 結束 session：先更新 UI 狀態，再收尾寫入（flush + metadata）
    if (_recordOpBusy) return;
    if (!_isRecordingUi) return;

    _recordOpBusy = true;
    try {
      _isRecordingUi = false;
      _isPausedUi = false;
      _markDirtyAndNotifySoon();

      await _firebase?.endSession(label: label);
      _markDirtyAndNotifySoon();
    } finally {
      _recordOpBusy = false;
    }
  }

  Future<void> clearRecord() async {
    // 一鍵清空：包含 session、中介緩衝、UI 狀態、結果與 popup 等，回到乾淨狀態
    _isRecordingUi = false;
    _isPausedUi = false;
    _markDirtyAndNotifySoon();

    await _firebase?.cancelSession();

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

    _serverDetectState = ServerDetectState.idle;
    _serverDetectMessage = '—';
    _serverDetectSeq++;

    _markDirtyAndNotifySoon();
  }

  void _onWsMessage(dynamic msg) {
    // 解析伺服器回傳：支援 JSON / 純字串；並對 shot/type 欄位做多鍵相容
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
          // ping/pong 僅作為 keepalive，不更新 UI 結果
          final t = obj['type']?.toString();
          if (t == 'pong' || t == 'ping') {
            _markDirty();
            return;
          }

          // 欄位相容：允許不同後端回傳 key 命名
          type = (obj['shot'] ??
              obj['type_shot'] ??
              obj['shot_type'] ??
              obj['shotType'] ??
              obj['type'] ??
              obj['class'])
              ?.toString();
          speed = (obj['speed'] ?? obj['velocity'])?.toString();
          message = (obj['message'] ?? obj['msg'])?.toString();
        } else {
          message = raw;
        }
      } catch (_) {
        message = raw;
      }
    } else {
      // 非 JSON：以關鍵字猜測球路，並保留原字串作為訊息
      message = raw;
      if (raw.contains('Smash')) type = 'Smash';
      else if (raw.contains('Drive')) type = 'Drive';
      else if (raw.contains('Drop')) type = 'Drop';
      else if (raw.contains('Clear')) type = 'Clear';
      else if (raw.contains('Net')) type = 'Net';
    }

    // 有分類結果就更新統計並觸發 popup
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

  @override
  void dispose() {
    // provider 銷毀時釋放所有訂閱與 timer
    _imuSub?.cancel();
    _wsMsgSub?.cancel();
    _wsStateSub?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }
}
