import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

import '../models/imu_data.dart';

class FirebaseService {
  // ---- Core wiring ----
  //
  // 本服務是「錄製/上傳管線」：把 IMUData 以 session 為單位寫入 Firebase Realtime Database。
  // - db 可注入（測試/多環境），預設用 FirebaseDatabase.instance
  // - sessionId 是目前錄製中的 session key（短 id，方便 debug）
  // - uploadedCount/pendingCount 提供 UI 顯示當前上傳進度/積壓量
  final FirebaseDatabase db;
  final _uuid = const Uuid();

  FirebaseService({FirebaseDatabase? database})
      : db = database ?? FirebaseDatabase.instance;

  DatabaseReference get _root => db.ref();

  String? sessionId;
  bool get hasSession => sessionId != null;

  int uploadedCount = 0;
  int pendingCount = 0;

  // ===== record state =====
  //
  // 暫停狀態：只控制「addData 是否接受資料」；
  // 真正的 pause/resume 也會同步更新 metadata（status/paused/時間戳）。
  bool _paused = false;
  bool get isPaused => _paused;

  // ===== buffer/flush =====
  //
  // 採「批次緩衝 + 定時 flush」策略：
  // - bufferSize：累積到此數量就主動觸發 flush（降低延遲）
  // - bufferHardLimit：保護上限，避免網路長時間失敗導致記憶體爆掉
  // - flushInterval：定時 flush（即使未達 bufferSize，也能持續把資料推上去）
  static const int bufferSize = 80;
  static const int bufferHardLimit = 600;
  static const Duration flushInterval = Duration(milliseconds: 500);

  final List<IMUData> _buffer = [];
  bool _flushing = false;
  Timer? _timer;

  // ===== debug =====
  //
  // 用於現場觀測錄製管線健康度（非核心邏輯）：
  // - add/flush 次數、成功次數
  // - 最近一次 add/flush/flushOk 的時間戳（ms）
  // - 最近一次 flush error 字串（便於 UI/console 顯示）
  int addCalls = 0;
  int flushCalls = 0;
  int flushOkCalls = 0;

  int? lastAddAtMs;
  int? lastFlushAtMs;
  int? lastFlushOkAtMs;
  String lastFlushError = '';

  // ---- Session lifecycle: start ----
  //
  // startSession 做的事：
  // 1) 先 cancelSession() 確保乾淨狀態（避免殘留 timer/buffer）
  // 2) 產生短 sessionId（8 字元）並重置 counters/buffer/paused/debug
  // 3) 寫入 sessions/{sid}/metadata（created_at/device_id/sample_rate/status/paused）
  // 4) 啟動 periodic flush timer（flush 本身保證不 rethrow）
  //
  // 若 metadata set() 在這裡就失敗，等同「錄製根本沒開始」：上層 UI 也不應進入 recording 狀態。
  Future<void> startSession({
    String deviceId = 'unknown',
    int sampleRate = 100,
  }) async {
    await cancelSession();

    sessionId = _uuid.v4().replaceAll('-', '').substring(0, 8);
    uploadedCount = 0;
    pendingCount = 0;
    _buffer.clear();

    _paused = false;

    addCalls = 0;
    flushCalls = 0;
    flushOkCalls = 0;
    lastAddAtMs = null;
    lastFlushAtMs = null;
    lastFlushOkAtMs = null;
    lastFlushError = '';

    final sid = sessionId!;
    final meta = {
      'created_at': ServerValue.timestamp,
      'device_id': deviceId,
      'sample_rate': sampleRate,
      'status': 'recording',
      'paused': false,
    };

    // 如果這裡會 throw，你的 UI 其實應該進不了 recording
    await _root.child('sessions/$sid/metadata').set(meta);

    _timer?.cancel();
    _timer = Timer.periodic(flushInterval, (_) async {
      try {
        await flush();
      } catch (e) {
        // flush 永遠不應該 rethrow，但多一道保護
        lastFlushError = e.toString();
      }
    });
  }

