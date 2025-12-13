from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QLabel, QSpinBox, QPushButton, QDialogButtonBox

class ConfigDialog(QDialog):
    def __init__(self, current_pre, current_post, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Label Configuration")
        self.resize(300, 150)
        
        self.pre = current_pre
        self.post = current_post
        
        layout = QVBoxLayout(self)
        
        # Pre Window
        h1 = QHBoxLayout()
        h1.addWidget(QLabel("Pre-Window (frames):"))
        self.spin_pre = QSpinBox()
        self.spin_pre.setRange(10, 200)
        self.spin_pre.setValue(self.pre)
        h1.addWidget(self.spin_pre)
        layout.addLayout(h1)
        
        # Post Window
        h2 = QHBoxLayout()
        h2.addWidget(QLabel("Post-Window (frames):"))
        self.spin_post = QSpinBox()
        self.spin_post.setRange(10, 200)
        self.spin_post.setValue(self.post)
        h2.addWidget(self.spin_post)
        layout.addLayout(h2)
        
        # Info
        self.lbl_info = QLabel(f"Total: {self.pre + self.post} frames")
        self.lbl_info.setStyleSheet("color: gray")
        layout.addWidget(self.lbl_info)
        
        # Connect to update info
        self.spin_pre.valueChanged.connect(self._update_info)
        self.spin_post.valueChanged.connect(self._update_info)
        
        # Buttons
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)
        
    def _update_info(self):
        total = self.spin_pre.value() + self.spin_post.value()
        sec = total * 0.02 # 20ms
        self.lbl_info.setText(f"Total: {total} frames ({sec:.2f} sec)")
        
    def get_values(self):
        return self.spin_pre.value(), self.spin_post.value()
