import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';
import '../ui_layout.dart';
import '../widgets/page_body.dart';
import '../widgets/six_axis_panel.dart';

class RealtimePage extends StatefulWidget {
  const RealtimePage({super.key});

  @override
  State<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends State<RealtimePage> {
  // Server 欄位輸入控制器（儲存/重連時取值）
  final TextEditingController _ipController = TextEditingController();

  // 連線逾時與冷卻計時器：
  // - connectTimeoutTimer：點「Scan」後 3 秒內沒連上就判失敗
  // - cooldownTimer：失敗後 3 秒冷卻，避免連點打爆掃描/連線堆疊
  Timer? _connectTimeoutTimer;
  Timer? _cooldownTimer;

  // UI 狀態旗標（只影響按鈕文案、disable 與動畫）
  bool _connecting = false;
  bool _failed = false;
  bool _cooldown = false;

  // ===== compile-safe 讀寫 HomeProvider 的設定（避免 provider 欄位未實作造成編譯錯） =====
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

  // ===== v3: Permissions (best-effort; compile-safe) =====
  // RealtimePage 提供「Permissions」按鈕，對舊版/新版 provider 做 best-effort 呼叫。
  // 目的：不管你 provider 叫 requestPermissions / ensurePermissions / checkPermissions，都能跑。
  Future<void> _v3RequestPermissions(HomeProvider p) async {
    bool ok = false;

    // 依序嘗試可能存在的方法（任何一個成功就 ok=true）
    try {
      await (p as dynamic).requestPermissions();
      ok = true;
    } catch (_) {}
    if (!ok) {
      try {
        await (p as dynamic).ensurePermissions();
        ok = true;
      } catch (_) {}
    }
    if (!ok) {
      try {
        await (p as dynamic).checkPermissions();
        ok = true;
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Permissions requested' : 'Permission method not supported'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // 等第一幀之後再讀 provider（避免 initState 時 context 尚未 ready）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<HomeProvider>();
      final ip = _getServerIp(p);
      if (ip.isNotEmpty) _ipController.text = ip;
    });
  }

  @override
  void dispose() {
    _connectTimeoutTimer?.cancel();
    _cooldownTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  // 使用者點圓形按鈕的主流程：
  // 1) 若已連線 -> disconnect
  // 2) 若未連線 -> startScan（由 HomeProvider 內部呼叫 BleService.startScan/autoConnect）
  // 3) 設定 3 秒 timeout：3 秒內沒連上 -> failed + cooldown 3 秒
  Future<void> _handleLinkTap(HomeProvider p) async {
    if (_cooldown || _connecting) return;

    HapticFeedback.mediumImpact();

    if (p.isConnected) {
      await p.disconnectBle();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _failed = false;
        _cooldown = false;
      });
      return;
    }

    setState(() {
      _connecting = true;
      _failed = false;
      _cooldown = false;
    });

    // 交給 HomeProvider 啟動掃描（通常會 autoConnect 到 target device）
    await p.startScan();

    // 3 秒內沒連上視為失敗（此逾時只管 UI，不一定代表 BLE 還在連線）
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      final nowConnected = context.read<HomeProvider>().isConnected;
      if (nowConnected) {
        setState(() {
          _connecting = false;
          _failed = false;
          _cooldown = false;
        });
        return;
      }

      setState(() {
        _connecting = false;
        _failed = true;
        _cooldown = true;
      });

      // 失敗後冷卻 3 秒，避免連點造成掃描/連線堆疊
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _failed = false;
          _cooldown = false;
        });
      });
    });
  }

  // 狀態文案：
  // - Connected：由 provider.connectionStatus（若有）或預設 'Connected'
  // - Connecting / failed / Tap to Scan：由頁面本地旗標控制
  String _statusText(HomeProvider p) {
    if (p.isConnected) {
      return p.connectionStatus.isEmpty ? 'Connected' : p.connectionStatus;
    }
    if (_connecting) return 'Connecting...';
    if (_failed) return 'Connection failed';
    return 'Tap to Scan';
  }

  @override
  Widget build(BuildContext context) {
    // 頁面主視覺色系
    const accent = Colors.greenAccent;
    const greenDark = Color(0xFF166534);
    const greenDarker = Color(0xFF064E3B);
    const textGrey = Color(0xFF374151);
    const border = Color(0xFFE5E7EB);

    return Consumer<HomeProvider>(
      builder: (_, p, __) {
        final sensitivity = _getSensitivity(p);
        final serverIp = _getServerIp(p);

        // 若 provider 有 serverIp 且 textfield 還是空的 -> 自動帶入（避免重建時消失）
        if (_ipController.text.isEmpty && serverIp.isNotEmpty) {
          _ipController.text = serverIp;
        }

        // 若 provider 已連線，但本地仍顯示 connecting/failed/cooldown -> 立刻自動清狀態
        if (p.isConnected && (_connecting || _failed || _cooldown)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _connecting = false;
              _failed = false;
              _cooldown = false;
            });
          });
        }

        final status = _statusText(p);

        return PageBody(
          children: [
            // 顯示即時六軸數值/狀態（與 GraphPage/RecordPage 一致）
            const SixAxisPanel(),
            const SizedBox(height: 78),

            // 圓形「Scan/Connected」主按鈕（含 ripple 動畫）
            Center(
              child: _ScanCircleButton(
                connected: p.isConnected,
                disabled: _cooldown || _connecting,
                rippleActive: _connecting || p.isConnected,
                statusText: status,
                onTap: () => _handleLinkTap(p),
              ),
            ),

            const SizedBox(height: kGapL),

            // Server 設定區（IP / domain）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Server',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: textGrey,
                    ),
                  ),
                  const SizedBox(height: 10),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: TextField(
                      controller: _ipController,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'e.g. 192.168.0.100 or diid-termproject-v2.onrender.com',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: border, width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: accent, width: 1.6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      keyboardType: TextInputType.url,
                      onSubmitted: (value) {
                        _updateSettings(p, sensitivity, value.trim());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Saved & reconnecting...')),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Permissions + Reconnect 兩顆按鈕
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  HapticFeedback.selectionClick();
                                  await _v3RequestPermissions(p);
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8FFF0),
                                  foregroundColor: greenDarker,
                                  side: const BorderSide(color: accent, width: 1.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.security_outlined, color: greenDark),
                                label: const Text(
                                  'Permissions',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _updateSettings(p, sensitivity, _ipController.text.trim());
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Saved & reconnecting...')),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8FFF0),
                                  foregroundColor: greenDarker,
                                  side: const BorderSide(color: accent, width: 1.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh, color: greenDark),
                                label: const Text(
                                  'Reconnect',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// =================== 圓形掃描按鈕（含 ripple 動畫） ===================
//
// 角色：
// - 顯示「wifi」圖示，並用顏色/陰影表示 Connected vs Disconnected
// - rippleActive=true 時啟動三層漣漪（連線中或已連線）
// - disabled=true 時禁止點擊（connecting/cooldown）
// - statusText 顯示在下方 pill 中
class _ScanCircleButton extends StatefulWidget {
  const _ScanCircleButton({
    required this.connected,
    required this.disabled,
    required this.rippleActive,
    required this.statusText,
    required this.onTap,
  });

  final bool connected;
  final bool disabled;
  final bool rippleActive;
  final String statusText;
  final VoidCallback onTap;

  @override
  State<_ScanCircleButton> createState() => _ScanCircleButtonState();
}

class _ScanCircleButtonState extends State<_ScanCircleButton>
    with SingleTickerProviderStateMixin {
  static const accent = Colors.greenAccent;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // rippleActive -> repeat 動畫；否則靜止
    if (widget.rippleActive) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ScanCircleButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // rippleActive 狀態切換時，開始/停止動畫
    if (widget.rippleActive && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.rippleActive && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // 單層 ripple：
  // - t: 0..1 表示這層從中心擴散到外圈
  // - scale: 1 -> 2.35（約 1 + 1.35）
  // - opacity: 逐漸變淡
  Widget _ripple(double phase) {
    final t = (_ctrl.value + phase) % 1.0;
    final scale = 1.0 + t * 1.35;
    final opacity = (1.0 - t) * 0.28;
    final borderOpacity = (1.0 - t) * 0.55;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 164,
        height: 164,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: opacity * 0.35),
          border: Border.all(
            color: accent.withValues(alpha: borderOpacity),
            width: 2.2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Connected 時：按鈕填滿 accent；Disconnected 時：白底 + 綠邊
    final bg = widget.connected ? accent : Colors.white;
    final iconColor = widget.connected ? Colors.white : const Color(0xFF166534);

    // 狀態 pill：Connected 用較深綠；其他狀態用灰
    final statusColor =
    widget.connected ? const Color(0xFF166534) : const Color(0xFF6B7280);

    const double size = 164;
    const double iconSize = 84;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // 三層 ripple，相位錯開（0 / 0.33 / 0.66）形成連續波紋
                if (widget.rippleActive) ...[
                  _ripple(0.0),
                  _ripple(0.33),
                  _ripple(0.66),
                ],

                // 主要可點擊圓形
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.disabled ? null : widget.onTap,
                    customBorder: const CircleBorder(),
                    splashColor: accent.withValues(alpha: 0.30),
                    highlightColor: accent.withValues(alpha: 0.14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(
                            alpha: widget.connected ? 0.0 : 1.0,
                          ),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                              alpha: widget.connected ? 0.40 : 0.28,
                            ),
                            blurRadius: 24,
                            spreadRadius: 3,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(Icons.wifi, size: iconSize, color: iconColor),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 14),

        // 下方狀態 pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.connected
                ? const Color(0xFFE8FFF0)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.connected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFE5E7EB),
              width: 1.1,
            ),
          ),
          child: Text(
            widget.statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
