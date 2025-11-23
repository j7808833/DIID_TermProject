# 🔥 Firebase 設定步驟

## 步驟 1：建立 Firebase 專案

1. **前往 Firebase Console**
   - 網址：https://console.firebase.google.com/
   - 使用 Google 帳號登入

2. **建立新專案**
   - 點擊「新增專案」或「Add project」
   - 專案名稱：`SmartBadmintonRacket`（或您喜歡的名稱）
   - 點擊「繼續」

3. **設定 Google Analytics（可選）**
   - 建議先停用，之後需要時再啟用
   - 點擊「建立專案」

4. **等待專案建立完成**
   - 完成後點擊「繼續」

## 步驟 2：新增 Android App

1. **在專案概覽頁面**
   - 點擊 Android 圖示（或「新增應用程式」→「Android」）

2. **註冊應用程式**
   - **Android 套件名稱**：`com.example.smartbadmintonracket`
     - ⚠️ **重要**：必須與 `app/build.gradle.kts` 中的 `applicationId` 完全一致
   - **應用程式暱稱**（可選）：`Smart Badminton Racket`
   - **Debug signing certificate SHA-1**（可選）：暫時可以跳過
   - 點擊「註冊應用程式」

3. **下載設定檔案**
   - 下載 `google-services.json` 檔案
   - ⚠️ **重要**：請妥善保管此檔案，不要上傳到公開的 Git 儲存庫

4. **將設定檔案加入專案**
   - 將 `google-services.json` 複製到：
     ```
     APP/android/app/google-services.json
     ```

## 步驟 3：建立 Firestore 資料庫

1. **在 Firebase Console**
   - 點擊左側選單的「Firestore Database」
   - 點擊「建立資料庫」

2. **選擇模式**
   - 選擇「測試模式」（適合開發階段）
   - 點擊「下一步」

3. **選擇位置**
   - 選擇最接近您的位置（例如：`asia-east1` 或 `asia-northeast1`）
   - 點擊「啟用」

## 步驟 4：驗證設定

1. **確認檔案位置**
   - 確認 `APP/android/app/google-services.json` 檔案存在

2. **同步 Gradle**
   - 在 Android Studio 中點擊「Sync Now」或「Sync Project with Gradle Files」

3. **執行測試**
   - 執行 App
   - 在 MainActivity 中會自動執行 Firebase 連線測試
   - 檢查 Logcat 是否有「Firebase 連線測試成功」的訊息

4. **檢查 Firestore**
   - 在 Firebase Console → Firestore Database
   - 檢查是否有測試資料寫入

## 常見問題

### 問題 1：找不到 `google-services.json`

**解決方法**：
- 確認檔案位置：`APP/android/app/google-services.json`
- 確認檔案名稱完全一致（區分大小寫）
- 重新下載並替換檔案

### 問題 2：Gradle 同步失敗

**解決方法**：
- 確認 `build.gradle.kts` 中的依賴版本正確
- 清理專案：`Build` → `Clean Project`
- 重新建置：`Build` → `Rebuild Project`

### 問題 3：權限錯誤

**解決方法**：
- 檢查 Firestore 規則是否允許寫入（測試模式應該允許）
- 確認 App 的 `applicationId` 與 Firebase 專案中的套件名稱一致

---

**完成後請告知，我們將繼續下一步！**

