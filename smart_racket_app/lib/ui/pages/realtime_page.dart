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
  // 伺服器位址輸入：同時支援「ip:port」與完整 ws/wss URL
  final TextEditingController _ipController = TextEditingController();

  // BLE 連線 UX：3 秒連線逾時判定 + 3 秒冷卻避免連點
  Timer? _connectTimeoutTimer;
  Timer? _cooldownTimer;

  bool _connecting = false;
  bool _failed = false;
  bool _cooldown = false;

  // Server 偵測提示的去重：只在 seq 推進時顯示一次 SnackBar
  int _lastDetectSeqSeen = 0;

  /// 快速選單：提供少量「高命中率」的 server 候選，減少手動輸入成本
  /// - 內網常用 ip:port
  /// - Render 版優先 /ws，再試根目錄
  /// - 同時保留 ws:// 前綴版本以兼容不同輸入習慣
  static const List<String> _quickServers = [
    '192.168.0.100:8765',
    '192.168.0.100:8000',
    'wss://diid-termproject-v2.onrender.com/ws',
    'wss://diid-termproject-v2.onrender.com',
    'ws://192.168.0.100:8765',
  ];

  // --- HomeProvider capability adapters ---
  // 這頁面同時相容 v2/v3/v4 provider：用 dynamic 方式做「能力探測」，避免介面不一致造成編譯中斷

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
    // 寫入敏感度與 server，並觸發 provider 端的 detect 流程（若有實作）
    try {
      (p as dynamic).updateSettings(sensitivity, ip);
    } catch (_) {}
  }

  bool _getServerDetectOk(HomeProvider p) {
    try {
      return (p as dynamic).serverDetectOk as bool;
    } catch (_) {
      return false;
    }
  }

  String _getServerDetectMessage(HomeProvider p) {
    try {
      return (p as dynamic).serverDetectMessage as String;
    } catch (_) {
      return '—';
    }
  }

  int _getServerDetectSeq(HomeProvider p) {
    try {
      return (p as dynamic).serverDetectSeq as int;
    } catch (_) {
      return 0;
    }
  }

  bool _getServerDetectBusy(HomeProvider p) {
    try {
      return (p as dynamic).serverDetectBusy as bool;
    } catch (_) {
      return false;
    }
  }

  Future<void> _v3RequestPermissions(HomeProvider p) async {
    // 權限請求：嘗試多個可能的方法名（不同版本 provider 可能存在不同 API）
    bool ok = false;

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

    // 初次進頁：同步 provider 內保存的 serverIp 到輸入框，並記錄當前 detectSeq（避免一進頁就彈舊提示）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<HomeProvider>();
      final ip = _getServerIp(p);
      if (ip.isNotEmpty) _ipController.text = ip;
      _lastDetectSeqSeen = _getServerDetectSeq(p);
    });
  }

  @override
  void dispose() {
    // 釋放計時器與 controller
    _connectTimeoutTimer?.cancel();
    _cooldownTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _handleLinkTap(HomeProvider p) async {
    // BLE 主按鈕：未連線 → 掃描/自動連線；已連線 → 斷線
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

    await p.startScan();

    // 連線逾時：3 秒內未連上則標記失敗並進入冷卻，避免連點造成掃描風暴
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

  String _statusText(HomeProvider p) {
    // BLE 按鈕下方狀態文案：優先顯示 provider 的 connectionStatus
    if (p.isConnected) {
      return p.connectionStatus.isEmpty ? 'Connected' : p.connectionStatus;
    }
    if (_connecting) return 'Connecting...';
    if (_failed) return 'Connection failed';
    return 'Tap to Scan';
  }

  /// Server 狀態列：將偵測狀態映射成固定格式，與 UI 規格一致
  String _serverHeaderText(HomeProvider p) {
    final busy = _getServerDetectBusy(p);
    if (busy) return 'Server: Connecting...';

    final msg = _getServerDetectMessage(p);
    if (msg == 'Detection succeeded') return 'Server: Detection succeeded';
    if (msg == 'Detection failed') return 'Server: Detection failed';

    // 沒有明確訊息時：以成功旗標與是否有填入位址決定顯示
    final ok = _getServerDetectOk(p);
    if (ok) return 'Server: Connected';

    final ip = _getServerIp(p).trim();
    if (ip.isEmpty) return 'Server: Disconnected';

    return 'Server: Disconnected';
  }

  @override
  Widget build(BuildContext context) {
    // 視覺常數：統一此頁色系與按鈕風格
    const accent = Colors.greenAccent;
    const greenDark = Color(0xFF166534);
    const greenDarker = Color(0xFF064E3B);
    const textGrey = Color(0xFF374151);
    const border = Color(0xFFE5E7EB);

    const okGreen = Color(0xFF22C55E);
    const offGrey = Color(0xFF9CA3AF);

    return Consumer<HomeProvider>(
      builder: (_, p, __) {
        final sensitivity = _getSensitivity(p);
        final serverIp = _getServerIp(p);

        // provider 端已有 serverIp 時，輸入框尚空則補上（避免覆蓋使用者正在輸入）
        if (_ipController.text.isEmpty && serverIp.isNotEmpty) {
          _ipController.text = serverIp;
        }

        // BLE 一旦連上：把本地的 failed/cooldown/connect 狀態清掉，避免 UI 邏輯殘留
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

        // Server 偵測狀態（由 provider 更新）：以 seq 做一次性提示
        final detectOk = _getServerDetectOk(p);
        final detectMsg = _getServerDetectMessage(p);
        final detectSeq = _getServerDetectSeq(p);

        // 成功/失敗才提示，且同一個 seq 只提示一次
        if (detectSeq != _lastDetectSeqSeen) {
          _lastDetectSeqSeen = detectSeq;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (detectMsg == 'Detection succeeded' || detectMsg == 'Detection failed') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(detectMsg),
                  duration: const Duration(milliseconds: 1200),
                ),
              );
            }
          });
        }

        final serverHeader = _serverHeaderText(p);

        // 標題色系：採深綠，避免使用警示色造成誤導
        final headerColor = greenDarker;

        return PageBody(
          children: [
            // 六軸即時顯示（加速度/角速度）
            const SixAxisPanel(),
            const SizedBox(height: 78),

            // BLE 掃描/連線主按鈕
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

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Server 狀態：以同一行方式呈現（符合頁面需求）
                  Text(
                    serverHeader,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: headerColor,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Server URL 輸入：左側快速選單、右側狀態勾勾
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SizedBox(
                      height: 52,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: TextField(
                              controller: _ipController,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: 'e.g. 192.168.0.100:8765 or wss://.../ws',
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: border, width: 1.2),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: accent, width: 1.6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 12,
                                ),
                              ),
                              keyboardType: TextInputType.url,
                              onSubmitted: (value) {
                                // Enter 直接儲存並觸發 provider 端的偵測流程
                                final v = value.trim();
                                _updateSettings(p, sensitivity, v);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Saved & detecting...'),
                                    duration: Duration(milliseconds: 900),
                                  ),
                                );
                              },
                            ),
                          ),

                          // 左側：快速選單（固定少量）
                          Positioned(
                            left: 6,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _ServerPresetMenu(
                                items: _quickServers,
                                onSelected: (v) {
                                  _ipController.text = v;
                                  _updateSettings(p, sensitivity, v);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Selected: $v'),
                                      duration: const Duration(milliseconds: 900),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          // 右側：偵測狀態指示（成功才顯示綠色）
                          Positioned(
                            right: 10,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Icon(
                                Icons.check_circle,
                                size: 18,
                                color: detectOk ? okGreen : offGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 權限 / 重新連線：把常用操作集中在同一列
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
                                  // 以當前輸入重新套用設定，等同「儲存 + 觸發偵測」
                                  final v = _ipController.text.trim();
                                  _updateSettings(p, sensitivity, v);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Saved & detecting...'),
                                      duration: Duration(milliseconds: 900),
                                    ),
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

class _ServerPresetMenu extends StatelessWidget {
  const _ServerPresetMenu({
    required this.items,
    required this.onSelected,
  });

  final List<String> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    // 輕量下拉選單：把固定候選塞進 PopupMenu，避免把 UI 做得太重
    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<String>(
        tooltip: '',
        onSelected: onSelected,
        itemBuilder: (_) => items
            .map(
              (s) => PopupMenuItem<String>(
            value: s,
            child: Text(s),
          ),
        )
            .toList(growable: false),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: const Icon(
            Icons.arrow_drop_down_rounded,
            size: 22,
            color: Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

// =================== 圓形掃描按鈕（原樣保留） ===================
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

  // ripple 動畫控制器：connecting/connected 時 repeat，其他狀態停止
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.rippleActive) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ScanCircleButton oldWidget) {
    super.didUpdateWidget(oldWidget);

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

  Widget _ripple(double phase) {
    // 以 controller value 做三圈位相錯開的擴散波紋，提供「掃描/連線中」視覺回饋
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
    // connected 時反轉配色：綠底白 icon；未連線則白底綠 icon
    final bg = widget.connected ? accent : Colors.white;
    final iconColor = widget.connected ? Colors.white : const Color(0xFF166534);

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
                if (widget.rippleActive) ...[
                  _ripple(0.0),
                  _ripple(0.33),
                  _ripple(0.66),
                ],
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
                          color: accent.withValues(alpha: widget.connected ? 0.0 : 1.0),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                            accent.withValues(alpha: widget.connected ? 0.40 : 0.28),
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

        // 狀態膠囊：顯示 BLE 狀態（Connecting/Failed/Connected）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.connected ? const Color(0xFFE8FFF0) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.connected ? const Color(0xFF22C55E) : const Color(0xFFE5E7EB),
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
