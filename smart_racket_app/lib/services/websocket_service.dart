import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/imu_frame.dart';

/// compute(...) 只能吃 top-level / static function
/// - 將 payload JSON 序列化抽成 top-level function，便於用 compute() 搬到背景 isolate 執行
String _encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);

enum WsConnState { disconnected, connecting, connected }

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _currentUrl;

  // ---- Incoming message stream (broadcast) ----
  /// 伺服器回傳訊息的統一出口（broadcast），讓多個 listener（Provider/UI/Log）可同時訂閱
  final StreamController<dynamic> _msgCtrl =
  StreamController<dynamic>.broadcast();
  Stream<dynamic> get stream => _msgCtrl.stream;

  // ---- Connection state (3-state) ----
  /// 連線狀態以 3-state 對外發布，UI 可用於顯示 connecting/connected/disconnected
  final StreamController<WsConnState> _stateCtrl =
  StreamController<WsConnState>.broadcast();
  Stream<WsConnState> get stateStream => _stateCtrl.stream;

  WsConnState _state = WsConnState.disconnected;
  WsConnState get state => _state;

  /// 舊版相容：bool stream（Connected=true）
  /// - 保留舊接口，避免其他模組仍依賴 connectionStateStream
  final StreamController<bool> _connCtrl =
  StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connCtrl.stream;

  /// 防止重入與競態：disconnect/close 期間避免再次 send/connect 造成狀態錯亂
  bool _closing = false;

  bool get isConnected =>
      !_closing && _channel != null && _state == WsConnState.connected;

  /// 「可送出」比「已 connected」更寬鬆：connecting 時仍可能允許先排隊
  bool get canSend =>
      !_closing && _channel != null && _state != WsConnState.disconnected;

  // ---- Client identity ----
  /// client_id：讓後端能區分不同裝置/錄製 session（通常會用 Firebase sessionId 覆寫）
  String _clientId = 'SmartRacket';
  void setClientId(String id) {
    final t = id.trim();
    if (t.isNotEmpty) _clientId = t;
  }

  // ---- Outgoing throttled queue ----
  /// 視窗資料採「最新覆蓋」策略：短時間多次 enqueue 只保留最後一包，避免堆積延遲
  List<IMUFrame>? _pendingLatest;
  bool _sending = false;
  Timer? _sendTimer;
  static const Duration _sendInterval = Duration(milliseconds: 100);

  // ---- Optional keepalive ----
  /// 可選 keepalive：避免某些網路/代理在 idle 時切斷 WebSocket
  Timer? _pingTimer;
  static const Duration _keepAlivePingInterval = Duration(seconds: 10);

  Future<void> connect(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;

    // 同 URL 且已連線 -> 不重連（避免重複握手/重複訂閱 stream）
    if (_channel != null && _currentUrl == u && isConnected) return;

    await disconnect();
    _currentUrl = u;

    Uri uri;
    try {
      uri = Uri.parse(u);
    } catch (e) {
      if (kDebugMode) debugPrint('WS invalid url: $u ($e)');
      _setState(WsConnState.disconnected);
      return;
    }

    _closing = false;
    _setState(WsConnState.connecting);

    try {
      // 平台分流：mobile/desktop 走 IOWebSocketChannel；Web 走 WebSocketChannel
      // - IO 端可透過 pingInterval 讓底層維持連線活性
      if (!kIsWeb) {
        _channel = IOWebSocketChannel.connect(
          uri,
          pingInterval: const Duration(seconds: 20),
        );
      } else {
        // Web：缺乏可靠 onOpen callback，建立後先交由 state 管理
        _channel = WebSocketChannel.connect(uri);
      }

      // v2/v3 連線策略：建立 channel 後先視為 connected，後續由 onError/onDone 收斂回 disconnected
      _setState(WsConnState.connected);
    } catch (e) {
      if (kDebugMode) debugPrint('WS connect failed: $e');
      _channel = null;
      _setState(WsConnState.disconnected);
      return;
    }

    // 訂閱 channel stream：統一轉發到 msg stream；錯誤/結束時做清理與狀態回復
    _sub = _channel!.stream.listen(
          (msg) {
        _safeMsg(msg);
      },
      onError: (e) async {
        if (kDebugMode) debugPrint('WS error: $e');
        _setState(WsConnState.disconnected);
        await disconnect();
      },
      onDone: () async {
        _setState(WsConnState.disconnected);
        await disconnect();
      },
      cancelOnError: false,
    );

    // 連上後啟動 keepalive（不要求 pong，純維持活性）
    _armKeepAlivePing();
  }

  /// v2/v3 等級偵測：不要求 pong
  /// - connect 後在 timeout 內觀察是否掉回 disconnected
  /// - 若持續維持非 disconnected，視為「可連」
  Future<bool> probeOnce(
      String url, {
        Duration timeout = const Duration(seconds: 3),
      }) async {
    final u = url.trim();
    if (u.isEmpty) return false;

    await connect(u);

    // connect() 內部若失敗會把 state 設回 disconnected
    if (state == WsConnState.disconnected) return false;

    final completer = Completer<bool>();
    StreamSubscription<WsConnState>? sub;
    Timer? t;

    sub = stateStream.listen((s) {
      if (s == WsConnState.disconnected && !completer.isCompleted) {
        completer.complete(false);
      }
    });

    t = Timer(timeout, () {
      if (completer.isCompleted) return;
      completer.complete(state != WsConnState.disconnected);
    });

    final ok = await completer.future;

    try {
      await sub.cancel();
    } catch (_) {}
    t.cancel();

    return ok;
  }

  // ---- Compatibility ----
  /// 舊 API：保留 sendWindow 但導向新的 enqueueWindow（統一出口）
  void sendWindow(List<IMUFrame> frames) => enqueueWindow(frames);

  // ---- Enqueue & throttle ----
  /// 送出策略：
  /// - 上游可能以高頻率產生 window（事件觸發後連續送），此處做節流與最新覆蓋
  /// - Timer 以固定間隔 pump，確保傳輸頻率可控且避免 sink 被塞爆
  void enqueueWindow(List<IMUFrame> frames) {
    if (!canSend) return;
    if (frames.isEmpty) return;

    _pendingLatest = frames;

    _sendTimer ??= Timer.periodic(_sendInterval, (_) => _pumpSend());
    _pumpSend();
  }

  void _pumpSend() {
    if (!canSend) return;
    if (_sending) return;

    final frames = _pendingLatest;
    if (frames == null || frames.isEmpty) return;

    _pendingLatest = null;

    _sending = true;
    _sendWindowInternal(_clientId, frames).whenComplete(() {
      _sending = false;

      // 若沒有待送資料就停止 timer，避免背景常駐
      if (_pendingLatest == null) {
        _sendTimer?.cancel();
        _sendTimer = null;
      }
    });
  }

  Future<void> _sendWindowInternal(String clientId, List<IMUFrame> frames) async {
    if (!canSend) return;

    // 統一 payload schema：type/window + client_id + data[]
    final payload = <String, dynamic>{
      'type': 'window',
      'client_id': clientId,
      'data': frames.map((f) => f.toJson()).toList(growable: false),
    };

    try {
      // JSON encode 可能耗時，交給 compute() 避免卡住 UI thread
      final encoded = await compute(_encodePayload, payload);
      if (!canSend) return;
      _channel!.sink.add(encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('WS send failed: $e');
    }
  }

  void _armKeepAlivePing() {
    _pingTimer?.cancel();
    _pingTimer = null;

    if (_state != WsConnState.connected) return;

    _pingTimer = Timer.periodic(_keepAlivePingInterval, (_) {
      // 輕量 ping：不要求伺服器回 pong，只是避免連線 idle 被中斷
      if (!canSend) return;
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'ping',
          'client_id': _clientId,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    });
  }

  Future<void> disconnect() async {
    // 關閉流程集中於此：避免重複 close 導致例外或狀態錯亂
    if (_closing) return;
    _closing = true;

    _pingTimer?.cancel();
    _pingTimer = null;

    _sendTimer?.cancel();
    _sendTimer = null;
    _pendingLatest = null;

    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _setState(WsConnState.disconnected);

    _closing = false;
  }

  /// 狀態更新入口：同步推送 3-state 與舊版 bool stream
  void _setState(WsConnState s) {
    if (_state == s) return;
    _state = s;

    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
    if (!_connCtrl.isClosed) _connCtrl.add(s == WsConnState.connected);
  }

  /// 轉發訊息時保護 controller：避免已 close 後仍 add 造成 exception
  void _safeMsg(dynamic msg) {
    if (_msgCtrl.isClosed) return;
    _msgCtrl.add(msg);
  }

  void dispose() {
    // ignore: discarded_futures
    disconnect();
    _msgCtrl.close();
    _stateCtrl.close();
    _connCtrl.close();
  }
}
