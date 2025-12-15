import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ui_layout.dart';
import '../../providers/home_provider.dart';

/// 頁面共用的 Body 容器：
/// - 主要內容用 SingleChildScrollView 包起來（可捲動）
/// - 另外疊一層「偵測到揮拍」的 popup（上方浮出、可自動消失、有冷卻時間）
class PageBody extends StatefulWidget {
  /// 要顯示在頁面內的子元件列表（由各分頁傳入）
  final List<Widget> children;

  const PageBody({super.key, required this.children});

  @override
  State<PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<PageBody> {
  /// 內距（同時用在 scroll 區與 popup 左右邊界）
  static const double _pad = 16;

  /// ✅ popup 顯示後 2 秒自動關閉
  static const Duration _autoHide = Duration(seconds: 2);

  /// ✅ popup 冷卻 15 秒（UI 節流；避免太頻繁彈出）
  /// ※ HomeProvider 可能也有做統計/節流，這裡是 UI 層再保險
  static const Duration _cooldown = Duration(seconds: 15);

  /// 控制自動隱藏的 timer
  Timer? _hideTimer;

  /// 上一次已處理的 popup 序號（避免同一事件重複彈出）
  int _lastSeq = 0;

  /// 是否顯示 popup（AnimatedOpacity / AnimatedSlide 會依此動畫）
  bool _show = false;

  /// popup 內容：偵測到的動作類型（Smash/Drive/...）
  String _type = '—';

  /// 上一次真正彈出 popup 的時間（用來做 15 秒冷卻）
  DateTime _lastPopupAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    // 離開頁面時要取消 timer，避免 memory leak / callback 打到已 dispose 的 widget
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 是否允許此刻彈出 popup（距離上次彈出是否已超過冷卻時間）
  bool _canPopupNow() {
    final now = DateTime.now();
    return now.difference(_lastPopupAt) >= _cooldown;
  }

  /// 顯示 popup 並啟動自動隱藏 timer
  void _showPopup(String type, int seq) {
    // 先取消舊 timer（避免重疊）
    _hideTimer?.cancel();

    // 更新冷卻時間基準
    _lastPopupAt = DateTime.now();

    // 更新狀態：記錄 seq、更新 type、顯示 popup
    setState(() {
      _lastSeq = seq;
      _type = type;
      _show = true;
    });

    // 2 秒後自動隱藏（注意 mounted 檢查）
    _hideTimer = Timer(_autoHide, () {
      if (!mounted) return;
      setState(() => _show = false);
    });
  }

  /// 使用者手動關閉 popup（按 Close）
  void _closePopup() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!mounted) return;
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    // watch：只要 shotPopupSeq 變化就會 rebuild（用來觸發 popup 邏輯）
    final p = context.watch<HomeProvider>();
    final seq = p.shotPopupSeq;

