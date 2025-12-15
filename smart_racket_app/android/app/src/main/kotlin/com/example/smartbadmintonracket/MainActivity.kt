// android/app/src/main/kotlin/com/example/smartbadmintonracket/MainActivity.kt
package com.example.smartbadmintonracket

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode

class MainActivity : FlutterActivity() {

    // ✅ 避免部分 Adreno/qdgralloc 裝置在 SurfaceView 路徑下出現崩潰/黑屏/當機
    // 會改用 TextureView（通常比 SurfaceView 更穩）
    override fun getRenderMode(): RenderMode = RenderMode.texture

    // ✅ 保持預設不透明（更穩）
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.opaque
}
