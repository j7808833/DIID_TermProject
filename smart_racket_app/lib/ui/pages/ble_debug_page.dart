import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/imu_data.dart';
import '../../services/ble_service.dart';
import '../../providers/home_provider.dart';

import '../ui_layout.dart';
import '../widgets/page_body.dart';

class BleDebugPage extends StatefulWidget {
  const BleDebugPage({super.key});

  @override
  State<BleDebugPage> createState() => _BleDebugPageState();
}

class _BleDebugPageState extends State<BleDebugPage> {
  @override
  Widget build(BuildContext context) {
    // 本頁是「工程用 Debug 面板」：
    // - 上半部放 Trigger sensitivity（目前設計成從 BleDebugPage 入口管理）
    // - 下半部顯示 HomeProvider 的整體狀態快照 + 即時 IMU log（從 BleService 的 imu stream 取資料）
    //
    // Provider 使用策略：
    // - context.watch<BleService>()：只要 BleService notifyListeners，本頁就會 rebuild（用來取得 imuDataStream）
    // - Consumer<HomeProvider>：把 provider 實體傳進 _BleDebugPanel，集中渲染 snapshot/log
    final ble = context.watch<BleService>();

    return Consumer<HomeProvider>(
      builder: (context, p, child) {
        return PageBody(
          children: [
            // ✅ Trigger Sensitivity moved here (replaces old BLE status area)
            // Trigger sensitivity card 以「相容模式」取值（dynamic try/catch），避免 provider 介面調整時整頁爆掉。
            const _TriggerSensitivityCard(),
            const SizedBox(height: kGapM),

            _BleDebugPanel(
              provider: p,
              imuStream: ble.imuDataStream,
            ),
          ],
        );
      },
    );
  }
}

class _TriggerSensitivityCard extends StatelessWidget {
  const _TriggerSensitivityCard();

  // 本卡片刻意用 dynamic 存取 HomeProvider 的設定欄位，目的是「跨版本相容」：
  // - 你可能在不同分支/版本裡把 sensitivity/serverIp/updateSettings 改名或搬位置
  // - Debug UI 不應該變成 compile-time blocker
  // 取不到就用 fallback（2.0 / ''）讓 UI 還能運作。
  double _getSensitivity(HomeProvider p) {
    try {
      return (p as dynamic).sensitivity as double;
    } catch (_) {
      return 2.0;
    }
  }

  String _getServerIp(HomeProvider p) {
    try {
      return (p as dynamic).serverIp as String;
    } catch (_) {
      return '';
    }
  }

