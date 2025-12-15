import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/ble_service.dart';
import 'services/firebase_service.dart';
import 'services/websocket_service.dart';
import 'services/data_buffer_manager.dart';

import 'providers/home_provider.dart';
import 'ui/home_page.dart';

/// App entrypoint
///
/// 這個 main 負責：
/// 1) 初始化 Flutter engine binding（確保插件/平台通道可用）
/// 2) 初始化 Firebase（FirebaseService 會用到 Realtime Database 等能力）
/// 3) 啟動整個 App（SmartRacketApp）
///
/// 重點：Firebase.initializeApp() 必須在 runApp 之前完成，避免後續服務/Provider 依賴 Firebase 時出現 race condition。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmartRacketApp());
}

/// Application root widget
///
/// 這裡是整個 app 的依賴注入（DI）入口：
/// - 用 MultiProvider 建立「全域服務層」：BLE / Firebase / WebSocket / Buffer
/// - 由 HomeProvider 作為整合層（facade / coordinator），接收上述服務並提供 UI 所需的狀態與操作 API
///
/// 設計目的：
/// - UI（HomePage / pages）只依賴 HomeProvider（或少量底層 service），降低耦合與整合成本
/// - 服務層彼此獨立，方便替換或 mock（測試、切換資料來源、切換連線策略）
class SmartRacketApp extends StatelessWidget {
  const SmartRacketApp({super.key});

  @override
  Widget build(BuildContext context) {
    /// App 主色：全局主題與底部導覽列一致使用（UI identity）
    const accent = Colors.greenAccent;

    return MultiProvider(
      providers: [
        /// BleService 是 ChangeNotifier：提供掃描/連線狀態、最新 IMU 資料、以及 notify stream 等
        /// 放在最底層，讓上層 provider / UI 都能監聽它的狀態變化
        ChangeNotifierProvider(create: (_) => BleService()),

        /// FirebaseService / WebSocketService / DataBufferManager：主要是「服務型物件」
        /// 這裡用 Provider（非 ChangeNotifier）代表它們不一定需要由 UI 直接 listen rebuild
        /// （狀態通常由 HomeProvider 統一對外暴露，或是它們本身透過 stream 提供訊息）
        Provider(create: (_) => FirebaseService()),
        Provider(create: (_) => WebSocketService()),
        Provider(create: (_) => DataBufferManager()),

        /// HomeProvider 是整合層：依賴 4 個服務（BLE/Firebase/WS/Buffer）
        ///
        /// ChangeNotifierProxyProvider4 的語意：
        /// - 當任一依賴 provider rebuild/變動時，會觸發 update()
        /// - update() 裡把依賴注入到 HomeProvider（updateDeps），讓 HomeProvider 永遠持有最新的 service instance
        ///
        /// 注意：這種寫法適合「HomeProvider 本身要維持狀態（不可每次都重建）」的情境，
        /// 所以 create() 先建立一次，update() 只做依賴更新。
        ChangeNotifierProxyProvider4<
            BleService,
            FirebaseService,
            WebSocketService,
            DataBufferManager,
            HomeProvider>(
          create: (_) => HomeProvider(),

          /// update() 會在依賴變動時被呼叫：
          /// - home 可能是既有的 HomeProvider（保持狀態）
          /// - 若 home 為 null（理論上少見），就補建一個，避免注入流程中斷
          /// - updateDeps 將四個 service 注入，讓 HomeProvider 的對外操作能統一調度底層能力
          update: (_, ble, firebase, ws, buffer, home) {
            home ??= HomeProvider();
            home.updateDeps(
              ble: ble,
              firebase: firebase,
              ws: ws,
              bufferMgr: buffer,
            );
            return home;
          },
        ),
      ],

      /// MaterialApp 放在 MultiProvider 之下，讓整棵 widget tree 都能讀取 providers
      /// Theme 統一集中在這裡：視覺一致性與後續調整成本最低
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,

          /// 全域互動回饋（例如 ink ripple / highlight）用 accent 做弱透明，保持品牌色感
          splashColor: accent.withValues(alpha: 0.18),
          highlightColor: accent.withValues(alpha: 0.10),

          /// BottomNavigationBar 視覺規格：
          /// - fixed：五個 tab 仍保持固定寬度
          /// - selectedItemColor：accent
          /// - unselectedItemColor：藍灰，避免搶主視覺
          /// - 背景白色，配合整體清爽 UI
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            type: BottomNavigationBarType.fixed,
            selectedItemColor: accent,
            unselectedItemColor: Colors.blueGrey,
            backgroundColor: Colors.white,
          ),

          /// 以 accent 作為 seed 建立 color scheme（Material 3 推薦方式）
          /// 讓各 component 自動取得一致的色彩階層（primary/secondary/tertiary 等）
          colorScheme: ColorScheme.fromSeed(seedColor: accent),

          /// Dialog 視覺：固定白底 + 關閉 surfaceTint，避免 M3 預設疊色影響一致性
          dialogTheme: const DialogThemeData(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
        ),

        /// HomePage 是 UI Shell（底部導覽/分頁容器等）
        /// 內部再透過 Provider 取得 HomeProvider 與各服務
        home: const HomePage(),
      ),
    );
  }
}