  // ---- Streaming input: addData ----
  //
  // addData 是錄製期間的高頻入口：
  // - 無 session 或 paused 時直接丟棄（避免寫到錯誤路徑/破壞狀態）
  // - hard limit：超過 bufferHardLimit 就從最舊的開始丟（保護記憶體；偏保守策略）
  // - 更新 pendingCount 供 UI 顯示
  // - bufferSize 達標時觸發 flush（非 await，避免阻塞 caller / UI thread）
  void addData(IMUData d) {
    final sid = sessionId;
    if (sid == null) return;
    if (_paused) return;

    addCalls++;
    lastAddAtMs = DateTime.now().millisecondsSinceEpoch;

    if (_buffer.length >= bufferHardLimit) {
      final dropN = (_buffer.length - bufferHardLimit) + 1;
      _buffer.removeRange(0, dropN.clamp(0, _buffer.length));
    }

    _buffer.add(d);
    pendingCount = _buffer.length;

    if (_buffer.length >= bufferSize) {
      // ignore: discarded_futures
      flush();
    }
  }

  // ---- Session state: pause ----
  //
  // pauseSession 的語意是「停止接受新資料」並盡可能把 buffer 送出：
  // - 先標記 _paused
  // - pause 前先 flush 一次（最大化資料落庫）
  // - 更新 metadata：status/paused/paused_at（失敗也不阻斷流程）
  Future<void> pauseSession() async {
    final sid = sessionId;
    if (sid == null) return;
    if (_paused) return;

    _paused = true;

    // 暫停前先 flush 一次（盡量把 buffer 送出去）
    await flush();

    try {
      await _root.child('sessions/$sid/metadata').update({
        'status': 'paused',
        'paused': true,
        'paused_at': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  // ---- Session state: resume ----
  //
  // resumeSession：恢復接受資料，並把狀態寫回 metadata（同樣不強制成功）。
  Future<void> resumeSession() async {
    final sid = sessionId;
    if (sid == null) return;
    if (!_paused) return;

    _paused = false;

    try {
      await _root.child('sessions/$sid/metadata').update({
        'status': 'recording',
        'paused': false,
        'resumed_at': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// 重要：Realtime DB 不接受 NaN/Infinity
  //
  // sanitize 的目的：Firebase Realtime Database 對 NaN/Infinity 會拒收（write 直接 fail）。
  // 這裡做遞迴清洗：
  // - double NaN/Inf -> 0.0（保守替代，確保資料能落庫）
  // - List/Map 會遞迴處理所有元素
  Object? _sanitizeValue(Object? v) {
    if (v is num) {
      if (v is double) {
        if (v.isNaN || !v.isFinite) return 0.0;
      }
      return v;
    }
    if (v is List) {
      return v.map(_sanitizeValue).toList();
    }
    if (v is Map) {
      final out = <String, Object?>{};
      for (final e in v.entries) {
        out[e.key.toString()] = _sanitizeValue(e.value);
      }
      return out;
    }
    return v;
  }

  Map<String, Object?> _sanitizeMap(Map<String, dynamic> m) {
    final out = <String, Object?>{};
    for (final e in m.entries) {
      out[e.key] = _sanitizeValue(e.value);
    }
    return out;
  }

  /// ✅ flush 永遠不 rethrow（避免把 Timer/UI 打爆）
  //
  // flush 的目標：把目前 buffer 的資料以「一次 update 多筆」的方式寫到 raw_data：
  // - _flushing 互斥：避免並發 flush 造成競態（尤其 addData 的閾值觸發 + timer 同時來）
  // - toSend：把 buffer snapshot 下來並清空，先讓 pendingCount 歸零（UI 看起來立即回落）
  // - updates：組成 sessions/{sid}/raw_data/{uuid} -> sanitized JSON
  // - 成功：uploadedCount += toSend.length，並 optional 更新 metadata heartbeat（last_upload_at/uploaded）
  // - 失敗：把資料塞回 buffer（保守），但不 throw
  Future<void> flush() async {
    if (_flushing) return;

    final sid = sessionId;
    if (sid == null) return;
    if (_buffer.isEmpty) return;

    _flushing = true;
    flushCalls++;
    lastFlushAtMs = DateTime.now().millisecondsSinceEpoch;

    final toSend = List<IMUData>.from(_buffer);
    _buffer.clear();
    pendingCount = 0;

    final updates = <String, Object?>{};
    for (final d in toSend) {
      final id = _uuid.v4().replaceAll('-', '');
      final raw = d.toJson(); // 你原本的模型輸出
      updates['sessions/$sid/raw_data/$id'] = _sanitizeMap(Map<String, dynamic>.from(raw));
    }

    try {
      await _root.update(updates);
      uploadedCount += toSend.length;

      flushOkCalls++;
      lastFlushOkAtMs = DateTime.now().millisecondsSinceEpoch;
      lastFlushError = '';

      // optional: 在 metadata 留一個 heartbeat，方便你在 console 看是否有在寫
      try {
        await _root.child('sessions/$sid/metadata').update({
          'last_upload_at': ServerValue.timestamp,
          'uploaded': uploadedCount,
        });
      } catch (_) {}
    } catch (e) {
      lastFlushError = e.toString();

      // 失敗：塞回去（保守），但不 throw
      _buffer.insertAll(0, toSend);
      pendingCount = _buffer.length;
    } finally {
      _flushing = false;
    }
  }

  // ---- Session lifecycle: end ----
  //
  // endSession 的語意是「結束一個 session（寫 completed + flush 收尾）」
  // - 先停 timer，避免結束過程中又被 timer 觸發 flush
  // - 最後 flush：做有限次重試（6 次，每次間隔 120ms），避免 transient failure 導致大量遺失
  // - 更新 metadata：status=completed、ended_at、total_samples、paused=false，並可選 label
  // - 清空本地 session 狀態（sessionId=null、buffer 清空、pending=0、paused=false）
  Future<void> endSession({String? label}) async {
    final sid = sessionId;
    if (sid == null) return;

    _timer?.cancel();
    _timer = null;

    // 最後 flush：有限次重試
    for (int i = 0; i < 6; i++) {
      await flush();
      if (_buffer.isEmpty && !_flushing) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final metaUpdate = <String, Object?>{
      'status': 'completed',
      'ended_at': ServerValue.timestamp,
      'total_samples': uploadedCount,
      'paused': false,
    };
    if (label != null && label.isNotEmpty) {
      metaUpdate['label'] = label;
    }

    await _root.child('sessions/$sid/metadata').update(metaUpdate);

    sessionId = null;
    _buffer.clear();
    pendingCount = 0;
    _paused = false;
  }

  // ---- Session lifecycle: cancel ----
  //
  // cancelSession 的語意是「放棄本次 session（連同 DB 上資料一起刪掉）」：
  // - 停 timer、清本地狀態與 counters
  // - 若之前有 sid，嘗試 remove sessions/{sid}（失敗不拋出）
  //
  // 用途：使用者按下取消、或 startSession 前先清掉任何殘留 session。
  Future<void> cancelSession() async {
    _timer?.cancel();
    _timer = null;

    final sid = sessionId;
    sessionId = null;

    _buffer.clear();
    uploadedCount = 0;
    pendingCount = 0;
    _flushing = false;
    _paused = false;

    if (sid != null) {
      try {
        await _root.child('sessions/$sid').remove();
      } catch (_) {}
    }
  }

  // ---- Manual cleanup ----
  //
  // 這個 dispose() 只負責停止 timer；實際 DB/stream 沒有長連線資源要關閉。
  // 若要更一致，也可改成 implements Disposable pattern，但目前專案以 Provider 管理生命週期即可。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
