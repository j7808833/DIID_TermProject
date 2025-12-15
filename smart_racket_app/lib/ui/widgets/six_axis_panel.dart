import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/home_provider.dart';

/// 六軸資訊面板：
/// - 每 250ms 重繪一次（用 StreamBuilder 觸發）
/// - 顯示 BLE 連線狀態、加速度 ACC、角速度 GYRO、電池電壓、時間戳
class SixAxisPanel extends StatelessWidget {
  const SixAxisPanel({super.key});

  /// UI 更新頻率（250ms 一次）
  static const Duration _tick = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    // 用 periodic stream 讓 UI 固定頻率刷新（即使 provider 沒 notifyListeners）
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(_tick, (i) => i),
      builder: (_, __) {
        // read：只取值，不因 provider notifyListeners 造成額外 rebuild
        final p = context.read<HomeProvider>();

        // 連線狀態：決定整體配色（綠色＝連線；灰色＝未連線）
        final connected = p.isConnected;

        final bg = connected ? const Color(0xFFE8FFF0) : const Color(0xFFF3F4F6);
        final bd = connected ? const Color(0xFF22C55E) : const Color(0xFFD1D5DB);
        final titleColor = connected ? const Color(0xFF166534) : const Color(0xFF374151);

        // 取最新一筆 IMU frame（可能為 null）
        final f = p.latestFrame;

        // acc / gyro 是 List<double>?（可能為 null）
        final acc = f?.acc;
        final gyro = f?.gyro;

        // 數值格式化工具：
        // - null / NaN / Infinite -> 顯示 '—'
        // - 否則依指定小數位輸出
        String fmt3(double? v) =>
            (v == null || !v.isFinite || v.isNaN) ? '—' : v.toStringAsFixed(3);
        String fmt2(double? v) =>
            (v == null || !v.isFinite || v.isNaN) ? '—' : v.toStringAsFixed(2);
        String fmt1(double? v) =>
            (v == null || !v.isFinite || v.isNaN) ? '—' : v.toStringAsFixed(1);

        // 標題：顯示 BLE 狀態字串（永遠置中）
        final title = Text(
          'BLE: ${p.connectionStatus}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center, // ✅ 文字本身也置中
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: titleColor,
          ),
        );

        return Container(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // 整塊面板背景與邊框會隨連線狀態變色
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bd, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== 標題列（永遠置中）=====
              Row(
                children: [
                  Expanded(child: Center(child: title)),
                ],
              ),
              const SizedBox(height: 10),

              // ===== 六軸數值：左 ACC / 右 GYRO =====
              Row(
                children: [
                  Expanded(
                    child: _AxisBlock(
                      title: 'ACC (g)',
                      // acc?[0]：若 acc 為 null 則結果為 null
                      x: fmt2(acc?[0]),
                      y: fmt2(acc?[1]),
                      z: fmt2(acc?[2]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AxisBlock(
                      title: 'GYRO (dps)',
                      x: fmt1(gyro?[0]),
                      y: fmt1(gyro?[1]),
                      z: fmt1(gyro?[2]),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ===== 底部資訊：電池電壓 + timestamp =====
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // batteryVoltage 通常是 double?（若為 null 則顯示 '—'）
                      'Battery ${fmt3(p.batteryVoltage)} V',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    // f?.timestamp 可能為 null
                    't=${fmt3(f?.timestamp)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 單一區塊（ACC / GYRO）：
/// - 顯示標題 + X/Y/Z 三行數值
class _AxisBlock extends StatelessWidget {
  final String title;
  final String x, y, z;

  const _AxisBlock({
    required this.title,
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  Widget build(BuildContext context) {
    // 軸標籤樣式（X/Y/Z）
    const labelStyle = TextStyle(fontSize: 12, color: Colors.black54);

    // 數值樣式（用等寬字體更像儀表）
    const valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      fontFamily: 'Menlo',
    );

    /// 一行「X: value」
    Widget row(String axis, String value) {
      return Row(
        children: [
          Text('$axis: ', style: labelStyle),
          Expanded(
            child: Align(
              // 數值靠左對齊，避免因長度不同而跳動
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 白底半透明，讓上層面板底色透出一點
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 區塊標題（ACC / GYRO）
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),

          // 三軸數值
          row('X', x),
          row('Y', y),
          row('Z', z),
        ],
      ),
    );
  }
}
