# 🔥 Firebase 設定完整教學

## 📋 目錄

1. [Firebase 專案建立](#firebase-專案建立)
2. [Android App 整合](#android-app-整合)
3. [Firestore 資料庫設定](#firestore-資料庫設定)
4. [安全性規則設定](#安全性規則設定)
5. [測試與驗證](#測試與驗證)

---

## Firebase 專案建立

### 步驟 1：建立 Firebase 專案

1. **前往 Firebase Console**
   - 網址：https://console.firebase.google.com/
   - 使用 Google 帳號登入

2. **建立新專案**
   - 點擊「新增專案」或「Add project」
   - 輸入專案名稱：`SmartBadmintonRacket`（或您喜歡的名稱）
   - 點擊「繼續」

3. **設定 Google Analytics（可選）**
   - 可以選擇啟用或停用 Google Analytics
   - 建議：先停用，之後需要時再啟用
   - 點擊「建立專案」

4. **等待專案建立完成**
   - 通常需要幾秒鐘
   - 完成後點擊「繼續」

### 步驟 2：新增 Android App

1. **在專案概覽頁面**
   - 點擊 Android 圖示（或「新增應用程式」→「Android」）

2. **註冊應用程式**
   - **Android 套件名稱**：`com.example.smartbadmintonracket`
     - ⚠️ 重要：必須與您的 `build.gradle` 中的 `applicationId` 完全一致
   - **應用程式暱稱**（可選）：`Smart Badminton Racket`
   - **Debug signing certificate SHA-1**（可選）：暫時可以跳過
   - 點擊「註冊應用程式」

3. **下載設定檔案**
   - 下載 `google-services.json` 檔案
   - ⚠️ 重要：請妥善保管此檔案，不要上傳到公開的 Git 儲存庫

4. **將設定檔案加入專案**
   - 將 `google-services.json` 複製到：
     ```
     APP/android/app/google-services.json
     ```

### 步驟 3：安裝 Firebase SDK

1. **在專案層級的 `build.gradle`（`APP/android/build.gradle`）**

   在 `buildscript` 區塊的 `dependencies` 中加入：
   ```gradle
   buildscript {
       dependencies {
           // ... 其他依賴
           classpath 'com.google.gms:google-services:4.4.0'
       }
   }
   ```

2. **在應用程式層級的 `build.gradle`（`APP/android/app/build.gradle.kts`）**

   在檔案**最上方**加入：
   ```kotlin
   plugins {
       id("com.android.application")
       // ... 其他插件
       id("com.google.gms.google-services")  // 加入這行
   }
   ```

   在 `dependencies` 區塊中加入：
   ```kotlin
   dependencies {
       // ... 其他依賴
       
       // Firebase BOM (Bill of Materials)
       implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
       
       // Firebase Firestore
       implementation("com.google.firebase:firebase-firestore")
       
       // Firebase Analytics (可選)
       implementation("com.google.firebase:firebase-analytics")
   }
   ```

3. **同步專案**
   - 點擊 Android Studio 的「Sync Now」或「Sync Project with Gradle Files」

---

## Android App 整合

### 步驟 1：初始化 Firebase

在 `MainActivity.java` 或 `Application` 類別中初始化 Firebase：

```java
import com.google.firebase.FirebaseApp;
import com.google.firebase.firestore.FirebaseFirestore;

public class MainActivity extends AppCompatActivity {
    private FirebaseFirestore db;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // 初始化 Firebase（通常會自動初始化，但可以明確呼叫）
        FirebaseApp.initializeApp(this);
        
        // 取得 Firestore 實例
        db = FirebaseFirestore.getInstance();
        
        // ... 其他初始化程式碼
    }
}
```

### 步驟 2：建立 FirebaseManager

建立 `APP/android/app/src/main/java/com/example/smartbadmintonracket/firebase/FirebaseManager.java`：

```java
package com.example.smartbadmintonracket.firebase;

import android.util.Log;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.FieldValue;
import com.example.smartbadmintonracket.IMUData;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class FirebaseManager {
    private static final String TAG = "FirebaseManager";
    private FirebaseFirestore db;
    private boolean isRecordingMode = false;
    
    public FirebaseManager() {
        db = FirebaseFirestore.getInstance();
    }
    
    public void setRecordingMode(boolean enabled) {
        this.isRecordingMode = enabled;
        Log.d(TAG, "Recording mode: " + (enabled ? "ON" : "OFF"));
    }
    
    public boolean isRecordingMode() {
        return isRecordingMode;
    }
    
    public void uploadData(IMUData data, String deviceId, String sessionId) {
        if (!isRecordingMode) {
            return;  // 僅在錄製模式下上傳
        }
        
        Map<String, Object> docData = new HashMap<>();
        docData.put("device_id", deviceId);
        docData.put("session_id", sessionId);
        docData.put("timestamp", data.getTimestamp());
        docData.put("accelX", data.getAccelX());
        docData.put("accelY", data.getAccelY());
        docData.put("accelZ", data.getAccelZ());
        docData.put("gyroX", data.getGyroX());
        docData.put("gyroY", data.getGyroY());
        docData.put("gyroZ", data.getGyroZ());
        docData.put("voltage", data.getVoltage());
        docData.put("received_at", System.currentTimeMillis());
        docData.put("calibrated", true);
        docData.put("uploaded_at", FieldValue.serverTimestamp());
        
        db.collection("imu_data")
            .add(docData)
            .addOnSuccessListener(documentReference -> {
                Log.d(TAG, "資料上傳成功: " + documentReference.getId());
            })
            .addOnFailureListener(e -> {
                Log.e(TAG, "資料上傳失敗", e);
                // TODO: 儲存至本地資料庫以便重試
            });
    }
    
    public void uploadBatch(List<IMUData> dataList, String deviceId, String sessionId) {
        if (!isRecordingMode || dataList.isEmpty()) {
            return;
        }
        
        for (IMUData data : dataList) {
            uploadData(data, deviceId, sessionId);
        }
    }
}
```

---

## Firestore 資料庫設定

### 步驟 1：建立 Firestore 資料庫

1. **在 Firebase Console**
   - 點擊左側選單的「Firestore Database」
   - 點擊「建立資料庫」

2. **選擇模式**
   - **測試模式**：適合開發階段，所有讀寫都允許（30 天後會自動鎖定）
   - **正式模式**：需要設定安全性規則
   - 建議：先選擇「測試模式」，之後再設定規則

3. **選擇位置**
   - 選擇最接近您的位置（例如：`asia-east1` 或 `asia-northeast1`）
   - 點擊「啟用」

### 步驟 2：資料結構設計

Firestore 使用集合（Collection）和文件（Document）的結構：

```
firestore/
└── imu_data/                    (Collection)
    ├── {auto_id_1}/             (Document)
    │   ├── device_id: "SmartRacket_001"
    │   ├── session_id: "session_20241123_001"
    │   ├── timestamp: 1234567890
    │   ├── accelX: 0.123
    │   ├── accelY: -0.456
    │   ├── accelZ: 0.789
    │   ├── gyroX: 12.34
    │   ├── gyroY: -56.78
    │   ├── gyroZ: 90.12
    │   ├── voltage: 3.65
    │   ├── received_at: 1234567890123
    │   ├── calibrated: true
    │   └── uploaded_at: Timestamp
    ├── {auto_id_2}/
    └── ...
```

### 步驟 3：手動建立測試資料（可選）

1. **在 Firestore Console**
   - 點擊「開始集合」
   - 集合 ID：`imu_data`
   - 點擊「下一步」

2. **建立第一個文件**
   - 文件 ID：選擇「自動 ID」
   - 新增欄位：
     - `device_id` (string): `SmartRacket_001`
     - `timestamp` (number): `1234567890`
     - `accelX` (number): `0.123`
     - ... 其他欄位
   - 點擊「儲存」

---

## 安全性規則設定

### 測試模式規則（開發階段）

在 Firestore Console →「規則」分頁，使用以下規則：

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 允許所有讀寫（僅用於開發測試）
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

⚠️ **警告**：此規則允許任何人讀寫您的資料庫，僅適用於開發測試！

### 正式模式規則（生產環境）

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // IMU 資料集合
    match /imu_data/{documentId} {
      // 允許寫入（僅限已認證的使用者，或根據需求調整）
      allow write: if request.auth != null;
      
      // 允許讀取（僅限已認證的使用者）
      allow read: if request.auth != null;
    }
  }
}
```

**注意**：如果您的 App 不需要使用者認證，可以根據 `device_id` 或其他條件來限制存取。

---

## 測試與驗證

### 步驟 1：測試連線

在 `MainActivity` 中加入測試程式碼：

```java
public class MainActivity extends AppCompatActivity {
    private FirebaseManager firebaseManager;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // 初始化 Firebase Manager
        firebaseManager = new FirebaseManager();
        
        // 測試連線
        testFirebaseConnection();
    }
    
    private void testFirebaseConnection() {
        FirebaseFirestore db = FirebaseFirestore.getInstance();
        
        // 建立測試資料
        Map<String, Object> testData = new HashMap<>();
        testData.put("test", true);
        testData.put("timestamp", System.currentTimeMillis());
        
        // 寫入測試資料
        db.collection("test")
            .add(testData)
            .addOnSuccessListener(documentReference -> {
                Log.d(TAG, "Firebase 連線成功！文件 ID: " + documentReference.getId());
                Toast.makeText(this, "Firebase 連線成功", Toast.LENGTH_SHORT).show();
            })
            .addOnFailureListener(e -> {
                Log.e(TAG, "Firebase 連線失敗", e);
                Toast.makeText(this, "Firebase 連線失敗: " + e.getMessage(), Toast.LENGTH_LONG).show();
            });
    }
}
```

### 步驟 2：檢查資料

1. **在 Firebase Console**
   - 前往「Firestore Database」
   - 檢查是否有新資料寫入
   - 確認資料格式正確

### 步驟 3：常見問題排除

#### 問題 1：找不到 `google-services.json`

**解決方法**：
- 確認檔案位置：`APP/android/app/google-services.json`
- 確認檔案名稱完全一致（區分大小寫）
- 重新下載並替換檔案

#### 問題 2：Gradle 同步失敗

**解決方法**：
- 確認 `build.gradle` 中的依賴版本正確
- 清理專案：`Build` → `Clean Project`
- 重新建置：`Build` → `Rebuild Project`

#### 問題 3：權限錯誤

**解決方法**：
- 檢查 Firestore 規則是否允許寫入
- 確認 App 的 `applicationId` 與 Firebase 專案中的套件名稱一致

#### 問題 4：網路連線問題

**解決方法**：
- 確認手機/模擬器有網路連線
- 檢查 Firebase 專案是否啟用
- 確認 Firestore 資料庫已建立

---

## 下一步

1. ✅ 完成 Firebase 設定
2. ⏭️ 整合到 Android App
3. ⏭️ 實作批次上傳邏輯
4. ⏭️ 實作離線資料緩存
5. ⏭️ 設定正式環境的安全性規則

---

## 參考資源

- [Firebase 官方文件](https://firebase.google.com/docs)
- [Firestore 文件](https://firebase.google.com/docs/firestore)
- [Android 快速入門](https://firebase.google.com/docs/android/setup)

---

**最後更新**: 2024年11月

