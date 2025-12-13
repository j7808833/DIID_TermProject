import os
import json
import pandas as pd
import numpy as np
from datetime import datetime
from core.constants import LabelType

class LabelManager:
    """
    Handles data slicing and saving labels to JSONL.
    Window Size: 80 frames (60 past + current + 19 future) @ 50Hz
    """
    
    WINDOW_SIZE = 80
    PRE_WINDOW = 60
    POST_WINDOW = 19
    
    def __init__(self, output_dir="labels"):
        self.output_dir = output_dir
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        self._current_session_id = "default_session"
        self._csv_reader = None # Ref to CSV reader for data
        self._sync_manager = None # Ref for full sync details
        
    def set_context(self, csv_reader, sync_manager, session_id=None):
        self._csv_reader = csv_reader
        self._sync_manager = sync_manager
        
        if session_id is None:
            # Auto-generate session ID from CSV start time
            start_ts_str = csv_reader.get_start_timestamp_str()
            # Clean string for filename: 2025/12/06 18:10 -> 20251206_1810
            clean_str = start_ts_str.replace("/", "").replace(":", "").replace(" ", "_").split(".")[0]
            self._current_session_id = clean_str if clean_str else "unknown_session"
        else:
            self._current_session_id = session_id
            
    def get_output_path(self):
        return os.path.join(self.output_dir, f"{self._current_session_id}.jsonl")
        
    def save_label(self, label_type: int, t_csv_ms: float) -> bool:
        """
        Slice data at t_csv_ms and append to JSONL.
        """
        if self._csv_reader is None:
            print("Error: No CSV loaded")
            return False
            
        df = self._csv_reader.get_data()
        if df is None or df.empty:
            return False
            
        # 1. Find nearest index
        # t_csv_ms is current cursor time
        # df is indexed by datetime, but has 't_ms' column
        # Find row closest to t_csv_ms
        # Faster way: t_ms is regular grid? Yes, 20ms.
        # So index = t_csv_ms / 20. But better to use searchsorted for robustness.
        
        # Using searchsorted on t_ms column
        idx = df['t_ms'].searchsorted(t_csv_ms)
        
        if idx >= len(df):
            idx = len(df) - 1
            
        # Check if t_ms at idx is close enough? (Validation)
        # Assuming grid is dense, just perform windowing around idx
        
        start_idx = idx - self.PRE_WINDOW
        end_idx = idx + self.POST_WINDOW + 1 # Slice is exclusive at end
        
        if start_idx < 0 or end_idx > len(df):
            print(f"Error: Window out of bounds. Idx={idx}, Range=[{start_idx}, {end_idx}]")
            return False
            
        # 2. Extract Data
        # Shape: (80, 6) -> accelX,Y,Z, gyroX,Y,Z
        cols = ['accelX', 'accelY', 'accelZ', 'gyroX', 'gyroY', 'gyroZ']
        window_df = df.iloc[start_idx:end_idx][cols]
        
        data_matrix = window_df.values.tolist()
        
        if len(data_matrix) != self.WINDOW_SIZE:
             print(f"Error: Slice length {len(data_matrix)} != {self.WINDOW_SIZE}")
             return False
             
        # 3. Prepare JSON
        record = {
            "session_id": self._current_session_id,
            "label": LabelType.to_str(label_type),
            "label_id": int(label_type),
            "timestamp_csv_ms": t_csv_ms, # Rel
            # "timestamp_real": ... # Could add absolute time string
            "sync_params": self._sync_manager.get_params() if self._sync_manager else {},
            "data": data_matrix
        }
        
        # 4. Append to file
        try:
            with open(self.get_output_path(), 'a', encoding='utf-8') as f:
                f.write(json.dumps(record) + "\n")
            print(f"Label saved: {LabelType.to_str(label_type)} at {t_csv_ms:.0f}ms")
            return True
        except Exception as e:
            print(f"Error writing label: {e}")
            return False

    def undo_last_label(self):
        """Remove last line from JSONL file"""
        path = self.get_output_path()
        if not os.path.exists(path):
            return
            
        try:
            # Read all lines
            with open(path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            if not lines:
                return
                
            # Remove last
            lines = lines[:-1]
            
            # Write back
            with open(path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
                
            print("Undo successful.")
            
        except Exception as e:
            print(f"Error undoing: {e}")
