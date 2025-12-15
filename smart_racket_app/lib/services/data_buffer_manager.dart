import 'dart:collection';

import '../models/imu_frame.dart';

class DataBufferManager {
  // ---- Windowing / trigger parameters ----
  //
  // DataBufferManager 的職責是把連續 IMUFrame 串流做「條件觸發式視窗擷取」：
  // - _windowSize：每次要送去推論的主要視窗長度（frames）
  // - _preTriggerFrames：觸發點之前要保留的歷史 frames（做前導上下文）
  // - _triggerThresholdG：以加速度向量大小（g）作為觸發門檻
  //
  // 典型行為：每次 addFrame() 進來先進 buffer，當滿足 trigger 條件且不在 cooldown 期間，
  // 回傳一段 window（List<IMUFrame>）；否則回傳 null。
  int _windowSize = 40;
  int _preTriggerFrames = 20;
  double _triggerThresholdG = 2.0;

  // ---- Cooldown control ----
  //
  // 觸發後的冷卻時間：避免一次揮拍或高能量區段在短時間內連續觸發多次。
  // 這裡使用「系統時間」作為 cooldown 判斷基準（wall clock），
  // 不依賴 frame.timestamp（避免 timestamp 不穩、掉包、重置等導致 cooldown 失效或卡住）。
  Duration _coolDownDuration = const Duration(seconds: 1);

  // ✅ 用系統時間做 cooldown（避免 frame.timestamp 不穩造成誤判或卡住）
  int _lastTriggerWallMs = 0;

  // ---- Internal buffer ----
  //
  // 用 ListQueue 當滑動緩衝：高頻 add/removeFirst 成本穩定。
  // buffer 不是無限長，會在 _trimToMaxKeep() 限制最大保留量，避免觸發時 toList 太重。
  final ListQueue<IMUFrame> _buffer = ListQueue<IMUFrame>();

  // ---- Convenience setters ----
  //
  // 對外暴露兩個同義方法（便於上層呼叫習慣一致），最後都走 thresholdG setter 做驗證。
  void setThresholdG(double value) => thresholdG = value;
  void updateThreshold(double value) => thresholdG = value;

  // ---- Threshold validation ----
  //
  // 門檻必須是正數且 finite；無效值直接忽略（保持既有設定），避免 runtime 進入不可預期狀態。
  double get thresholdG => _triggerThresholdG;
  set thresholdG(double v) {
    if (!v.isFinite || v.isNaN || v <= 0) return;
    _triggerThresholdG = v;
  }

  // ---- Read-only accessors for UI / settings ----
  int get windowSize => _windowSize;
  int get preTriggerFrames => _preTriggerFrames;
  Duration get coolDownDuration => _coolDownDuration;

  // ---- Window configuration ----
  //
  // 允許 UI/上層調整 windowSize / preTriggerFrames / cooldown：
  // - windowSize 下限 10（避免太短失去辨識意義）
  // - preTriggerFrames 可為 0（表示不取觸發前）
  // - 若 preTriggerFrames > windowSize，回退成 windowSize/2 的安全值（避免 need 設定失衡）
  // 最後呼叫 _trimToMaxKeep()，確保 buffer 上限跟新設定一致。
  void setWindowConfig({
    int? windowSize,
    int? preTriggerFrames,
    Duration? coolDown,
  }) {
    if (windowSize != null && windowSize >= 10) _windowSize = windowSize;
    if (preTriggerFrames != null && preTriggerFrames >= 0) {
      _preTriggerFrames = preTriggerFrames;
    }
    if (coolDown != null) _coolDownDuration = coolDown;

    if (_preTriggerFrames > _windowSize) {
      _preTriggerFrames = _windowSize ~/ 2;
    }

    _trimToMaxKeep();
  }

  // ---- Streaming entry point ----
  //
  // addFrame() 是資料串流入口：
  // 1) 先做資料健全性檢查（finite/NaN、防止髒資料污染後續判斷）
  // 2) 推入 buffer，並做上限裁剪
  // 3) 用 wall clock 判斷是否仍在 cooldown，若是則不觸發
  // 4) buffer 未滿 windowSize 時不觸發（避免 early trigger）
  // 5) 計算加速度向量平方長度 mag2 與門檻平方 th2，比較避免 sqrt 成本
  // 6) 觸發時更新 _lastTriggerWallMs，並回傳擷取出的 window；否則回 null
  List<IMUFrame>? addFrame(IMUFrame frame) {
    if (!_isFrameFinite(frame)) return null;

    _buffer.addLast(frame);
    _trimToMaxKeep();

    // cooldown（wall clock）
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastTriggerWallMs != 0) {
      final dt = nowMs - _lastTriggerWallMs;
      if (dt < _coolDownDuration.inMilliseconds) return null;
    }

    if (_buffer.length < _windowSize) return null;

    final ax = frame.acc[0];
    final ay = frame.acc[1];
    final az = frame.acc[2];

    // compare squared magnitude (避免 sqrt)
    final mag2 = ax * ax + ay * ay + az * az;
    final th2 = _triggerThresholdG * _triggerThresholdG;

    if (mag2 > th2) {
      _lastTriggerWallMs = nowMs;
      return _extractWindow();
    }
    return null;
  }

  // ---- Window extraction ----
  //
  // 視窗擷取策略：
  // - 需要的總長度 need = preTriggerFrames + windowSize
  // - 直接把 buffer 轉成 list（固定長度），然後取最後 need 筆
  // - 若 buffer 本身不夠長，就回傳全部（合理 fallback）
  //
  // 注意：這裡的 windowSize 概念是「觸發後應該包含的主視窗長度」，
  // 但實作是取最後 need 筆，因此結果 window 會包含 trigger 當下附近的區段。
  List<IMUFrame> _extractWindow() {
    final need = _preTriggerFrames + _windowSize;
    final list = _buffer.toList(growable: false);

    if (list.length <= need) return list;

    return list.sublist(list.length - need);
  }

  // ---- Buffer cap ----
  //
  // buffer 上限設為 (windowSize + preTriggerFrames) * 3：
  // - 讓觸發前後仍有足夠上下文可用
  // - 避免 buffer 太大導致 _extractWindow() 的 toList 成本上升
  void _trimToMaxKeep() {
    // ✅ buffer 上限合理化：太大會讓觸發時 toList 變重
    final maxKeep = (_windowSize + _preTriggerFrames) * 3;
    while (_buffer.length > maxKeep) {
      _buffer.removeFirst();
    }
  }

  // ---- Hard reset ----
  //
  // 清空內部 buffer + 重置 cooldown 計時點，通常用在：
  // - 切換 session / 開始新錄製
  // - 斷線重連後避免舊資料殘留觸發
  void clear() {
    _buffer.clear();
    _lastTriggerWallMs = 0;
  }

  // ---- Data integrity guard ----
  //
  // 只接受 timestamp/acc/gyro/voltage 全部 finite 且非 NaN 的 frame；
  // 同時要求 acc/gyro 必須是 3 維向量（避免上層傳入不完整向量造成 index error）。
  bool _isFrameFinite(IMUFrame f) {
    bool ok3(List<double> a) =>
        a.length == 3 && a.every((v) => v.isFinite && !v.isNaN);

    return f.timestamp.isFinite &&
        !f.timestamp.isNaN &&
        ok3(f.acc) &&
        ok3(f.gyro) &&
        f.voltage.isFinite &&
        !f.voltage.isNaN;
  }
}
