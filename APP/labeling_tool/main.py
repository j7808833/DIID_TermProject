import sys
import os

# Ensure High DPI support
os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "1"

from PySide6.QtWidgets import (QApplication, QMainWindow, QLabel, QVBoxLayout, 
                               QWidget, QFileDialog, QMenuBar, QMenu, QSplitter)
from PySide6.QtGui import QAction
from PySide6.QtCore import Qt
from ui.graph_widget import GraphWidget
from ui.video_player import VideoPlayer
from ui.sync_widget import SyncWidget
from ui.label_widget import LabelWidget
from core.csv_reader import CSVReader
from core.sync_manager import SyncManager
from core.label_manager import LabelManager

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SmartRacket Labeling Tool (Phase 4: Full System)")
        self.resize(1200, 950)
        
        # Components
        self.csv_reader = CSVReader()
        self.sync_manager = SyncManager()
        self.label_manager = LabelManager()
        
        # State
        self.is_sync_locked = True
        self.current_t_csv = 0.0
        
        # Central Widget & Main Layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        self.layout = QVBoxLayout(central_widget)
        
        # Splitter
        self.splitter = QSplitter(Qt.Vertical)
        self.layout.addWidget(self.splitter)
        
        # 1. Video Player (Area A)
        self.video_player = VideoPlayer()
        self.splitter.addWidget(self.video_player)
        
        # 2. Sync Widget (Area B)
        self.sync_widget = SyncWidget()
        self.layout.addWidget(self.sync_widget)
        
        # 3. Graph Widget (Area C)
        self.graph_widget = GraphWidget()
        self.splitter.addWidget(self.graph_widget)

        # 4. Label Widget (Area D - Bottom)
        self.label_widget = LabelWidget()
        self.layout.addWidget(self.label_widget)
        
        # Set initial sizes
        self.splitter.setSizes([450, 450])
        
        # Setup Menu
        self._setup_menu()
        
        # Connect Signals
        self._connect_signals()
        
    def _connect_signals(self):
        # Video -> Graph
        self.video_player.position_changed.connect(self._on_video_position_changed)
        
        # Graph -> Video
        self.graph_widget.cursor_changed.connect(self._on_graph_cursor_changed)
        
        # Sync Widget Signals
        self.sync_widget.set_anchor_a.connect(self._on_set_anchor_a)
        self.sync_widget.set_anchor_b.connect(self._on_set_anchor_b)
        self.sync_widget.reset_sync.connect(self._on_reset_sync)
        self.sync_widget.lock_toggled.connect(self._on_lock_toggled)
        
        # Label Signals
        self.label_widget.label_triggered.connect(self._on_label_triggered)
        self.label_widget.undo_triggered.connect(self._on_undo_triggered)
        self.label_widget.config_triggered.connect(self._on_config_triggered)
        
    def _on_config_triggered(self):
        from ui.config_dialog import ConfigDialog
        dialog = ConfigDialog(self.label_manager.PRE_WINDOW, self.label_manager.POST_WINDOW, self)
        if dialog.exec():
            pre, post = dialog.get_values()
            self.label_manager.set_window_size(pre, post)
            
    def _on_label_triggered(self, label_type):
        """Handle Label Button Click or Hotkey"""
        # Force get current cursor pos from Graph for WYSIWYG
        t_csv = self.graph_widget.get_cursor_position()
        
        # Save Label
        success = self.label_manager.save_label(label_type, t_csv)
        
        if success:
            # 1. Show Marker on Graph
            # Calculate window ms (20ms per frame)
            pre_ms = self.label_manager.PRE_WINDOW * 20
            post_ms = self.label_manager.POST_WINDOW * 20
            self.graph_widget.add_marker(t_csv, label_type, window_ms=(pre_ms, post_ms))
            
            # 2. Flash status or log
            print(f"Labeled: {label_type} at {t_csv}")
        else:
            # Show error (e.g. out of bounds)
            from PySide6.QtWidgets import QMessageBox
            QMessageBox.warning(self, "Label Failed", "Could not save label (Out of bounds?)")

    def _on_undo_triggered(self):
        self.label_manager.undo_last_label()
        # Remove last marker from graph (Need to implement remove_last_marker in GraphWidget)
        self.graph_widget.remove_last_marker()
        
    def keyPressEvent(self, event):
        # Handle hotkeys globally if widget doesn't catch them
        # 49 = '1', 53 = '5'
        key = event.key()
        if Qt.Key_1 <= key <= Qt.Key_5:
            label_type = key - Qt.Key_0 # 1..5
            self._on_label_triggered(label_type)
        elif key == Qt.Key_Z:
            self._on_undo_triggered()
        else:
            super().keyPressEvent(event)
            
    def _on_video_position_changed(self, t_vid):
        if not self.is_sync_locked:
            return
            
        # Video Time (ms) -> CSV Time (ms)
        t_csv = self.sync_manager.video_to_csv(t_vid)
        self.graph_widget.set_cursor_position(t_csv)
        
    def _on_graph_cursor_changed(self, t_csv):
        self.current_t_csv = t_csv
        if not self.is_sync_locked:
            return
            
        # CSV Time (ms) -> Video Time (ms)
        # Update only if video is paused to avoid fighting
        if not self.video_player.is_playing():
            t_vid = self.sync_manager.csv_to_video(t_csv)
            self.video_player.set_position(int(t_vid))

    def _on_lock_toggled(self, locked):
        self.is_sync_locked = locked
        print(f"Sync Lock: {locked}")
        
    def _on_set_anchor_a(self):
        # Get current positions
        t_vid = self.video_player._player.position() # Access internal player or add getter
        t_csv = self.current_t_csv
        
        print(f"Setting Anchor A: Vid={t_vid}, CSV={t_csv}")
        self.sync_manager.set_start_anchor(t_vid, t_csv)
        
        self.sync_widget.update_anchor_label('A', t_vid, t_csv)
        self._update_sync_status()
        
        # Auto-lock after setting? Maybe optional.
        # self.sync_widget._chk_lock.setChecked(True)
        
    def _on_set_anchor_b(self):
        t_vid = self.video_player._player.position()
        t_csv = self.current_t_csv
        
        print(f"Setting Anchor B: Vid={t_vid}, CSV={t_csv}")
        self.sync_manager.set_end_anchor(t_vid, t_csv)
        
        self.sync_widget.update_anchor_label('B', t_vid, t_csv)
        self._update_sync_status()
        
    def _on_reset_sync(self):
        self.sync_manager = SyncManager() # Reset
        self.sync_widget.clear_anchors()
        self._update_sync_status()
        
    def _update_sync_status(self):
        params = self.sync_manager.get_params()
        self.sync_widget.update_status(params['offset_ms'], params['scale_factor'])
        
        # Refresh current view
        t_vid = self.video_player._player.position()
        t_csv = self.sync_manager.video_to_csv(t_vid)
        self.graph_widget.set_cursor_position(t_csv)
            
    def _setup_menu(self):
        menubar = self.menuBar()
        file_menu = menubar.addMenu("File")
        
        # Load Video Action
        load_video_action = QAction("Load Video...", self)
        load_video_action.triggered.connect(self._load_video)
        file_menu.addAction(load_video_action)
        
        # Load CSV Action
        load_csv_action = QAction("Load CSV files...", self)
        load_csv_action.triggered.connect(self._load_csv_files)
        file_menu.addAction(load_csv_action)
        
        file_menu.addSeparator()
        
        # Load Labels Action
        load_labels_action = QAction("Load Labels...", self)
        load_labels_action.triggered.connect(self._load_labels)
        file_menu.addAction(load_labels_action)
        
    def _load_video(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Open Video File", "", "Video Files (*.mp4 *.avi *.mov)"
        )
        if file_path:
            print(f"Loading video: {file_path}")
            self.video_player.load_video(file_path)
            
    def _load_labels(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Load Labels (JSONL)", "labels", "JSONL Files (*.jsonl);;All Files (*)"
        )
        if not file_path:
            return
            
        print(f"Loading labels from: {file_path}")
        labels = self.label_manager.load_labels(file_path)
        
        if labels:
            count = 0
            # Get current config for visualization
            pre_ms = self.label_manager.PRE_WINDOW * 20
            post_ms = self.label_manager.POST_WINDOW * 20
            
            for t_ms, l_type in labels:
                self.graph_widget.add_marker(t_ms, l_type, window_ms=(pre_ms, post_ms))
                count += 1
            print(f"Resorted {count} markers.")
            
            from PySide6.QtWidgets import QMessageBox
            QMessageBox.information(self, "Load Labels", f"Successfully loaded {count} labels.")
        else:
             print("No labels found or error.")
        
    def _load_csv_files(self):
        file_paths, _ = QFileDialog.getOpenFileNames(
            self, "Open CSV Files", "", "CSV Files (*.csv)"
        )
        
        if file_paths:
            print(f"Loading {len(file_paths)} files...")
            success = self.csv_reader.load_files(file_paths)
            if success:
                print("Load successful. Plotting...")
                df = self.csv_reader.get_data()
                # Get start datetime (Naive)
                start_dt = self.csv_reader.get_start_datetime() 
                self.graph_widget.set_data(df, start_dt)
                
                # Show Stats
                stats = self.csv_reader.get_stats()
                
                # Init Label Manager
                self.label_manager.set_context(self.csv_reader, self.sync_manager)
                
                from PySide6.QtWidgets import QMessageBox
                msg = (f"Loaded successfully!\n\n"
                       f"Duration: {stats.get('duration_str', '?')}\n"
                       f"Expected (50Hz): {stats.get('expected_samples', 0)}\n"
                       f"Raw Count: {stats.get('raw_samples', 0)}\n"
                       f"Missing/Drop Rate: {stats.get('missing_ratio', 0):.2%}")
                QMessageBox.information(self, "Data Info", msg)
            else:
                print("Load failed.")

def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