  void _updateSettings(HomeProvider p, double sensitivity, String ip) {
    try {
      (p as dynamic).updateSettings(sensitivity, ip);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 視覺規格：沿用整體 app 的 greenAccent / 深綠文字，並用較淺底色凸顯「設定卡」。
    // SliderTheme 做局部覆寫，讓 debug settings 在視覺上與主 UI 調性一致。
    const accent = Colors.greenAccent;
    const greenDark = Color(0xFF166534);
    const textGrey = Color(0xFF374151);
    const cardBg = Color(0xFFF7FDF9);
    const cardBorder = Color(0xFFD1FAE5);

    return Consumer<HomeProvider>(
      builder: (context, p, _) {
        final sensitivity = _getSensitivity(p);
        final serverIp = _getServerIp(p);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardBorder, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 上排：標題 + 當前 G 值（右側強調）
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trigger Sensitivity',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: textGrey,
                      ),
                    ),
                  ),
                  Text(
                    '${sensitivity.toStringAsFixed(1)} G',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: greenDark,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Slider：用 clamp 限制 UI 可調範圍，避免輸入極端值造成 trigger 行為不可預期。
              // onChanged 直接呼叫 HomeProvider.updateSettings：
              // - sensitivity 會映射到 DataBufferManager 的 triggerThreshold
              // - serverIp 不在這張卡改，但需要跟著傳回（updateSettings 的介面需求）
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: const Color(0xFFD1FAE5),
                  thumbColor: accent,
                  overlayColor: accent.withAlpha(40),
                  valueIndicatorColor: greenDark,
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Slider(
                  value: sensitivity.clamp(1.1, 5.0),
                  min: 1.1,
                  max: 5.0,
                  divisions: 39,
                  label: sensitivity.toStringAsFixed(1),
                  onChanged: (v) {
                    _updateSettings(p, v, serverIp);
                  },
                ),
              ),
              const Text(
                'Lower = more sensitive',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BleDebugPanel extends StatefulWidget {
  const _BleDebugPanel({
    required this.provider,
    required this.imuStream,
  });

  // provider 由上層 Consumer<HomeProvider> 直接注入，
  // 讓本 panel 內部不需要再做 watch/lookup，render 也更可控。
  final HomeProvider provider;

  // imuStream 直接吃 BleService 的 broadcast stream（連線後持續產生 IMUData）
  final Stream<IMUData> imuStream;

  @override
  State<_BleDebugPanel> createState() => _BleDebugPanelState();
}

class _BleDebugPanelState extends State<_BleDebugPanel> {
  // IMU log 是 debug 用，不需要無限累積；用 ring-like 的 ListQueue 控制最大行數。
  static const int _logMaxLines = 120;

  final ListQueue<String> _imuLog = ListQueue<String>();
  int? _lastTsMs;

  // pushLog：維持固定上限，超過就丟最舊的，避免 debug 頁面長時間開著造成記憶體壓力。
  void _pushLog(String line) {
    _imuLog.addLast(line);
    while (_imuLog.length > _logMaxLines) {
      _imuLog.removeFirst();
    }
  }

  // clearLog：清掉 log 並重置去重條件（_lastTsMs），讓下一筆資料會立刻寫入。
  void _clearLog() {
    setState(() {
      _imuLog.clear();
      _lastTsMs = null;
    });
  }

  // 格式化輔助：避免 NaN/Inf 直接污染 log 顯示。
  String _fmt3(double v) => v.isFinite ? v.toStringAsFixed(3) : 'NaN';
  String _fmt1(double v) => v.isFinite ? v.toStringAsFixed(1) : 'NaN';

  // IMU log 單行輸出格式：timestamp + acc/gyro + battery voltage（取 HomeProvider 的 batteryVoltage）
  // 這裡不做大量計算，只做字串化；此頁面定位是 debug 可讀性優先。
  String _imuLine(IMUData d, HomeProvider p) {
    final ts = d.timestampMs;
    final acc = 'acc[g]=(${_fmt3(d.accX)}, ${_fmt3(d.accY)}, ${_fmt3(d.accZ)})';
    final gyro = 'gyro[d/s]=(${_fmt1(d.gyroX)}, ${_fmt1(d.gyroY)}, ${_fmt1(d.gyroZ)})';
    final batt = 'V=${p.batteryVoltage.isFinite ? p.batteryVoltage.toStringAsFixed(2) : '0.00'}';
    return 'ts=$ts  $acc  $gyro  $batt';
  }

  // Snapshot 區塊：把 HomeProvider 的關鍵狀態（連線/錄製/上傳/結果/計數/圖表/校正）集中列印。
  // 用 multi-line text box 讓 debug 時不必切頁或打開多個 inspector。
  String _snapshotBlock(HomeProvider p) {
    final rec = p.isRecording ? 'ON' : 'OFF';
    final sid = p.currentSessionId ?? '-';
    final up = p.uploadedCount;
    final pend = p.pendingCount;

    final lrType = p.lastResultType;
    final lrSpeed = p.lastResultSpeed;
    final lrMsg = p.lastResultMessage;

    final cnt = p.swingCounts;
    final total = p.totalSwings;

    return [
      'Connection: ${p.connectionStatus.isEmpty ? (p.isConnected ? 'Connected' : 'Disconnected') : p.connectionStatus}',
      'Recording: $rec   session=$sid',
      'Upload: uploaded=$up  pending=$pend',
      'LastResult: type=$lrType  speed=$lrSpeed',
      'Message: $lrMsg',
      'Counts: Smash=${cnt['Smash']} Drive=${cnt['Drive']} Drop=${cnt['Drop']} Clear=${cnt['Clear']} Net=${cnt['Net']}  total=$total',
      'GraphFrames: ${p.recentFramesSnapshot.length}  seq=${p.recentFramesSnapshotSeq}',
      'Calibrated: ${p.isCalibrated ? 'YES' : 'NO'}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    // 視覺參數：與其他頁一致的 accent/dark green。
    // Debug 頁面仍維持 app 的設計語彙，避免「只有 debug 才長得不一樣」造成使用者困惑。
    const accent = Colors.greenAccent;
    const greenDark = Color(0xFF166534);
    const greenDarker = Color(0xFF064E3B);

    final p = widget.provider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Snapshot
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Snapshot',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.black.withAlpha(160),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: _CompactTextBox(text: _snapshotBlock(p), mono: true),
        ),

        const SizedBox(height: 12),

        // IMU Log
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'IMU Log',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.black.withAlpha(160),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          // StreamBuilder 直接吃 imuStream：
          // - 有資料時把新的一筆 append 到 _imuLog（用 timestamp 去重）
          // - 沒資料時顯示 "No IMU data"
          //
          // 注意：此處不是用 setState 來更新 log，而是依 StreamBuilder rebuild 時 side-effect 寫入 _imuLog。
          // 這種做法對 debug 頁面足夠（避免高頻 setState 造成額外 UI 負擔）。
          child: StreamBuilder<IMUData>(
            stream: widget.imuStream,
            builder: (context, snap) {
              if (snap.hasData) {
                final d = snap.data!;
                final ts = d.timestampMs;
                if (_lastTsMs != ts) {
                  _lastTsMs = ts;
                  _pushLog(_imuLine(d, p));
                }
              }

              final text = _imuLog.isEmpty ? 'No IMU data' : _imuLog.join('\n');
              return _CompactTextBox(text: text, mono: true);
            },
          ),
        ),

        const SizedBox(height: 12),

        // Clear IMU Log
        SizedBox(
          height: 46,
          // 清除 log：加上 haptic feedback，符合整體 app 的互動質感。
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              _clearLog();
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFE8FFF0),
              foregroundColor: greenDarker,
              side: const BorderSide(color: accent, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.delete_outline, color: greenDark),
            label: const Text(
              'Clear IMU Log',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactTextBox extends StatelessWidget {
  const _CompactTextBox({
    required this.text,
    this.mono = false,
  });

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    // 小型文字盒：給 Snapshot/Log 用。
    // 目標是「可複製、可捲動、在小高度內保持可讀」，因此：
    // - 固定 padding + 灰底 + 淺邊框
    // - mono=true 時用 monospace，利於對齊與掃描數值
    // - SingleChildScrollView 允許在固定高度內垂直捲動
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: mono ? 'monospace' : null,
            fontSize: 12,
            height: 1.25,
            color: const Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
