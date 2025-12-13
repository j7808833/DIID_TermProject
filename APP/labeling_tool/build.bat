@echo off
echo Cleaning up previous builds...
rd /s /q build
rd /s /q dist

echo Building SmartRacket Labeling Tool...
python -m PyInstaller --noconfirm --onedir --windowed --name "SmartRacketLabelingTool" ^
    --hidden-import="colorsys" ^
    --hidden-import="PySide6.QtXml" ^
    --collect-all "pyqtgraph" ^
    main.py

echo.
echo Build Complete!
echo Executable is located in: dist\SmartRacketLabelingTool\SmartRacketLabelingTool.exe
pause
