import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../providers/home_provider.dart';
import '../../models/imu_frame.dart';
import '../ui_layout.dart';
import '../widgets/page_body.dart';
import '../widgets/six_axis_panel.dart';

class GraphPage extends StatelessWidget {
  const GraphPage({super.key});

  // 本頁定位：把 HomeProvider 提供的 recentFramesSnapshot（已做 UI throttle 的資料快照）
  // 以固定頻率抽樣、維持固定點數，畫出 acc/gyro 的三軸折線圖。
  // 目標是「穩定、可視化趨勢、不要讓高頻 IMU 直接拖垮 UI」。

  // 20 points @ 250ms -> 約 5 秒視窗
  static const int _maxPoints = 20;
  static const Duration _tick = Duration(milliseconds: 250);
  static const double _chartHeight = 120;
  static const double _chartMaxWidth = 360;

  @override
  Widget build(BuildContext context) {
    // 這行等同於「確保 GraphPage 在 provider tree 之下」，也能提早讓依賴建立。
    // 此頁真正的讀取是在 _ThrottledChart 內用 context.read<HomeProvider>() 取 snapshot。
    context.read<HomeProvider>();

    return PageBody(
      children: [
        // 上方顯示 6 軸即時數值/狀態（與其他頁一致的 panel 元件）
        const SixAxisPanel(),
        const SizedBox(height: kGapM),

        _sectionTitle('Acceleration (G)'),
        const SizedBox(height: 18),

        // Acc 圖：三軸 + 固定 y 範圍（-4~4g），避免 y 軸自動縮放導致視覺抖動。
        // pickX/Y/Z 由 IMUFrame 抽取三軸數值，_ThrottledChart 只負責節流與繪圖。
        _ThrottledChart(
          tick: _tick,
          maxPoints: _maxPoints,
          height: _chartHeight,
          maxWidth: _chartMaxWidth,
          minY: -4,
          maxY: 4,
          legendLabels: const ('X', 'Y', 'Z'),
          pickX: (f) => f.acc[0],
          pickY: (f) => f.acc[1],
          pickZ: (f) => f.acc[2],
        ),

        const SizedBox(height: 38),

        _sectionTitle('Gyroscope (deg/s)'),
        const SizedBox(height: 18),

        // Gyro 圖：同樣三軸，y 範圍固定在 -2000~2000 deg/s（依你的揮拍強度需求可調）
        _ThrottledChart(
          tick: _tick,
          maxPoints: _maxPoints,
          height: _chartHeight,
          maxWidth: _chartMaxWidth,
          minY: -2000,
          maxY: 2000,
          legendLabels: const ('X', 'Y', 'Z'),
          pickX: (f) => f.gyro[0],
          pickY: (f) => f.gyro[1],
          pickZ: (f) => f.gyro[2],
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) {
    return Text(t, style: const TextStyle(fontWeight: FontWeight.w600));
  }
}

class _ThrottledChart extends StatefulWidget {
  const _ThrottledChart({
    required this.tick,
    required this.maxPoints,
    required this.height,
    required this.maxWidth,
    required this.minY,
    required this.maxY,
    required this.pickX,
    required this.pickY,
    required this.pickZ,
    required this.legendLabels,
  });

  // tick：圖表拉資料/append 的頻率（用 Timer 控制），與 HomeProvider 的 snapshot timer 解耦。
  // maxPoints：圖上最多顯示多少個點（點數固定 -> fl_chart layout 更穩）
  final Duration tick;
  final int maxPoints;
  final double height;
  final double maxWidth;
  final double minY;
  final double maxY;

  // pickX/Y/Z：從 IMUFrame 取值的策略，讓同一個 chart widget 可重用在 acc/gyro。
  final double Function(IMUFrame) pickX;
  final double Function(IMUFrame) pickY;
  final double Function(IMUFrame) pickZ;

  /// 圖例文字
  final (String, String, String) legendLabels;

  @override
  State<_ThrottledChart> createState() => _ThrottledChartState();
}

class _ThrottledChartState extends State<_ThrottledChart> {
  // Timer 週期性拉 recentFramesSnapshot，把「新增部分」 append 到本地 ring（ListQueue）。
  // 這個 widget 不直接 listen IMU stream，是刻意依賴 provider 的快照，避免高頻更新。
  Timer? _timer;

  // 三軸 buffer：固定長度 queue，對應 fl_chart 的 0..N-1 x 軸。
  final ListQueue<double> _bx = ListQueue<double>();
  final ListQueue<double> _by = ListQueue<double>();
  final ListQueue<double> _bz = ListQueue<double>();

  // 用 frame.timestamp 追蹤「最後處理到哪一筆」，避免每 tick 全量重跑。
  double? _lastTs;

  // ✅ 藍綠相近色調（可自行微調）
  // 色彩固定：legend 與線條一致，讓使用者在兩張圖之間建立軸向對應。
  static const Color _cX = Color(0xFF2F80ED); // blue
  static const Color _cY = Color(0xFF00BFA6); // teal
  static const Color _cZ = Color(0xFF2DD4BF); // aqua/green-teal

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.tick, (_) => _pullAndAppend());
  }

  @override
  void didUpdateWidget(covariant _ThrottledChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    // tick 變更：重建 timer，確保節流頻率立即生效。
    if (oldWidget.tick != widget.tick) {
      _timer?.cancel();
      _timer = Timer.periodic(widget.tick, (_) => _pullAndAppend());
    }

    // maxPoints 變更：立刻 trim buffer，避免超出圖表 x 範圍；並 setState 觸發 repaint。
    if (oldWidget.maxPoints != widget.maxPoints) {
      _trimTo(widget.maxPoints);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // reset：在資料中斷、或 timestamp 大幅回跳（例如重新連線/重新校正/重啟資料流）時，清空畫面。
  void _reset() {
    _bx.clear();
    _by.clear();
    _bz.clear();
    _lastTs = null;
  }

  // trim：確保三個 queue 同步維持固定長度（視覺上等距滑動）
  void _trimTo(int n) {
    while (_bx.length > n) {
      _bx.removeFirst();
      _by.removeFirst();
      _bz.removeFirst();
    }
  }

  // push：append 一個三軸點，並維持 maxPoints。
  void _push(double vx, double vy, double vz) {
    _bx.addLast(vx);
    _by.addLast(vy);
    _bz.addLast(vz);
    _trimTo(widget.maxPoints);
  }

  // 核心節流邏輯：
  // - 每 tick 取 HomeProvider.recentFramesSnapshot（這是 provider 已經 throttle 過的快照）
  // - 用 _lastTs 找出「新增的 frames」，只 append 新增部分
  // - 碰到 timestamp 回跳則 reset（避免把新 session 的資料接到舊圖上）
  void _pullAndAppend() {
    if (!mounted) return;

    final framesAll = context.read<HomeProvider>().recentFramesSnapshot;
    if (framesAll.isEmpty) {
      // 若 provider 暫時沒有 frame（斷線/尚未初始化），圖上若有舊資料就清掉。
      if (_bx.isNotEmpty) setState(_reset);
      return;
    }

    final lastNowTs = framesAll.last.timestamp;

    // timestamp 大幅回跳：通常代表資料流重置（例如 reconnect、device reboot、或 provider clear）
    // 這裡用 0.5 秒閾值判斷，避免偶發 jitter 誤判。
    if (_lastTs != null && lastNowTs < _lastTs! - 0.5) {
      _reset();
    }

    // 找出從哪一筆開始 append：
    // 從尾端往前掃到 <= _lastTs 的位置，start = i+1
    // 掃不到表示這個 snapshot 全是新資料（或 _lastTs 為 null）
    int start = 0;
    final lastTs = _lastTs;
    if (lastTs != null) {
      for (int i = framesAll.length - 1; i >= 0; i--) {
        if (framesAll[i].timestamp <= lastTs) {
          start = i + 1;
          break;
        }
      }
      if (start >= framesAll.length) return;
    }

    bool appended = false;

    for (int i = start; i < framesAll.length; i++) {
      final f = framesAll[i];

      // 防守式檢查：IMUFrame 的 acc/gyro 應為長度 3，若資料不完整則跳過。
      if (f.acc.length < 3 || f.gyro.length < 3) continue;

      // 由外部注入 pick 函式決定取哪個量（acc 或 gyro）
      final vx = widget.pickX(f);
      final vy = widget.pickY(f);
      final vz = widget.pickZ(f);

      // 防止 NaN/Inf 進入圖表（fl_chart 在極端值/NaN 可能造成 render 問題）
      if (!vx.isFinite || vx.isNaN) continue;
      if (!vy.isFinite || vy.isNaN) continue;
      if (!vz.isFinite || vz.isNaN) continue;

      _push(vx, vy, vz);
      appended = true;
    }

    _lastTs = lastNowTs;

    // 只有真的 append 才 setState，避免空 tick 造成不必要 repaint。
    if (appended) setState(() {});
  }

  // 把 queue 轉成 FlSpot（x 用 index，等距時間軸由 tick 定義，不用真實 timestamp）
  List<FlSpot> _spots(ListQueue<double> buf) {
    final out = <FlSpot>[];
    int i = 0;
    for (final v in buf) {
      out.add(FlSpot(i.toDouble(), v));
      i++;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 把 buffer 映射成 spots（點數上限固定，成本可控）
    final x = _spots(_bx);
    final y = _spots(_by);
    final z = _spots(_bz);

    final (lx, ly, lz) = widget.legendLabels;

    return Center(
      child: ConstrainedBox(
        // maxWidth：避免在大螢幕上 chart 撐太寬導致線條過稀、可讀性下降。
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.height,
              // RepaintBoundary：隔離 chart 的 repaint 範圍，避免上層 UI 一起被迫重繪。
              child: RepaintBoundary(
                child: _buildChart(
                  x: x,
                  y: y,
                  z: z,
                  minY: widget.minY,
                  maxY: widget.maxY,
                  maxPoints: widget.maxPoints,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _LegendRow(
              items: [
                _LegendItem(color: _cX, text: lx),
                _LegendItem(color: _cY, text: ly),
                _LegendItem(color: _cZ, text: lz),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart({
    required List<FlSpot> x,
    required List<FlSpot> y,
    required List<FlSpot> z,
    required double minY,
    required double maxY,
    required int maxPoints,
  }) {
    // fl_chart 在 spots < 2 時容易出現不可預期行為（例如不畫線/計算區間出錯）
    // 這裡用 dummyLine 做「安全 fallback」，並且用 enabled 控制 barWidth，避免畫出假線。
    final hasAny = (x.length >= 2) || (y.length >= 2) || (z.length >= 2);

    final safeX = (x.length >= 2) ? x : _dummyLine();
    final safeY = (y.length >= 2) ? y : _dummyLine();
    final safeZ = (z.length >= 2) ? z : _dummyLine();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (maxPoints - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 34),
          ),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          _line(safeX, color: _cX, enabled: x.length >= 2 || !hasAny),
          _line(safeY, color: _cY, enabled: y.length >= 2 || !hasAny),
          _line(safeZ, color: _cZ, enabled: z.length >= 2 || !hasAny),
        ],
      ),
    );
  }

  static List<FlSpot> _dummyLine() => const [FlSpot(0, 0), FlSpot(1, 0)];

  static LineChartBarData _line(
      List<FlSpot> spots, {
        required Color color,
        required bool enabled,
      }) {
    // barWidth 用 enabled 控制：
    // - 沒有足夠資料時，barWidth=0 -> 等同不顯示
    // - hasAny=false 時允許其中一條顯示（避免 chart 完全空白造成 UX 困惑）
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      dotData: const FlDotData(show: false),
      barWidth: enabled ? 2 : 0,
      color: color,
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    // 圖例列：用 chip 的方式快速建立「顏色 <-> 軸向」對應，置中排版。
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _LegendChip(color: items[i].color, text: items[i].text),
          if (i != items.length - 1) const SizedBox(width: 14),
        ],
      ],
    );
  }
}

class _LegendItem {
  final Color color;
  final String text;
  const _LegendItem({required this.color, required this.text});
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Legend chip：左側顏色方塊 + 右側文字，保持最小寬度以便三個並排。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
