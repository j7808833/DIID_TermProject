import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/realtime_page.dart';
import 'pages/graph_page.dart';
import 'pages/record_page.dart';
import 'pages/stats_page.dart';
import 'pages/ble_debug_page.dart';

import 'widgets/calibration_action.dart';

/// App 主頁：
/// - 上方 AppBar 顯示目前分頁標題
/// - 中間用 IndexedStack 承載 5 個頁面（保留狀態，不因切換重建）
/// - 下方 BottomNavigationBar 負責切頁
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 目前分頁索引（0~4）
  int _index = 0;

  /// 5 個分頁 Widget（在 initState 一次建立，避免重複 new）
  late final List<Widget> _pages;

  /// AppBar 顯示的標題（與 BottomNavigationBar label 對應）
  static const _titles = ['Link', 'Graph', 'Record', 'Stats', 'BLE Debug'];

  @override
  void initState() {
    super.initState();

    // ✅ 初始化頁面列表：
    // 使用 const 頁面可減少重建成本；IndexedStack 會保留每頁狀態
    _pages = const [
      RealtimePage(),
      GraphPage(),
      RecordPage(),
      StatsPage(),
      BleDebugPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 主色（與整套 UI 的綠色系一致）
    const accent = Colors.greenAccent;

    // 取得目前 Theme（用來延用字體等設定）
    final theme = Theme.of(context);

    return Scaffold(
      // 全頁白底（避免預設 scaffold 灰底影響視覺）
      backgroundColor: Colors.white,

      appBar: AppBar(
        // 標題置中（對齊 iOS/現代 App 習慣）
        centerTitle: true,

        // AppBar 主色與文字/圖示色彩
        backgroundColor: accent,
        foregroundColor: Colors.white,

        // 覆寫標題字體（沿用 theme 的 titleLarge，再改顏色與字重）
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),

        // 左側返回/抽屜等 icon 顏色（此頁通常沒有，但保持一致）
        iconTheme: const IconThemeData(color: Colors.white),

        // 右側 actions icon 顏色
        actionsIconTheme: const IconThemeData(color: Colors.white),

        // 依目前索引顯示標題
        title: Text(_titles[_index]),

        // ✅ 右上角只留校正入口：
        // 避免同時存在多套校正 UI/流程，減少使用者混淆
        actions: const [
          CalibrationAction(),
        ],
      ),

      // ✅ IndexedStack：
      // - 好處：切換分頁不會 dispose/rebuild 子頁（保留 scroll、controller、狀態）
      // - 避免某些情況下 page 被重建導致 index/狀態「看起來歸零」
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),

      // BottomNavigationBar 外包一層 Theme：
      // 用來調整點擊時的 ripple/highlight 顏色（維持整體一致）
      bottomNavigationBar: Theme(
        data: theme.copyWith(
          splashColor: accent.withAlpha(64),    // 點下去的水波紋
          highlightColor: accent.withAlpha(38), // 按住時的高亮
        ),
        child: BottomNavigationBar(
          // 底部列背景白色
          backgroundColor: Colors.white,

          // 目前選到哪一個 tab
          currentIndex: _index,

          // 點擊切換 tab
          onTap: (i) {
            // 觸覺回饋（更像原生 App 操作感）
            HapticFeedback.selectionClick();

            // 點同一個 tab 不做事（避免不必要 rebuild）
            if (i == _index) return;

            // 更新 index -> IndexedStack 顯示對應頁面、AppBar 標題更新
            setState(() => _index = i);
          },

          // fixed：五個 tab 都顯示 label（不會因數量變動而隱藏）
          type: BottomNavigationBarType.fixed,

          // 選中/未選中顏色
          selectedItemColor: accent,
          unselectedItemColor: Colors.grey,

          // 5 個 tab 項目：icon + label
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.link), label: 'Link'),
            BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Graph'),
            BottomNavigationBarItem(
              icon: Icon(Icons.radio_button_checked_rounded),
              label: 'Record',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.gps_fixed_rounded), // ✅ 使用 target 風格 icon
              label: 'Stats',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.bug_report), label: 'Debug'),
          ],
        ),
      ),
    );
  }
}
