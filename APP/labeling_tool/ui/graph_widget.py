import pyqtgraph as pg
from PySide6.QtWidgets import QWidget, QVBoxLayout, QCheckBox, QHBoxLayout, QPushButton, QDoubleSpinBox, QLabel
from PySide6.QtCore import Signal, Slot, Qt
from datetime import datetime, timedelta

class TimeAxisItem(pg.AxisItem):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._start_dt = datetime.min

    def set_start_datetime(self, dt):
        self._start_dt = dt

    def tickStrings(self, values, scale, spacing):
        """Convert ms to HH:MM:SS.mmm format (Absolute Time using Naive Datetime)"""
        ret = []
        for x in values:
            if x < 0:
                ret.append("")
                continue
            
            # x is relative ms
            try:
                # Naive Math: Start + Delta
                current_dt = self._start_dt + timedelta(milliseconds=x)
                ret.append(current_dt.strftime("%H:%M:%S.%f")[:-3])
            except Exception:
                ret.append("")
                
        return ret

class GraphWidget(QWidget):
    """
    Widget to display 6-axis IMU data + Magnitude.
    Uses pyqtgraph for high performance.
    """
    
    # Cursor position changed signal (time in ms)
    cursor_changed = Signal(float)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        
        # Configuration
        # Configuration (Global pyqtgraph settings)
        pg.setConfigOption('background', 'k')
        pg.setConfigOption('foreground', 'w')
        
        # Layout
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0,0,0,0)
        
        # Checkbox for Magnitude
        self._controls_layout = QHBoxLayout()
        self._cb_magnitude = QCheckBox("Show Magnitude (合力)")
        self._cb_magnitude.setChecked(True)
        self._cb_magnitude.stateChanged.connect(self._update_plots)
        self._controls_layout.addWidget(self._cb_magnitude)
        
        # Spacer
        self._controls_layout.addSpacing(20)
        
        # Smart Nav
        self._controls_layout.addWidget(QLabel("Peak Threshold(g):"))
        self._spin_thresh = QDoubleSpinBox()
        self._spin_thresh.setRange(0.5, 20.0)
        self._spin_thresh.setValue(3.0)
        self._spin_thresh.setSingleStep(0.5)
        self._controls_layout.addWidget(self._spin_thresh)
        
        self._btn_next_peak = QPushButton("Next Peak (>>)")
        self._btn_next_peak.clicked.connect(self._find_next_peak)
        self._controls_layout.addWidget(self._btn_next_peak)
        
        self._controls_layout.addStretch()
        self._layout.addLayout(self._controls_layout)
        
        # Plots
        # We use a GraphicsLayoutWidget to manage multiple plots aligned vertically
        self._glw = pg.GraphicsLayoutWidget()
        self._layout.addWidget(self._glw)
        
        # Accel Plot (Top)
        self._plot_acc = self._glw.addPlot(row=0, col=0, title="Acceleration (g)")
        self._plot_acc.setLabel('left', 'Accel', units='g')
        self._plot_acc.showGrid(x=True, y=True, alpha=0.3)
        self._plot_acc.addLegend(offset=(10, 10))
        self._plot_acc.setYRange(-16, 16, padding=0.1) # Fixed range for 16g sensor
        self._plot_acc.hideAxis('bottom') # axis hidden for top plot
        
        # Gyro Plot (Bottom)
        time_axis = TimeAxisItem(orientation='bottom')
        self._plot_gyro = self._glw.addPlot(row=1, col=0, title="Gyroscope (dps)", axisItems={'bottom': time_axis})
        self._plot_gyro.setLabel('left', 'Gyro', units='dps')
        # self._plot_gyro.setLabel('bottom', 'Time', units='ms')
        self._plot_gyro.showGrid(x=True, y=True, alpha=0.3)
        self._plot_gyro.addLegend(offset=(10, 10))
        self._plot_gyro.setYRange(-2500, 2500, padding=0.1) # Fixed range for 2000dps sensor
        
        # Link X-axis (Zooming one zooms both)
        self._plot_gyro.setXLink(self._plot_acc)
        
        # Disable Y-axis zooming via mouse wheel on the plot area
        # (This prevents the "out of edge" issue when zooming time)
        self._plot_acc.setMouseEnabled(x=True, y=False)
        self._plot_gyro.setMouseEnabled(x=True, y=False)
        
        # Infinite Lines (Cursors) - Yellow
        self._cursor_acc = pg.InfiniteLine(angle=90, movable=True, pen=pg.mkPen('y', width=2))
        self._cursor_gyro = pg.InfiniteLine(angle=90, movable=True, pen=pg.mkPen('y', width=2))
        
        self._plot_acc.addItem(self._cursor_acc)
        self._plot_gyro.addItem(self._cursor_gyro)
        
        # Connect cursor signals
        self._cursor_acc.sigPositionChanged.connect(self._on_cursor_dragged)
        self._cursor_gyro.sigPositionChanged.connect(self._on_cursor_dragged)
        
        # Data references
        self._t = None # Relative time in ms
        self._start_timestamp = 0 # Absolute unix timestamp in ms
        self._acc = None # [ax, ay, az, amag]
        self._gyro = None # [gx, gy, gz, gmag]
        
        # Curves references
        self._curves_acc = {}
        self._curves_gyro = {}
        
    def set_data(self, df, start_dt=None):
        """
        Set DataFrame from CSVReader.
        Expected columns: t_ms, accelX/Y/Z, gyroX/Y/Z, acc_mag, gyro_mag
        """
        if df is None or df.empty:
            return
            
        self._t = df['t_ms'].values
        self._start_timestamp = 0 # kept for compatibility if needed, but we rely on axis now
        
        # Update Axis with offset
        if start_dt:
            self._plot_gyro.getAxis('bottom').set_start_datetime(start_dt)
        
        self._acc = {
            'x': df['accelX'].values,
            'y': df['accelY'].values,
            'z': df['accelZ'].values,
            'm': df['acc_mag'].values
        }
        
        self._gyro = {
            'x': df['gyroX'].values,
            'y': df['gyroY'].values,
            'z': df['gyroZ'].values,
            'm': df['gyro_mag'].values
        }
        
        self.plot_all()
        
    def plot_all(self):
        """Re-draw all curves."""
        self._plot_acc.clear()
        self._plot_gyro.clear()
        
        # Re-add cursors
        self._plot_acc.addItem(self._cursor_acc)
        self._plot_gyro.addItem(self._cursor_gyro)
        
    def add_marker(self, t_ms, label_type, window_ms=None):
        """
        Add a vertical line and optional range region.
        window_ms: tuple (pre_ms, post_ms)
        """
        # Get color
        from core.constants import LabelType
        color = LabelType.get_color(label_type)
        
        # 1. Range Region (Background) - Draw FIRST so it's behind line
        region_items = []
        if window_ms:
            pre_ms, post_ms = window_ms
            # Faint gray brush: (R, G, B, Alpha) -> (100, 100, 100, 30)
            brush = pg.mkBrush(150, 150, 150, 40)
            
            # Create regions for both plots
            # movable=False to prevent user dragging
            reg_acc = pg.LinearRegionItem(values=[t_ms - pre_ms, t_ms + post_ms], brush=brush, movable=False)
            for l in reg_acc.lines: l.setPen(pg.mkPen(None)) # No border lines
            
            reg_gyro = pg.LinearRegionItem(values=[t_ms - pre_ms, t_ms + post_ms], brush=brush, movable=False)
            for l in reg_gyro.lines: l.setPen(pg.mkPen(None))
            
            self._plot_acc.addItem(reg_acc)
            self._plot_gyro.addItem(reg_gyro)
            region_items = [reg_acc, reg_gyro]
        
        # 2. Key/Center Line
        # Use SolidLine and Width=3 for better visibility
        line_acc = pg.InfiniteLine(pos=t_ms, angle=90, pen=pg.mkPen(color, width=3, style=Qt.SolidLine))
        line_gyro = pg.InfiniteLine(pos=t_ms, angle=90, pen=pg.mkPen(color, width=3, style=Qt.SolidLine))
        
        self._plot_acc.addItem(line_acc)
        self._plot_gyro.addItem(line_gyro)
        
        # Store for Undo as a tuple (flat list of items to remove)
        if not hasattr(self, '_markers'):
            self._markers = []
            
        # marker_entry = ((lines), (regions))
        self._markers.append(((line_acc, line_gyro), tuple(region_items)))
        
    def remove_last_marker(self):
        if hasattr(self, '_markers') and self._markers:
            # Pop entry
            (lines, regions) = self._markers.pop()
            
            # Remove lines
            for l in lines:
                if l in self._plot_acc.items: self._plot_acc.removeItem(l)
                if l in self._plot_gyro.items: self._plot_gyro.removeItem(l)
                
            # Remove regions
            for r in regions:
                if r in self._plot_acc.items: self._plot_acc.removeItem(r)
                if r in self._plot_gyro.items: self._plot_gyro.removeItem(r)

    def plot_all(self):
        """Re-draw all curves."""
        self._plot_acc.clear()
        self._plot_gyro.clear()
        
        # Re-add cursors
        self._plot_acc.addItem(self._cursor_acc)
        self._plot_gyro.addItem(self._cursor_gyro)
        
        # Re-add Markers
        if hasattr(self, '_markers'):
            try:
                for entry in self._markers:
                    # Determine format
                    lines = []
                    regions = []
                    
                    # New Format: tuple of 2 tuples -> ((l1,l2), (r1,r2))
                    # Old Format: tuple of 2 lines -> (l1,l2)
                    
                    if len(entry) == 2 and isinstance(entry[0], tuple):
                         # New Format
                         lines = entry[0]
                         regions = entry[1]
                    else:
                         # Old Format (assume just lines)
                         lines = entry
                         regions = []

                    # Add Regions
                    if regions:
                        if len(regions) >= 2:
                            if regions[0] and regions[0] not in self._plot_acc.items: 
                                self._plot_acc.addItem(regions[0])
                            if regions[1] and regions[1] not in self._plot_gyro.items: 
                                self._plot_gyro.addItem(regions[1])

                    # Add Lines
                    if lines:
                        if len(lines) >= 2:
                             if lines[0] and lines[0] not in self._plot_acc.items: 
                                self._plot_acc.addItem(lines[0])
                             if lines[1] and lines[1] not in self._plot_gyro.items: 
                                self._plot_gyro.addItem(lines[1])
                                
            except Exception as e:
                print(f"Error restoring markers in plot_all: {e}")
        
        if self._t is None:
            return
            
        # Draw Accel
        # X: Red, Y: Green, Z: Blue
        self._plot_acc.plot(self._t, self._acc['x'], pen='r', name='X')
        self._plot_acc.plot(self._t, self._acc['y'], pen='g', name='Y')
        self._plot_acc.plot(self._t, self._acc['z'], pen='b', name='Z')
        
        # Draw Gyro
        self._plot_gyro.plot(self._t, self._gyro['x'], pen='r', name='X')
        self._plot_gyro.plot(self._t, self._gyro['y'], pen='g', name='Y')
        self._plot_gyro.plot(self._t, self._gyro['z'], pen='b', name='Z')
        
        # Draw Magnitude if checked
        if self._cb_magnitude.isChecked():
            # White thick line for magnitude
            self._plot_acc.plot(self._t, self._acc['m'], pen=pg.mkPen('w', width=2), name='Mag')
            self._plot_gyro.plot(self._t, self._gyro['m'], pen=pg.mkPen('w', width=2), name='Mag')
            
        # Set Auto Range
        self._plot_acc.autoRange()
        self._plot_gyro.autoRange()
        
    def _update_plots(self):
        """Refresh plots (e.g. when checkbox changes)."""
        self.plot_all()

    def _on_cursor_dragged(self, line):
        """Sync cursors and emit signal."""
        pos = line.value()
        
        # Block signals to prevent feedback
        self._cursor_acc.blockSignals(True)
        self._cursor_gyro.blockSignals(True)
        
        self._cursor_acc.setValue(pos)
        self._cursor_gyro.setValue(pos)
        
        self._cursor_acc.blockSignals(False)
        self._cursor_gyro.blockSignals(False)
        
        # Emit signal
        self.cursor_changed.emit(pos)

    @Slot(float)
    def set_cursor_position(self, t_ms):
        """Set cursor position from external source (e.g. Video)."""
        # Block signals to prevent feedback
        self._cursor_acc.blockSignals(True)
        self._cursor_gyro.blockSignals(True)
        
        self._cursor_acc.setValue(t_ms)
        self._cursor_gyro.setValue(t_ms)
        
        self._cursor_acc.blockSignals(False)
        self._cursor_gyro.blockSignals(False)
        
        # Auto-Scroll Logic: Keep cursor visible
        view_range = self._plot_acc.viewRange()[0] # [min, max]
        min_x, max_x = view_range
        
        # If cursor is out of view (or very close to edge)
        margin = (max_x - min_x) * 0.05 # 5% margin
        
        if t_ms > (max_x - margin) or t_ms < (min_x + margin):
            # Shift view to center cursor (or at least keep it in view)
            # Let's keep the same zoom level (width)
            width = max_x - min_x
            
            # Simple panning: Center the cursor
            new_min = t_ms - (width / 2)
            new_max = t_ms + (width / 2)
            
            self._plot_acc.setXRange(new_min, new_max, padding=0)
            # Gyro is linked, so it updates automatically
            
    def get_cursor_position(self):
        """Return current cursor position (t_ms)"""
        return self._cursor_acc.value()
            
    def _find_next_peak(self):
        """Find next time point where Acc Mag > Threshold"""
        if self._t is None or self._acc is None:
            return
            
        threshold = self._spin_thresh.value()
        current_t = self._cursor_acc.value()
        
        # BUFFER: Search starting 0.5s (500ms) after current cursor
        # to avoid finding the same peak we are currently standing on.
        start_search_t = current_t + 500
        
        # Helper: Find index of start_search_t
        import numpy as np
        
        # Filter indices where t > start_search_t AND mag > threshold
        mask = (self._t > start_search_t) & (self._acc['m'] > threshold)
        
        # Get indices usually returns a tuple of arrays
        indices = np.where(mask)[0]
        
        if indices.size > 0:
            next_idx = indices[0]
            next_t = self._t[next_idx]
            
            # Move cursor
            self.set_cursor_position(next_t)
            self.cursor_changed.emit(next_t)
            print(f"Jumped to Peak at {next_t:.0f}ms (Mag={self._acc['m'][next_idx]:.2f}g)")
        else:
            print("No more peaks found.")


