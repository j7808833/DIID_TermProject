import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';
import '../ui_layout.dart';
import '../widgets/page_body.dart';
import '../widgets/six_axis_panel.dart';

/// 統計頁：顯示總揮拍數 + 五種姿勢分類計數，並提供重置按鈕
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  // 介面主題點綴色（與整個 App 的綠色系一致）
  static const _accent = Colors.greenAccent;

  // 姿勢名稱 -> 對應圖片資產路徑（用於卡片左側插圖）
  static const Map<String, String> _poseAsset = {
    'Smash': 'assets/poses/Smash.png',
    'Drive': 'assets/poses/Drive.png',
    'Drop': 'assets/poses/Drop.png',
    'Clear': 'assets/poses/Clear.png',
    'Net': 'assets/poses/Net.png',
  };

  /// 重置統計：先嘗試 provider 可能提供的 resetSwingCounts()
  /// 若不存在，則退回直接把 swingCounts 的值清為 0 並 notify
  void _resetStats(HomeProvider p) {
    // ✅ 版本相容：若 HomeProvider 有 resetSwingCounts() 就用它
    try {
      (p as dynamic).resetSwingCounts();
      return;
    } catch (_) {}

    // ✅ fallback：直接把 Map 內所有 key 的 count 清零
    try {
      p.swingCounts.updateAll((_, __) => 0);
      p.notifyListeners(); // 手動通知 UI 重建
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      // Consumer 監聽 HomeProvider：totalSwings 或 swingCounts 更新會自動重建 UI
      builder: (_, p, __) {
        // 顯示順序固定（避免 Map iteration 順序不穩）
        const keys = ['Smash', 'Drive', 'Drop', 'Clear', 'Net'];

        return PageBody(
          children: [
            // 上方六軸資料面板（與其他頁一致）
            const SixAxisPanel(),
            const SizedBox(height: kGapM),

            // 2 欄 Grid：第一張是 Total，其餘五張是各姿勢統計
            GridView.count(
              crossAxisCount: 2, // 兩欄
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55, // 卡片寬高比（偏橫向）
              shrinkWrap: true, // 讓 GridView 在 Column 中可自動包內容高度
              physics: const NeverScrollableScrollPhysics(), // 不讓 Grid 自己滾動
              children: [
                // 總計卡
                _TotalCard(total: p.totalSwings),

                // 各姿勢卡：從 swingCounts 取值，沒有就顯示 0
                for (final k in keys)
                  _StatCard(
                    title: k,
                    value: p.swingCounts[k] ?? 0,
                    assetPath: _poseAsset[k],
                  ),
              ],
            ),

            const SizedBox(height: kGapM),

            // Reset 統計按鈕
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _resetStats(p),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8FFF0),
                  foregroundColor: const Color(0xFF064E3B),
                  side: const BorderSide(color: _accent, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Color(0xFF166534)),
                label: const Text(
                  'Reset stats',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Total 卡：顯示總揮拍數（較醒目，整張用綠底）
class _TotalCard extends StatelessWidget {
  final int total;
  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // LayoutBuilder：用容器實際大小計算右側數字區寬度，避免不同螢幕溢位
      builder: (context, c) {
        // 右側數字區固定比例寬（42%），並限制最小/最大寬度，避免太窄或太寬
        final rightW = (c.maxWidth * 0.42).clamp(56.0, 120.0);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.greenAccent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // 左側：Total 標題（用 Expanded 防止擠壓）
              const Expanded(
                child: Text(
                  'Total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),

              // 右側：數字（置中 + 用 FittedBox 讓大字在小寬度也不爆）
              SizedBox(
                width: rightW,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      total.toString(),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 單一姿勢卡：左側標題+圖，右側大數字
class _StatCard extends StatelessWidget {
  // 文字/邊框色彩常數（統一風格）
  static const _textDark = Color(0xFF111827);
  static const _textGrey = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  final String title; // 姿勢名稱
  final int value; // 次數
  final String? assetPath; // 姿勢圖（可為 null）

  const _StatCard({
    required this.title,
    required this.value,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // LayoutBuilder：依卡片實際寬高計算「右側數字區」與「圖片最大尺寸」
      builder: (context, c) {
        // ✅ 右側數字區：固定 40% 寬度，並 clamp 範圍避免太窄/太寬
        //    這樣 FittedBox 一定有約束，不會出現 overflow 或 layout exception
        final rightW = (c.maxWidth * 0.40).clamp(54.0, 110.0);

        // ✅ 圖片最大尺寸：依卡片高度比例（52%）並 clamp
        //    讓不同裝置下圖片大小看起來都合理
        final imgMax = (c.maxHeight * 0.52).clamp(34.0, 70.0);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 1.2),
            boxShadow: const [
              // 輕陰影：增加卡片層次
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // 左側：標題 + 圖片（上下排列）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 姿勢名稱（上方小字）
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textGrey,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 圖片區：用 Expanded 讓它吃滿剩餘高度
                    Expanded(
                      child: Center(
                        // 沒有 assetPath 就不顯示
                        child: (assetPath == null)
                            ? const SizedBox.shrink()
                            : ConstrainedBox(
                          // 限制圖片最大寬高，避免變形或把卡片撐爆
                          constraints: BoxConstraints(
                            maxWidth: imgMax,
                            maxHeight: imgMax,
                          ),
                          child: Image.asset(
                            assetPath!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // 右側：數字（靠右對齊，並用 FittedBox 縮放避免溢位）
              SizedBox(
                width: rightW,
                child: Center(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        value.toString(),
                        maxLines: 1,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
