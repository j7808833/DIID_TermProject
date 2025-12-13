# SmartRacket Labeling Tool 開發環境設定

本專案使用 **Python 3.10+** 與 **PySide6** (Qt for Python)。
為了確保所有人的開發環境一致，請依照以下步驟設定。

## 1. 安裝 Python
建議使用 **Python 3.10 ~ 3.12** 版本（最穩定）。
*注意：不建議使用 Python 3.13 或 3.14+，因為 PyInstaller 與 PySide6 可能尚未完整支援，容易導致打包失敗。*
- [下載 Python 3.10](https://www.python.org/downloads/release/python-31011/)
- **重要**：安裝時請勾選 **"Add Python to PATH"**。

## 2. 建立虛擬環境 (Virtual Environment)
為了避免套件衝突，請在專案目錄下建立虛擬環境。

**Windows (PowerShell):**
```powershell
# 進入 labeling_tool 目錄
cd d:\DevProjects\Arduino\DIID_TermProject\APP\labeling_tool

# 建立名為 .venv 的虛擬環境
python -m venv .venv

# 啟動虛擬環境 (啟動後命令列前面會有 (.venv) 字樣)
.\.venv\Scripts\Activate.ps1
```
*如果遇到權限錯誤，請先執行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`*

### 多版本 Python 管理 (重要)
若您的電腦同時安裝了 Python 3.14 和 3.11，請使用 Windows 的 `py` 啟動器來指定版本：

```powershell
# 檢查已安裝版本
py --list

# 強制使用 3.11 建立虛擬環境 (前提是您必須先安裝 Python 3.11)
py -3.11 -m venv .venv
```
**注意**：`venv` module 無法自動下載 Python，您必須先去官網下載並安裝 Python 3.11，才能建立 3.11 的虛擬環境。

## 3. 安裝依賴套件
在虛擬環境啟動的狀態下，安裝 `requirements.txt` 中的套件：

```powershell
pip install -r requirements.txt
```

**包含的主要套件：**
- `PySide6`: GUI 框架
- `pyqtgraph`: 高效能繪圖庫 (用於 50Hz IMU 曲線)
- `pandas`: CSV 資料處理
- `scipy`: 訊號處理 (平滑/插值)
- `pyinstaller`: 打包 EXE 工具

## 4. 執行程式 (開發中)
```powershell
# 假設主程式為 main.py
python main.py
```

## 5. 打包成 EXE (給同學使用)
當開發完成後，可以使用以下指令打包成單一資料夾或執行檔：

**打包成資料夾 (推薦，啟動快、好除錯):**
```powershell
pyinstaller --noconfirm --onedir --windowed --name "SmartRacketLabeler" --clean main.py
```
打包好的程式會在 `dist/SmartRacketLabeler/SmartRacketLabeler.exe`。

**打包成單一檔案 (方便傳輸，啟動較慢):**
```powershell
pyinstaller --noconfirm --onefile --windowed --name "SmartRacketLabeler_StandAlone" --clean main.py
```

## 常見問題

## 6. 使用說明 (Phase 1)
目前版本支援讀取 CSV 並顯示波形圖。

1.  **啟動程式**:
    ```powershell
    python main.py
    ```
2.  **載入資料**:
    *   點選選單 `File` -> `Load CSV files...`
    *   選擇一個或多個由 App 產生的 CSV 檔案。
3.  **操作圖表**:
    *   **平移 (Pan)**: 按住滑鼠左鍵拖曳。
    *   **縮放 (Zoom)**: 滾動滑鼠滾輪（僅水平縮放時間軸）。

## 7. 使用說明 (Phase 2 & 3: 影片同步)
本階段加入了 MP4 播放與時間對齊功能。

1.  **載入檔案**:
    *   `File` -> `Load Video...`: 載入 MP4 影片。
    *   `File` -> `Load CSV files...`: 載入對應的感測器數據。
    *   *程式會自動顯示讀取的數據統計資料 (Duration, Quality...)*
2.  **執行同步 (Alignment)**:
    由於影片與感測器啟動時間不同，需手動對齊：
    *   **Step 1**: 在中間的同步面板，**取消勾選** `Lock Sync`（解鎖，使兩者可獨立移動）。
    *   **Step 2**: 播放影片，暫停在**第一球擊球瞬間**。
    *   **Step 3**: 拖曳下方波形圖的黃色游標，對準**第一個波峰**。
    *   **Step 4**: 按下 `Set Start Anchor (A)` 按鈕。
        *   *此時 Offset 數值會更新，代表已記錄時差。*
    *   **Step 5**: **重新勾選** `Lock Sync`。
    *   現在播放影片，波形圖將會完美同步。
3.  **其他操作**:
    *   **漂移修正**: 若影片很長 (10分鐘+)，結尾處可能會有誤差。請重複上述步驟找最後一球，並按下 `Set End Anchor (B)`，系統會自動計算縮放比例 (Scale) 進行修正。
    *   **自動跟隨**: 播放時，若游標超出畫面，波形圖會自動捲動跟隨。

## 8. 使用說明 (Phase 4: 標註系統)
當您完成影片與數據的同步對齊後，即可開始進行標註。

1.  **標註操作**:
    *   播放影片或拖曳時間軸，找到特定的羽球動作（如殺球 Smash）。
    *   暫停或慢速播放，確認動作發生點。
    *   按下對應的按鈕或**鍵盤快捷鍵**：
        *   `1`: **Smash** (殺球)
        *   `2`: **Drive** (抽球)
        *   `3`: **Toss** (挑球)
        *   `4`: **Drop** (吊球)
        *   `5`: **Other** (其他)
2.  **標註結果**:
    *   **視覺回饋**: 波形圖上會出現一條對應顏色的虛線標記。
    *   **檔案儲存**: 程式會自動在與執行檔/原始碼同級的 `labels/` 資料夾中，建立 `.jsonl` 檔案。
    *   **數據格式**: 每次標註會自動擷取當下時間點 **前60筆 (1.2秒) + 後20筆 (0.4秒)**，共 80 筆 (1.6秒) 的 50Hz 數據。
3.  **復原 (Undo)**:
    *   若標錯了，請按介面上的 `Undo (Z)` 按鈕或鍵盤 `Z` 鍵。
    *   這將會刪除最新的一筆 JSONL 紀錄，並移除畫面上的虛線。