    // seq != 0 表示 provider 有發出「彈窗事件」
    // seq != _lastSeq 表示是新事件（避免同一事件重複處理）
    if (seq != 0 && seq != _lastSeq) {
      // 使用 postFrameCallback：避免在 build 期間直接 setState 導致錯誤
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // read：避免因為讀取而額外觸發 rebuild；只拿當下最新值
        final p2 = context.read<HomeProvider>();
        final seq2 = p2.shotPopupSeq;
        final type2 = p2.shotPopupType;

        // 若 provider 已經清掉事件、或我們剛好已處理過，就不做事
        if (seq2 == 0 || seq2 == _lastSeq) return;

        // ✅ UI 冷卻：若 15 秒內已彈過，這次就「吞掉」事件
        // 但要更新 _lastSeq，避免每次 rebuild 都一直嘗試處理同一 seq
        if (!_canPopupNow()) {
          _lastSeq = seq2;
          return;
        }

        // 真正彈出 popup
        _showPopup(type2, seq2);
      });
    }

    return Stack(
      children: [
        // ===== 主內容：可捲動區域 =====
        SingleChildScrollView(
          padding: const EdgeInsets.all(_pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),

        // ===== Popup：固定在頂部（覆蓋在內容之上） =====
        Positioned(
          left: _pad,
          right: _pad,
          top: _pad,
          child: IgnorePointer(
            // _show=false 時讓 popup 不吃點擊（避免擋住下面 UI）
            ignoring: !_show,
            child: AnimatedOpacity(
              // 透明度動畫：顯示 1.0 / 隱藏 0.0
              opacity: _show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: AnimatedSlide(
                // 位移動畫：隱藏時往上小移一點（看起來像滑入/滑出）
                offset: _show ? Offset.zero : const Offset(0, -0.06),
                duration: const Duration(milliseconds: 180),
                child: _ShotPopupCard(
                  type: _type,
                  onClose: _closePopup,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 上方 popup 卡片：顯示偵測到的揮拍類型 + 對應圖片 + Close 按鈕
class _ShotPopupCard extends StatelessWidget {
  final String type;
  final VoidCallback onClose;

  const _ShotPopupCard({
    required this.type,
    required this.onClose,
  });

  /// 依 type 回傳對應資產路徑（只能用 assets/... 不能用本機絕對路徑）
  String? _assetForType(String t) {
    const map = <String, String>{
      'Smash': 'assets/poses/Smash.png',
      'Drive': 'assets/poses/Drive.png',
      'Drop': 'assets/poses/Drop.png',
      'Clear': 'assets/poses/Clear.png',
      'Net': 'assets/poses/Net.png',
    };
    return map[t];
  }

  @override
  Widget build(BuildContext context) {
    const accent = Colors.greenAccent;
    const textDark = Color(0xFF111827);
    const greenDark = Color(0xFF166534);
    const greenDarker = Color(0xFF064E3B);

    // ✅ 白底 + 灰邊：符合你要的「白底、乾淨」風格
    const border = Color(0xFFE5E7EB);
    const bg = Colors.white;

    // 取對應動作的圖片路徑
    final assetPath = _assetForType(type);

    // 圖片顯示框大小（雖然原圖可能 128x128，但 UI 顯示縮成 64）
    const double imgBox = 64;

    // 為了縮小仍清楚：用 devicePixelRatio 設定 cacheWidth/cacheHeight
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final int cache = (imgBox * dpr).round().clamp(64, 256);

    return Material(
      // 透明 Material：讓陰影/InkWell 外觀正常，但不強制背景色
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== 標題列：Detected =====
            Row(
              children: const [
                Icon(Icons.sports_tennis, color: greenDark, size: 18),
                SizedBox(width: 8),
                Text(
                  'Detected',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ===== 內容列：圖片 + 文字 + 勾勾 =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 動作圖片（有圓角裁切）
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: imgBox,
                    height: imgBox,
                    color: Colors.white,
                    child: assetPath == null
                    // 找不到對應資產：顯示「不支援」圖示
                        ? const Center(
                      child: Icon(Icons.image_not_supported, color: greenDark),
                    )
                    // 讀取 asset 圖片
                        : Image.asset(
                      assetPath,
                      width: imgBox,
                      height: imgBox,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      cacheWidth: cache,
                      cacheHeight: cache,
                      // 圖片載入失敗時的 fallback
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, color: greenDark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 動作文字（大字顯示）
                Expanded(
                  child: Text(
                    type,
                    style: const TextStyle(
                      color: greenDarker,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      height: 1.0,
                    ),
                  ),
                ),

                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: greenDark),
              ],
            ),

            const SizedBox(height: 12),

            // ===== 關閉按鈕：佔滿寬度 =====
            SizedBox(
              height: 46,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onClose, // 呼叫父層關閉 popup
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF064E3B),
                  side: const BorderSide(color: accent, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.close, color: greenDark),
                label: const Text(
                  'Close',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
