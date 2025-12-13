from PySide6.QtWidgets import QWidget, QHBoxLayout, QPushButton, QVBoxLayout, QLabel
from PySide6.QtCore import Signal, Qt
from core.constants import LabelType

class LabelWidget(QWidget):
    """
    Widget containing the 5 Label buttons.
    Emits 'label_triggered(LabelType)' when clicked or hotkey pressed.
    """
    
    label_triggered = Signal(int) # LabelType
    undo_triggered = Signal()
    config_triggered = Signal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()
        
    def _setup_ui(self):
        layout = QHBoxLayout(self)
        
        # Instructions
        lbl_hint = QLabel("Hotkeys: (1)Smash (2)Drive (3)Toss (4)Drop (5)Other (Z)Undo")
        lbl_hint.setStyleSheet("color: gray;")
        layout.addWidget(lbl_hint)
        layout.addStretch()
        
        # Create buttons
        self._buttons = {}
        for l_type in LabelType:
            name = LabelType.to_str(l_type)
            # Create Button with hotkey hint, e.g. "Smash (1)"
            btn = QPushButton(f"{name} ({l_type.value})")
            
            # Simple styling
            color = LabelType.get_color(l_type)
            # btn.setStyleSheet(f"background-color: {color}; font-weight: bold;") 
            # (Background color might look ugly on standard style, keeping simple for now)
            
            # Connect
            # Use default=l_type to capture value in lambda
            btn.clicked.connect(lambda checked=False, val=l_type: self.label_triggered.emit(val))
            
            layout.addWidget(btn)
            self._buttons[l_type] = btn
            
        # Undo Button
        btn_undo = QPushButton("Undo (Z)")
        btn_undo.clicked.connect(self.undo_triggered.emit)
        layout.addWidget(btn_undo)
        
        # Spacer
        layout.addSpacing(10)
        
        # Config Button
        btn_config = QPushButton("⚙ Config")
        btn_config.clicked.connect(self.config_triggered.emit)
        layout.addWidget(btn_config)

    def keyPressEvent(self, event):
        # Allow widget to handle keys if focused, 
        # but usually main window handles global keys.
        super().keyPressEvent(event)
