import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';
import '../ui_layout.dart';
import '../widgets/page_body.dart';
import '../widgets/six_axis_panel.dart';

/// 錄製頁：控制錄製/暫停、設定 Session ID、選擇 Label、結束上傳、清除取消
class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage>
    with SingleTickerProviderStateMixin {
  // 主色系（與其他頁一致）
  static const Color _accent = Colors.greenAccent;
  static const Color _greenDark = Color(0xFF166534);
  static const Color _greenDarker = Color(0xFF064E3B);

  // UI 刷新節流：用 StreamBuilder periodic 讓 UI 500ms 更新一次
  static const Duration _uiTick = Duration(milliseconds: 500);

  // 操作按鈕高度（對齊 StatsPage 的按鈕高度）
  static const double _actionBtnH = 52;

  // 時間條/動畫用：控制時間軸條的來回脈動（repeat reverse）
  late final AnimationController _pulseCtrl;

  // 錄製秒數計時器（每秒 +1）
  Timer? _timer;
  int _seconds = 0;

  // 避免重複點擊：任何主要操作進行中會鎖住按鈕
  bool _actionBusy = false;

  // 使用者選擇的 label（五種姿勢 + None）
  String? _selectedLabel;

  // Session ID 欄位：可編輯、可複製、可送出更新 Provider
  final TextEditingController _sidCtrl = TextEditingController();

  // Session ID 欄位狀態：
  // _sidDirty：使用者是否已手動改過（改過就不要再自動覆蓋）
  // _sidProgrammatic：程式自動填值時避免觸發 dirty
  // _sidLastFromProvider：上次同步過的 provider 值，用來判斷需不需要更新欄位
  bool _sidDirty = false;
  bool _sidProgrammatic = false;
  String? _sidLastFromProvider;

  @override
  void initState() {
    super.initState();

    // 脈動動畫：供時間軸條使用
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // 監聽 session 欄位：只要使用者手動改過就標記 dirty
    _sidCtrl.addListener(() {
      if (_sidProgrammatic) return;
      _sidDirty = true;
    });
  }

  @override
  void dispose() {
    // 清掉 timer / controller / text controller，避免記憶體洩漏
    _timer?.cancel();
    _pulseCtrl.dispose();
    _sidCtrl.dispose();
    super.dispose();
  }

  // ========================= Provider 相容性（避免編譯失敗） =========================

  /// 取得暫停狀態：若 provider 沒有 isPaused，就回傳 false（保持可編譯）
  bool _getPaused(HomeProvider p) {
    try {
      return (p as dynamic).isPaused as bool;
    } catch (_) {
      return false;
    }
  }

  /// 暫停：優先嘗試 pauseRecord；沒有就退回 stopRecord（舊版相容）
  Future<void> _pause(HomeProvider p) async {
    try {
      await (p as dynamic).pauseRecord();
      return;
    } catch (_) {}
    await p.stopRecord();
  }

  /// 繼續：優先嘗試 resumeRecord；沒有就退回 startRecord（舊版相容）
  Future<void> _resume(HomeProvider p) async {
    try {
      await (p as dynamic).resumeRecord();
      return;
    } catch (_) {}
    await p.startRecord();
  }

  // ========================= UI 計時器（純 UI，不影響資料錄製） =========================

  /// 開始每秒計時（錄製中用）
  void _startUiTimerIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  /// 停止 UI 計時（不改秒數）
  void _stopUiTimerOnly() {
    _timer?.cancel();
    _timer = null;
  }

  /// 重設 UI 計時（歸零）
  void _resetUiTimer() {
    _stopUiTimerOnly();
    if (mounted) setState(() => _seconds = 0);
  }

  /// 秒數格式化成 mm:ss
  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ========================= Session / 錄製狀態判斷 =========================

  /// 取得 sessionId：先嘗試 dynamic 欄位，再退回 p.currentSessionId（相容不同版本）
  String? _getSessionId(HomeProvider p) {
    try {
      final v = (p as dynamic).currentSessionId;
      if (v is String) return v;
    } catch (_) {}

    try {
      final v = p.currentSessionId;
      return v;
    } catch (_) {}

    return null;
  }

  /// 是否存在 session 或正在錄製（用來判斷是否允許 End & Upload）
  bool _hasSessionOrRecording(HomeProvider p) {
    final sid = _getSessionId(p);
    return (sid != null && sid.trim().isNotEmpty) || p.isRecording;
  }

  // ========================= 小工具：Snack / Dialog =========================

  /// 顯示簡短 SnackBar（統一入口）
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(milliseconds: 900), content: Text(msg)),
    );
  }

  /// 確認對話框（回傳 true 表示按下 OK）
  Future<bool> _confirmDialog({
    required String title,
    required String content,
    required String okText,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ========================= Session 可編輯（盡量支援多版本 provider） =========================

  /// 嘗試把欄位文字寫回 provider（不同版本可能方法名稱不同，所以用多段 fallback）
  Future<void> _trySetSessionId(HomeProvider p, String sid) async {
    final v = sid.trim();
    if (v.isEmpty) {
      _snack('Session is empty');
      return;
    }

    bool ok = false;

    // 依序嘗試可能存在的方法名稱
    try {
      await (p as dynamic).setSessionId(v);
      ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        await (p as dynamic).setCurrentSessionId(v);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).updateSessionId(v);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).renameSession(v);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      // 某些實作可能直接給 set 欄位（不建議，但保留相容）
      try {
        (p as dynamic).currentSessionId = v;
        ok = true;
      } catch (_) {}
    }

    _snack(ok ? 'Session updated' : 'Session edit not supported (UI only)');
  }

  /// 複製 Session ID：優先用欄位文字，沒有才用 provider currentSessionId
  Future<void> _copySessionIdFromField(HomeProvider p) async {
    final text = _sidCtrl.text.trim();
    final sid = text.isNotEmpty ? text : (_getSessionId(p) ?? '').trim();

    if (sid.isEmpty) {
      _snack('No session id');
      return;
    }
    await Clipboard.setData(ClipboardData(text: sid));
    _snack('Copied');
  }

  // ========================= Label 設定（盡量支援多版本 provider） =========================

  /// 設定 label：嘗試多個方法/欄位名稱，最後至少保留本地 _selectedLabel
  Future<void> _setLabel(HomeProvider p, String label) async {
    bool ok = false;

    // 依序嘗試常見命名
    try {
      await (p as dynamic).setLabel(label);
      ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        await (p as dynamic).setSessionLabel(label);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).setCurrentLabel(label);
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).setRecordLabel(label);
        ok = true;
      } catch (_) {}
    }

    // 最後退回直接設欄位（若 provider 允許）
    if (!ok) {
      try {
        (p as dynamic).label = label;
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        (p as dynamic).currentLabel = label;
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        (p as dynamic).sessionLabel = label;
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        (p as dynamic).recordLabel = label;
        ok = true;
      } catch (_) {}
    }

    // UI 一定要更新
    setState(() => _selectedLabel = label);
    _snack(ok ? 'Label: $label' : 'Label set (local): $label');
  }

  // ========================= End & Upload（結束 session 並上傳/儲存） =========================

  Future<void> _endAndUpload(HomeProvider p) async {
    if (_actionBusy) return;

    final hasSession = _hasSessionOrRecording(p);
    if (!hasSession) {
      _snack('No active session.');
      return;
    }

    // 使用者確認，避免誤觸
    final ok = await _confirmDialog(
      title: 'End & Upload?',
      content: 'This will finish the current session and upload/save it.',
      okText: 'End & Upload',
    );
    if (!ok) return;

    setState(() => _actionBusy = true);

    try {
      // 停止 UI 動畫/計時（資料端仍由 provider 控制）
      if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
      _stopUiTimerOnly();

      final label = _selectedLabel;
      bool done = false;

      // 依序嘗試不同版本的「結束 session」方法（可帶 label 或不帶）
      try {
        if (label == null) {
          await (p as dynamic).endSession();
        } else {
          await (p as dynamic).endSession(label);
        }
        done = true;
      } catch (_) {}

      if (!done) {
        try {
          if (label == null) {
            await (p as dynamic).finishSession();
          } else {
            await (p as dynamic).finishSession(label);
          }
          done = true;
        } catch (_) {}
      }

      if (!done) {
        try {
          if (label == null) {
            await (p as dynamic).stopSession();
          } else {
            await (p as dynamic).stopSession(label);
          }
          done = true;
        } catch (_) {}
      }

      // 最後 fallback：至少停止錄製
      if (!done) {
        await p.stopRecord();
      }

      _snack(label == null
          ? 'End & Upload: done'
          : 'End & Upload: done (label=$label)');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ========================= Clear / Cancel（清除或取消 session） =========================

  Future<void> _clearCancel(HomeProvider p) async {
    if (_actionBusy) return;

    final hasSession = _hasSessionOrRecording(p);

    // 根據是否有 session，顯示不同文案
    final ok = await _confirmDialog(
      title: hasSession ? 'Clear / Cancel session?' : 'Clear record?',
      content: hasSession
          ? 'This will delete/cancel the current session data.'
          : 'This will clear the current recording so you can start over.',
      okText: 'Clear / Cancel',
    );
    if (!ok) return;

    setState(() => _actionBusy = true);

    try {
      // 清 UI 狀態
      if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
      _resetUiTimer();

      bool done = false;

      // 有 session 的話：優先嘗試 cancel/delete/remove 等方法
      if (hasSession) {
        try {
          await (p as dynamic).cancelSession();
          done = true;
        } catch (_) {}
        if (!done) {
          try {
            await (p as dynamic).cancelRecord();
            done = true;
          } catch (_) {}
        }
        if (!done) {
          try {
            await (p as dynamic).deleteSession();
            done = true;
          } catch (_) {}
        }
        if (!done) {
          try {
            await (p as dynamic).removeSession();
            done = true;
          } catch (_) {}
        }
      }

      // 最後 fallback：清除錄製資料
      if (!done) {
        await p.clearRecord();
      }

      // 清掉本地 label
      setState(() => _selectedLabel = null);
      _snack('Clear / Cancel: done');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ========================= 主圓按鈕行為（Record / Pause / Resume） =========================

  /// 主圓按鈕邏輯：
  /// - 未錄製：startRecord
  /// - 錄製中未暫停：pauseRecord（或 stopRecord fallback）
  /// - 錄製中已暫停：resumeRecord（或 startRecord fallback）
  Future<void> _toggleMainButton(HomeProvider p) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);

    try {
      final recording = p.isRecording;
      final paused = _getPaused(p);

      if (!recording) {
        await p.startRecord();
      } else {
        if (paused) {
          await _resume(p);
        } else {
          await _pause(p);
        }
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ========================= v3 額外功能按鈕（盡量支援多版本 provider） =========================

  /// Flush Pending：把尚未上傳的 buffer 送出（不同版本方法名不同）
  Future<void> _v3FlushPending(HomeProvider p) async {
    bool ok = false;
    try {
      await (p as dynamic).flushPending();
      ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        await (p as dynamic).flush();
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).flushBuffer();
        ok = true;
      } catch (_) {}
    }
    _snack(ok ? 'Flush Pending: done' : 'Flush Pending not supported');
  }

  /// Reset Upload Counters：重置上傳/待上傳計數（只改 UI/統計）
  Future<void> _v3ResetUploadCounters(HomeProvider p) async {
    bool ok = false;
    try {
      (p as dynamic).resetUploadCounters();
      ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        (p as dynamic).resetCounters();
        ok = true;
      } catch (_) {}
    }
    _snack(ok ? 'Reset Counters: done' : 'Reset Counters not supported');
  }

  // ========================= UI 區塊：Session 欄位 =========================

  Widget _sessionEditableRow(HomeProvider p) {
    final providerSid = (p.currentSessionId ?? '').trim();

    // 自動帶入：使用者未改過（_sidDirty=false）時，才同步 provider 的 sessionId 到輸入框
    if (!_sidDirty && providerSid != _sidLastFromProvider) {
      _sidProgrammatic = true; // 避免 listener 把它判成使用者改動
      _sidCtrl.text = providerSid;
      _sidCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _sidCtrl.text.length),
      );
      _sidProgrammatic = false;
      _sidLastFromProvider = providerSid;
    }

    return SizedBox(
      height: 52,
      child: TextField(
        controller: _sidCtrl,
        enabled: !_actionBusy, // 操作中鎖住避免狀態不一致
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
        decoration: InputDecoration(
          hintText: 'Session ID / Name',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD1FAE5), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD1FAE5), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.greenAccent, width: 1.6),
          ),
          // 右側 Copy 按鈕：複製 sessionId
          suffixIcon: IconButton(
            tooltip: 'Copy',
            onPressed: _actionBusy
                ? null
                : () async {
              HapticFeedback.selectionClick();
              await _copySessionIdFromField(p);
            },
            icon: const Icon(Icons.copy_rounded, color: _greenDark),
          ),
        ),
        textInputAction: TextInputAction.done,
        // 按 Enter：嘗試寫回 provider
        onSubmitted: (v) async {
          HapticFeedback.selectionClick();
          await _trySetSessionId(p, v);
        },
        // 編輯完成（例如點到其他地方）：同樣寫回 provider
        onEditingComplete: () async {
          HapticFeedback.selectionClick();
          await _trySetSessionId(p, _sidCtrl.text);
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  // ========================= UI 區塊：狀態膠囊（Recording / Paused / Not recording） =========================

  Widget _statusPill({required bool recording, required bool paused}) {
    final String text;
    final IconData icon;
    final Color bg;
    final Color bd;
    final Color fg;

    if (!recording) {
      text = 'Not recording';
      icon = Icons.videocam_outlined;
      bg = const Color(0xFFF3F4F6);
      bd = const Color(0xFFE5E7EB);
      fg = const Color(0xFF6B7280);
    } else if (paused) {
      text = 'Paused';
      icon = Icons.pause_circle_outline;
      bg = const Color(0xFFF3F4F6);
      bd = const Color(0xFFD1D5DB);
      fg = const Color(0xFF374151);
    } else {
      text = 'Recording...';
      icon = Icons.videocam;
      bg = const Color(0xFFE8FFF0);
      bd = const Color(0xFF22C55E);
      fg = _greenDark;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd, width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
              fontSize: 12,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ========================= UI 區塊：時間膠囊（顯示 mm:ss） =========================

  Widget _timePill({
    required bool recording,
    required bool paused,
    required String timeText,
  }) {
    // 不同狀態給不同底色與邊框，方便辨識
    final bg = paused
        ? const Color(0xFFF3F4F6)
        : (recording ? const Color(0xFFE8FFF0) : const Color(0xFFF3F4F6));
    final bd = paused
        ? const Color(0xFFD1D5DB)
        : (recording ? const Color(0xFF22C55E) : const Color(0xFFD1D5DB));
    final fg = paused
        ? const Color(0xFF374151)
        : (recording ? const Color(0xFF166534) : const Color(0xFF374151));

    // icon：錄製中用小圓點，暫停/未錄製用 pause 圖示
    final icon = paused
        ? Icons.pause_circle_filled
        : (recording ? Icons.circle : Icons.pause_circle_filled);

    final iconColor = paused
        ? const Color(0xFF6B7280)
        : (recording ? const Color(0xFF16A34A) : const Color(0xFF6B7280));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: iconColor),
          const SizedBox(width: 8),
          Text(
            timeText,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
              fontSize: 12,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ========================= UI 區塊：Label 群組（Smash/Drive/Drop/Clear/Net/None） =========================

  Widget _labelsGroup(HomeProvider p) {
    const labels = ['Smash', 'Drive', 'Drop', 'Clear', 'Net'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Labels',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Color(0xFF374151),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            // 五種姿勢 label
            for (final lb in labels)
              _LabelChip(
                text: lb,
                selected: _selectedLabel == lb,
                onTap: _actionBusy
                    ? null
                    : () async {
                  HapticFeedback.selectionClick();
                  await _setLabel(p, lb);
                },
              ),
            // None：只改本地狀態，不強制寫回 provider
            _LabelChip(
              text: 'None',
              selected: _selectedLabel == null,
              onTap: _actionBusy
                  ? null
                  : () {
                HapticFeedback.selectionClick();
                setState(() => _selectedLabel = null);
              },
              light: true,
            ),
          ],
        ),
      ],
    );
  }

  // ========================= UI 區塊：功能按鈕群（Flush/End/Reset/Clear） =========================

  Widget _actionButtons(HomeProvider p, {required bool hasSession}) {
    // 統一按鈕樣式
    final style = OutlinedButton.styleFrom(
      backgroundColor: const Color(0xFFE8FFF0),
      foregroundColor: _greenDarker,
      side: const BorderSide(color: _accent, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

    // 產生按鈕（避免重複寫法）
    Widget btn({
      required String text,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        height: _actionBtnH,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: style,
          icon: Icon(icon, color: _greenDark, size: 18),
          label: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: btn(
                text: 'Flush Pending',
                icon: Icons.sync_outlined,
                onPressed: _actionBusy
                    ? null
                    : () async {
                  HapticFeedback.selectionClick();
                  await _v3FlushPending(p);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: btn(
                text: 'End & Upload',
                icon: Icons.cloud_upload_outlined,
                // 沒有 session 就禁用（避免誤按）
                onPressed: (_actionBusy || !hasSession)
                    ? null
                    : () async {
                  HapticFeedback.selectionClick();
                  await _endAndUpload(p);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: btn(
                text: 'Reset Counters',
                icon: Icons.refresh_outlined,
                onPressed: _actionBusy
                    ? null
                    : () async {
                  HapticFeedback.selectionClick();
                  await _v3ResetUploadCounters(p);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: btn(
                text: 'Clear / Cancel',
                icon: Icons.delete_outline,
                onPressed: _actionBusy
                    ? null
                    : () async {
                  HapticFeedback.selectionClick();
                  await _clearCancel(p);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ========================= build：主 UI =========================

  @override
  Widget build(BuildContext context) {
    // 使用 StreamBuilder 週期性重建 UI（避免每個元件自己開 timer）
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(_uiTick, (i) => i),
      builder: (_, __) {
        final p = context.read<HomeProvider>();

        final recording = p.isRecording;
        final paused = _getPaused(p);
        final hasSession = _hasSessionOrRecording(p);

        // 狀態驅動 UI：錄製中且非暫停 -> 播放時間條動畫 + 開始秒數計時
        // 暫停/停止 -> 停動畫、停計時；完全停止且秒數不為 0 -> 重設 UI 計時
        if (recording && !paused) {
          if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
          _startUiTimerIfNeeded();
        } else {
          if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
          if (_timer != null) _stopUiTimerOnly();
          if (!recording && _seconds != 0) _resetUiTimer();
        }

        // 顯示時間：未錄製固定 00:00；錄製中顯示累積秒數
        final timeText = (recording ? _formatTime(_seconds) : '00:00');

        return PageBody(
          children: [
            // 上方六軸面板
            const SixAxisPanel(),
            const SizedBox(height: kGapM),

            // 主卡片：統一背景、邊框、圓角
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FDF9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1FAE5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一列：狀態膠囊 + 時間膠囊
                  Row(
                    children: [
                      _statusPill(recording: recording, paused: paused),
                      const Spacer(),
                      _timePill(
                        recording: recording,
                        paused: paused,
                        timeText: timeText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 時間軸條：錄製中會顯示脈動滑塊
                  _TimelineBar(controller: _pulseCtrl, enabled: recording && !paused),
                  const SizedBox(height: 12),

                  // Session ID 欄位：可編輯、可複製
                  _sessionEditableRow(p),
                  const SizedBox(height: 12),

                  // 上傳統計：Uploaded / Pending
                  Row(
                    children: [
                      Expanded(child: _InfoRow(label: 'Uploaded', value: '${p.uploadedCount}')),
                      const SizedBox(width: 12),
                      Expanded(child: _InfoRow(label: 'Pending', value: '${p.pendingCount}')),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 主圓按鈕 + label 群組（同一列）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左側：大圓錄製按鈕 + 說明文字
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BigCircleRecordButton(
                            busy: _actionBusy,
                            recording: recording,
                            paused: paused,
                            onPressed: () => _toggleMainButton(p),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (recording && !paused) ? 'Pause' : 'Record',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),

                      // 右側：Label chips（置中）
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: _labelsGroup(p),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 下方：操作按鈕（Flush / End / Reset / Clear）
                  _actionButtons(p, hasSession: hasSession),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ========================= Label Chip =========================

/// 單一 Label 按鈕（可選取狀態）
class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.text,
    required this.selected,
    required this.onTap,
    this.light = false,
  });

  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final bool light;

  @override
  Widget build(BuildContext context) {
    const accent = Colors.greenAccent;
    const greenDarker = Color(0xFF064E3B);

    // selected / light 狀態會改變背景色與邊框色
    final bg = selected
        ? const Color(0xFFE8FFF0)
        : (light ? const Color(0xFFF3F4F6) : Colors.white);
    final bd = selected ? accent : const Color(0xFFE5E7EB);
    final fg = selected ? greenDarker : const Color(0xFF374151);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: bd, width: 1.2),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: fg,
            fontSize: 12,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ========================= 主圓錄製按鈕 =========================

/// 大圓按鈕：錄製中顯示 Pause；非錄製或暫停顯示 Record icon
class _BigCircleRecordButton extends StatelessWidget {
  const _BigCircleRecordButton({
    required this.busy,
    required this.recording,
    required this.paused,
    required this.onPressed,
  });

  final bool busy;
  final bool recording;
  final bool paused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const accent = Colors.greenAccent;

    // 只有「正在錄製且未暫停」才顯示 Pause
    final bool showPause = recording && !paused;

    final Color bg = showPause ? accent : Colors.white;
    final Color border = accent;

    // icon 顏色：Pause 時偏深綠；Record 時偏綠
    final Color iconColor =
    showPause ? const Color(0xFF064E3B) : const Color(0xFF166534);

    // icon：Pause 或 Record（radio_button_checked）
    final IconData icon =
    showPause ? Icons.pause_rounded : Icons.radio_button_checked_rounded;

    const double size = 96;
    const double iconSize = 44;

    return Semantics(
      button: true,
      label: showPause ? 'Pause recording' : 'Start recording',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onPressed, // 操作中禁用
          customBorder: const CircleBorder(),
          splashColor: Colors.grey.withValues(alpha: 0.18),
          highlightColor: Colors.grey.withValues(alpha: 0.10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================= 時間軸條（脈動滑塊） =========================

/// 時間條：enabled=true 時顯示一段綠色滑塊左右移動（用 AnimationController 驅動）
class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.controller,
    required this.enabled,
  });

  final AnimationController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFFE5E7EB);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 10,
        color: base,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final t = controller.value; // 0..1
            final w = 0.22; // 滑塊寬度比例（佔整條的 22%）
            final pos = (t - w / 2).clamp(0.0, 1.0 - w); // 左側位置（0..1-w）

            return LayoutBuilder(
              builder: (context, c) {
                final width = c.maxWidth;
                final left = width * pos;

                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: width * w,
                      child: Opacity(
                        opacity: enabled ? 1.0 : 0.0, // 未啟用就隱藏滑塊
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ========================= 簡單資訊列（Uploaded / Pending） =========================

/// 小資訊列：左 label、右 value（單行省略）
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
