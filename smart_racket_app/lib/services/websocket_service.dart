import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/imu_frame.dart';

/// ✅ JSON encode 放到 background isolate（compute 需要 top-level function）
///
/// compute(...) 只能吃 top-level / static function，因此把 jsonEncode 包成一個純函式。
/// 目的：把「payload → JSON string」這個可能偏重的 CPU 工作移出 UI isolate，避免 jank。
String _encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);

class WebSocketService {
  // ---- Connection primitives ----
  //
  // - _channel: web_socket_channel 提供的連線與 sink
  // - _sub: 訂閱 server message 的 stream subscription
  // - _currentUrl: 去重連線用（同 URL 且 still connected 就不重連）
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _currentUrl;

  // ---- Incoming message stream ----
  //
  // UI / Provider 透過 stream 收到 server 回傳（分類結果、速度、訊息等）。
  // broadcast 允許多方訂閱（例如 debug page + home provider 同時 listen）。
  final StreamController<dynamic> _msgCtrl =
  StreamController<dynamic>.broadcast();
  Stream<dynamic> get stream => _msgCtrl.stream;

  // ---- Connection state stream ----
  //
  // 對外提供簡化後的連線狀態（bool），避免 UI 需要依賴底層 socket 狀態細節。
  // 這裡的 connected 定義是：成功收到第一個訊息後才標記為 true（見 connect() 的 listen）。
  final StreamController<bool> _connCtrl =
  StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connCtrl.stream;

  bool _connected = false;
  bool get isConnected => _connected && _channel != null;

  // ---- Client identity ----
  //
  // client_id 會包在每次 outgoing payload 內，讓 server 能識別來源（例如對應 sessionId）。
  // HomeProvider 會在 startRecording 後把 Firebase sessionId 注入進來（若可用）。
  String _clientId = 'SmartRacket';
  void setClientId(String id) {
    final t = id.trim();
    if (t.isNotEmpty) _clientId = t;
  }

  // ===== Outgoing throttled queue =====
  //
  // 本服務的 outgoing 策略是「只保留最新的一窗」：
  // - _pendingLatest: 最新 window（List<IMUFrame>）
  // - _sending: 避免同時送出多次（互斥）
  // - _sendTimer: 節流用的 periodic timer
  //
  // 目標：避免 backlog 堆積（例如感測資料產生速度 > 網路/Server 處理速度），
  // 讓系統保持「近即時」而不是「延遲越來越大」。
  List<IMUFrame>? _pendingLatest;
  bool _sending = false;
  Timer? _sendTimer;

  // 送出節流：最多 10Hz（可自行調整）
  //
  // enqueueWindow 可能被高頻呼叫（由 DataBufferManager 觸發），
  // 因此用 100ms 節流確保「最多 10 次/秒」送到 server，避免頻寬與 encode 成本失控。
  static const Duration _sendInterval = Duration(milliseconds: 100);

  // disconnect 重入保護：避免 onError/onDone 同時觸發多次 disconnect() 造成競態。
  bool _closing = false;

  // ---- Connect ----
  //
  // connect 流程：
  // 1) sanitize url（trim/empty）
  // 2) 同 URL 且 still connected → 直接 return（去重）
  // 3) disconnect() 清乾淨，再建立新 channel
  // 4) 先把 _connected 設 false，等待收到第一則 server message 才視為連線成立
  // 5) 訂閱 _channel.stream：
  //    - onData：第一次收到訊息時標記 connected=true（並推送 connection state）
  //    - onError/onDone：標記 disconnected，並做完整 disconnect 清理
  Future<void> connect(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;

    if (_channel != null && _currentUrl == u && isConnected) return;

    await disconnect();
    _currentUrl = u;

    final uri = Uri.parse(u);
    _channel = WebSocketChannel.connect(uri);

    _connected = false;
    _safeConn(false);

    _sub = _channel!.stream.listen(
          (msg) {
        if (!_connected) {
          _connected = true;
          _safeConn(true);
        }
        _safeMsg(msg);
      },
      onError: (e) async {
        if (kDebugMode) debugPrint('WS error: $e');
        _connected = false;
        _safeConn(false);
        await disconnect();
      },
      onDone: () async {
        _connected = false;
        _safeConn(false);
        await disconnect();
      },
      cancelOnError: false,
    );
  }

