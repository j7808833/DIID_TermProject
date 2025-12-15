import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';

/// AppBar 右上角的「校正」入口按鈕：點擊後開啟校正對話框
class CalibrationAction extends StatelessWidget {
  const CalibrationAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Calibrate', // 滑鼠懸停提示文字
      icon: const Icon(Icons.refresh), // 以 refresh 圖示表示校正/重置
      onPressed: () {
        HapticFeedback.selectionClick(); // 觸覺回饋：點一下的手感
        showDialog(
          context: context,
          barrierDismissible: true, // 點背景可關閉
          builder: (_) => const _CalibrationDialog(), // 對話框主體
        );
      },
    );
  }
}

/// 校正對話框（Stateful）：
/// - 進入時記錄 Base gyro（當下值）
/// - 以 Timer 定期刷新 Live gyro（即時值）
/// - 提供「Reset offsets」與「Calibrate」兩個動作（best-effort 兼容多版本 provider）
class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog();

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  // ===== 視覺常數：統一色彩與風格（與整個 App 一致）=====
  static const accent = Colors.greenAccent;
  static const greenDark = Color(0xFF166534);
  static const greenDarker = Color(0xFF064E3B);
  static const border = Color(0xFFE5E7EB);
  static const textGrey = Color(0xFF374151);

  // 週期更新用 Timer：每 250ms 抓一次最新 gyro 來顯示
  Timer? _tick;

  // 避免重複點擊/重入：按鈕忙碌中就 disable
  bool _busy = false;

  // 操作回饋文字：成功/失敗提示
  String _hint = '';

  // Base gyro：打開對話框那一刻的陀螺儀 XYZ（當作參考基準）
  List<double?> _baseGyro = const [null, null, null];

  // Live gyro：對話框顯示中的最新陀螺儀 XYZ（即時更新）
  List<double?> _liveGyro = const [null, null, null];

  @override
  void initState() {
    super.initState();

    // 以「打開彈窗那瞬間」為 Base：讀一次 provider 的當前 gyro
    final p = context.read<HomeProvider>();
    _baseGyro = _readGyroFromProvider(p);
    _liveGyro = _baseGyro;

    // 每 250ms 更新一次 Live gyro（避免用高頻 setState 造成 UI 負擔）
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return; // Widget 已被移除就不要更新
      final p2 = context.read<HomeProvider>();
      final g = _readGyroFromProvider(p2);
      setState(() => _liveGyro = g);
    });
  }

  @override
  void dispose() {
    _tick?.cancel(); // 關閉對話框時停止 Timer，避免資源/記憶體洩漏
    super.dispose();
  }

  // -------------------------
  // 從 HomeProvider 讀取陀螺儀資料（Robust / best-effort）
  // 目的：兼容不同版本的 provider 欄位命名與資料型態
  // -------------------------
  List<double?> _readGyroFromProvider(HomeProvider p) {
    dynamic sample; // 用 dynamic 接住「可能是 IMUData / IMUFrame / 自訂結構」

    // 1) 優先嘗試常見的「最新資料」欄位（last/latest/current）
    //    逐一試看看哪個存在且有值
    for (final getter in <dynamic Function()>[
          () => (p as dynamic).lastImuData,
          () => (p as dynamic).latestImuData,
          () => (p as dynamic).imuData,
          () => (p as dynamic).lastData,
          () => (p as dynamic).latestData,
          () => (p as dynamic).lastFrame,
          () => (p as dynamic).latestFrame,
          () => (p as dynamic).currentFrame,
    ]) {
      try {
        final v = getter();
        if (v != null) {
          sample = v;
          break;
        }
      } catch (_) {}
    }

    // 2) 如果找不到單筆最新資料，就試著從 recentFrames/buffer 取最後一筆
    if (sample == null) {
      try {
        final rf = (p as dynamic).recentFrames;

        // rf 可能是 List
        if (rf is List && rf.isNotEmpty) {
          sample = rf.last;
        }
        // rf 可能是 Iterable
        else if (rf is Iterable) {
          final it = rf.toList();
          if (it.isNotEmpty) sample = it.last;
        }
        // rf 也可能是自訂結構，有 .last 屬性
        else {
          try {
            final last = (rf as dynamic).last;
            if (last != null) sample = last;
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 3) 最後 fallback：provider 可能直接有 gyroX/gyroY/gyroZ 三個欄位
    if (sample == null) {
      final gx = _tryNum(() => (p as dynamic).gyroX);
      final gy = _tryNum(() => (p as dynamic).gyroY);
      final gz = _tryNum(() => (p as dynamic).gyroZ);
      return [gx, gy, gz];
    }

    // a) sample 若有 gyroX/gyroY/gyroZ 直接讀
    final gx = _tryNum(() => (sample as dynamic).gyroX);
    final gy = _tryNum(() => (sample as dynamic).gyroY);
    final gz = _tryNum(() => (sample as dynamic).gyroZ);
    if (gx != null || gy != null || gz != null) return [gx, gy, gz];

    // b) sample 若有 gyro List（例如 gyro=[x,y,z]）
    try {
      final g = (sample as dynamic).gyro;
      if (g is List && g.length >= 3) {
        return [
          (g[0] is num) ? (g[0] as num).toDouble() : null,
          (g[1] is num) ? (g[1] as num).toDouble() : null,
          (g[2] is num) ? (g[2] as num).toDouble() : null,
        ];
      }
    } catch (_) {}

    // 什麼都抓不到就回 null 三軸
    return const [null, null, null];
  }

  /// 嘗試讀取任意 getter 的數值，若是 num 則轉成 double
  double? _tryNum(dynamic Function() getter) {
    try {
      final v = getter();
      if (v is num) return v.toDouble();
    } catch (_) {}
    return null;
  }

  /// 讀取校正狀態（best-effort）：isCalibrated / calibrated
  bool _getCalibrated(HomeProvider p) {
    try {
      final v = (p as dynamic).isCalibrated;
      if (v is bool) return v;
    } catch (_) {}
    try {
      final v = (p as dynamic).calibrated;
      if (v is bool) return v;
    } catch (_) {}
    return false;
  }

  /// 顯示格式：保留 1 位小數；null / NaN / Inf 則顯示 '-'
  String _fmt1(double? v) =>
      (v == null || !v.isFinite) ? '-' : v.toStringAsFixed(1);

  // -------------------------
  // Actions：對 HomeProvider 呼叫校正/重置
  // 目的：兼容不同版本方法命名（best-effort）
  // -------------------------

  /// 「歸零校正」：嘗試呼叫 provider 的校正方法（多個命名候選）
  Future<bool> _zeroCalibrate(HomeProvider p) async {
    try {
      await (p as dynamic).startCalibration();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).calibrate();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).calibrateNow();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).runCalibration();
      return true;
    } catch (_) {}
    return false; // 全部都找不到 -> 不支援
  }

  /// 「清除 offset」：嘗試呼叫 provider 的 reset/clear offset 方法（多個命名候選）
  Future<bool> _resetOffsets(HomeProvider p) async {
    try {
      await (p as dynamic).resetCalibration();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).clearCalibration();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).resetOffsets();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).clearOffsets();
      return true;
    } catch (_) {}
    try {
      await (p as dynamic).setOffsetsToZero();
      return true;
    } catch (_) {}
    return false; // 全部都找不到 -> 不支援
  }

  /// 點擊「Calibrate」：呼叫校正並顯示提示文字
  Future<void> _onCalibrate() async {
    if (_busy) return; // 忙碌中就忽略

    setState(() {
      _busy = true; // 鎖按鈕
      _hint = ''; // 清空提示
    });

    try {
      final p = context.read<HomeProvider>();
      final ok = await _zeroCalibrate(p);

      setState(() {
        _hint = ok
            ? 'Zero calibration applied.'
            : 'Calibration is not supported (method not found).';
      });

      HapticFeedback.selectionClick();
    } finally {
      if (mounted) setState(() => _busy = false); // 解鎖按鈕
    }
  }

  /// 點擊「Reset offsets」：呼叫清除 offset 並顯示提示文字
  Future<void> _onReset() async {
    if (_busy) return; // 忙碌中就忽略

    setState(() {
      _busy = true; // 鎖按鈕
      _hint = ''; // 清空提示
    });

    try {
      final p = context.read<HomeProvider>();
      final ok = await _resetOffsets(p);

      setState(() {
        _hint = ok
            ? 'Offsets cleared (reset).'
            : 'Reset is not supported (method not found).';
      });

      HapticFeedback.selectionClick();
    } finally {
      if (mounted) setState(() => _busy = false); // 解鎖按鈕
    }
  }

  @override
  Widget build(BuildContext context) {
    // 注意：這裡用 read（不是 watch/Consumer）
    // 因為 gyro 的畫面更新是由 Timer 觸發 setState()，不依賴 provider 自己 notify
    final p = context.read<HomeProvider>();
    final calibrated = _getCalibrated(p);

    // ✅ 不用 AlertDialog：避免預設 title 區塊造成上方留白，改用自訂 Dialog
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 內容多高就多高（避免撐滿螢幕）
          children: [
            // ===== 上方列：校正狀態 pill + 關閉按鈕 =====
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        // YES -> 淺綠底；NO -> 灰底
                        color: calibrated
                            ? const Color(0xFFE8FFF0)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: calibrated
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            calibrated
                                ? Icons.check_circle
                                : Icons.info_outline,
                            size: 16,
                            color: calibrated
                                ? greenDark
                                : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Calibrated: ${calibrated ? 'YES' : 'NO'}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: calibrated
                                  ? greenDark
                                  : const Color(0xFF374151),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 關閉對話框
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  color: const Color(0xFF9CA3AF),
                  splashRadius: 20,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ===== gyro 顯示卡：Base / Live + 提示文字 + 結果 hint =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GYRO XYZ (deg/s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: textGrey,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Base：打開對話框時的 gyro（做為校正前參考）
                  Text(
                    'Base:  x=${_fmt1(_baseGyro[0])}   y=${_fmt1(_baseGyro[1])}   z=${_fmt1(_baseGyro[2])}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Live：Timer 更新的 gyro（即時監看是否穩定/漂移）
                  Text(
                    'Live:  x=${_fmt1(_liveGyro[0])}   y=${_fmt1(_liveGyro[1])}   z=${_fmt1(_liveGyro[2])}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 操作提示（校正時要保持靜止與水平）
                  const Text(
                    'Tip: Keep the racket still and level while calibrating.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  // 操作結果提示（成功/不支援）
                  if (_hint.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _hint,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ===== 下方按鈕列：Reset offsets / Calibrate =====
            Row(
              children: [
                // 左：重置 offset
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _onReset, // 忙碌中停用
                    style: OutlinedButton.styleFrom(
                      foregroundColor: greenDarker,
                      side: const BorderSide(color: accent, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(
                      Icons.restart_alt,
                      size: 18,
                      color: greenDark,
                    ),
                    label: const Text(
                      'Reset offsets',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 右：校正（歸零）
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _onCalibrate, // 忙碌中停用
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8FFF0),
                      foregroundColor: greenDarker,
                      side: const BorderSide(color: accent, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: greenDark,
                    ),
                    label: Text(
                      _busy ? 'Working...' : 'Calibrate', // 忙碌時顯示工作中
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
