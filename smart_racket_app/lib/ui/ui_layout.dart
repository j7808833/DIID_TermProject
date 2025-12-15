import 'package:flutter/widgets.dart';

/// 頁面左右固定內距（用同一個常數，確保整個 App 版面一致）
const double kPageHPad = 36;

/// 統一的頁面 Padding：
/// - left/right：kPageHPad（維持視覺對齊）
/// - top：16（頁首不要太擠）
/// - bottom：24（預留底部手勢區/按鈕空間）
const EdgeInsets kPagePadding = EdgeInsets.fromLTRB(
  kPageHPad, 16, kPageHPad, 24,
);

/// 常用間距：小（元件之間的基本空隙）
const double kGapS = 12;

/// 常用間距：中（區塊之間的段落空隙）
const double kGapM = 18;

/// 常用間距：大（主要區塊/段落之間的明顯分隔）
const double kGapL = 28;