  /// 舊版相容：HomeProvider 直接丟 frames 進來即可
  /// ✅ 只保留最新一窗 + 節流送出
  ///
  // enqueueWindow 是 HomeProvider 的主要呼叫入口（相容舊版 sendWindow/queue 的語意）。
  // 行為：
  // - 若未連線或 frames 空 → 忽略
  // - 覆蓋 pending（只保留最新窗）
  // - 若 timer 尚未啟動 → 啟動 periodic pump
  // - 立即 pump 一次，降低延遲（不必等到下一個 tick）
  void enqueueWindow(List<IMUFrame> frames) {
    if (!isConnected) return;
    if (frames.isEmpty) return;

    // 只保留最新窗（覆蓋舊的）
    _pendingLatest = frames;

    // 啟動節流 timer（若尚未啟動）
    _sendTimer ??= Timer.periodic(_sendInterval, (_) {
      _pumpSend();
    });

    // 立即嘗試送一次（不等下一個 tick）
    _pumpSend();
  }

  // ---- Send pump ----
  //
  // pumpSend 是節流器的核心：
  // - 互斥：_sending=true 時不重入
  // - 把 pendingLatest 取出並清空（避免同一窗被重複送出；新窗會覆蓋進來）
  // - whenComplete 後若沒有 pending，就停掉 timer（避免常駐喚醒）
  void _pumpSend() {
    if (!isConnected) return;
    if (_sending) return;

    final frames = _pendingLatest;
    if (frames == null || frames.isEmpty) return;

    // 把 pending 清掉（新窗會再覆蓋）
    _pendingLatest = null;

    _sending = true;
    _sendWindowInternal(_clientId, frames).whenComplete(() {
      _sending = false;

      // 沒有 pending 了 -> 停掉 timer，避免常駐喚醒
      if (_pendingLatest == null) {
        _sendTimer?.cancel();
        _sendTimer = null;
      }
    });
  }

  // ---- Internal send ----
  //
  // _sendWindowInternal 做兩件事：
  // 1) 以 client_id + frames.toJson() 建出 payload Map（此步驟相對輕）
  // 2) 用 compute 在 background isolate jsonEncode（主要重點：避免卡 UI）
  // 成功後 _channel.sink.add(encoded) 送出；失敗只記 log、不 throw（避免 Timer/UI 被 exception 撕裂）。
  Future<void> _sendWindowInternal(String clientId, List<IMUFrame> frames) async {
    if (!isConnected) return;

    // 建 payload（只是一個 Map，真正重的是 jsonEncode）
    final payload = <String, dynamic>{
      'client_id': clientId,
      'data': frames.map((f) => f.toJson()).toList(growable: false),
    };

    try {
      // ✅ 背景 isolate 做 JSON encode（避免卡 UI）
      final encoded = await compute(_encodePayload, payload);
      if (!isConnected) return;
      _channel!.sink.add(encoded);
    } catch (e) {
      // 送出失敗：不要 throw，避免把 UI/Timer 拉垮
      if (kDebugMode) debugPrint('WS send failed: $e');
    }
  }

  // ---- Disconnect ----
  //
  // disconnect 需要是「可安全重入」：
  // - _closing guard 避免多路徑（手動呼叫、onError、onDone）同時進來
  // - 停 timer / 清 pending
  // - cancel message subscription
  // - 關閉 sink（close websocket）
  // - 重置狀態並推送 conn=false
  Future<void> disconnect() async {
    if (_closing) return;
    _closing = true;

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
    _connected = false;
    _safeConn(false);

    _closing = false;
  }

  // ---- Safe emit helpers ----
  //
  // StreamController 關閉後 add 會 throw，因此以 isClosed guard 保護。
  // 這兩個 helper 讓 connect/disconnect 路徑更乾淨（不必到處 try-catch）。
  void _safeMsg(dynamic msg) {
    if (_msgCtrl.isClosed) return;
    _msgCtrl.add(msg);
  }

  void _safeConn(bool v) {
    if (_connCtrl.isClosed) return;
    _connCtrl.add(v);
  }

  // ---- Manual cleanup ----
  //
  // Provider/上層結束生命週期時呼叫：
  // - 先 async disconnect（不 await，避免阻塞 dispose 呼叫端）
  // - 關閉 controllers（停止對外 broadcast）
  void dispose() {
    // ignore: discarded_futures
    disconnect();
    _msgCtrl.close();
    _connCtrl.close();
  }
}
