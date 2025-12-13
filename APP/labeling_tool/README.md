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
- **Qt Platform 錯誤**: 確保在虛擬環境中執行。
- **PyQtGraph 字體模糊**: 若在高解析度螢幕上，程式碼需加入 `os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "1"`。
