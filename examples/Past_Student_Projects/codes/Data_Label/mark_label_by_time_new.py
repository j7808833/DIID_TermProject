import pandas as pd
import os
from datetime import datetime

def label_events_in_time_ranges(
    infile1: str,
    outfile: str,
    time_label_ranges: list,
    default_pre_samples: int = 15,
    default_post_samples: int = 14,
    std_multiplier: float = 2.0
):

    # 1. 讀取與合併所有 .xlsx
    all_data = []
    for file in os.listdir(infile1):
        if file.endswith('.xlsx'):
            df0 = pd.read_excel(os.path.join(infile1, file), engine='openpyxl')
            all_data.append(df0)
    df = pd.concat(all_data, ignore_index=True)

    # 2. 時間欄位轉換為 datetime
    df['time'] = pd.to_datetime(df['time'])

    # 3. 確保存在 label 與 interval_flag 欄位
    if 'label' not in df.columns:
        df['label'] = ''
    if 'interval_flag' not in df.columns:
        df['interval_flag'] = ''

    # 4. 計算 gY 門檻
    gy = df['gY']
    threshold = gy.mean() + std_multiplier * gy.std()
    print(f"門檻 = {threshold:.3f} (mean + {std_multiplier}·std)")

    # 5. 找出所有 gY > threshold 的位置
    above = gy > threshold

    # 6. 找出所有連續 True 的區段
    events = []
    start_idx = None
    for i, flag in enumerate(above):
        if flag and start_idx is None:
            start_idx = i
        elif not flag and start_idx is not None:
            events.append((start_idx, i - 1))
            start_idx = None
    if start_idx is not None:
        events.append((start_idx, len(df) - 1))

    print(f"偵測到 {len(events)} 個突增事件段。")

    # 統計資料
    label_stats = {'smash': 0, 'drive': 0}
    label_clean_stats = {'smash': 0, 'drive': 0}

    # 7. 檢查每個事件是否落在指定時間範圍內並標記
    for seg_start, seg_end in events:
        seg = df.loc[seg_start:seg_end, 'gY']
        peak_idx = seg.idxmax()
        peak_time = df.loc[peak_idx, 'time']
        assigned_label = 'other'

        for start_time, end_time, label in time_label_ranges:
            if start_time <= peak_time <= end_time:
                assigned_label = label
                break

        # 根據 label 決定前後筆數
        if assigned_label == 'smash':
            pre_samples = 19
            post_samples = 20
        elif assigned_label == 'drive':
            pre_samples = 20
            post_samples = 19
        else:
            pre_samples = default_pre_samples
            post_samples = default_post_samples

        mark_start = max(0, peak_idx - pre_samples)
        mark_end = min(len(df) - 1, peak_idx + post_samples)

        df.loc[mark_start:mark_end, 'label'] = assigned_label

        # interval 欄位異常檢查
        interval_segment = df.loc[mark_start:mark_end, 'interval']
        if not interval_segment.between(10, 40).all():
            df.loc[mark_start:mark_end, 'interval_flag'] = -1
        else:
            df.loc[mark_start:mark_end, 'interval_flag'] = ''

        if assigned_label in label_stats:
            label_stats[assigned_label] += 1
            if (df.loc[mark_start:mark_end, 'interval_flag'] != -1).all():
                label_clean_stats[assigned_label] += 1

    # 8.1 未標記補上 'other'
    df['label'] = df['label'].replace('', 'other')

    # 8.2 時間段內但非 smash/drive 的改成 'other'
    for start_time, end_time, _ in time_label_ranges:
        mask = (df['time'] >= start_time) & (df['time'] <= end_time)
        df.loc[mask & (~df['label'].isin(['smash', 'drive'])), 'label'] = 'other'

    # 9. 保留毫秒格式時間（Windows 用）
    df['time'] = df['time'].dt.strftime('%Y/%#m/%#d %H:%M:%S.%f').str[:-3]

    # 10. 儲存
    df.to_excel(outfile, index=False, engine='openpyxl')
    print(f"標記完成，已儲存為 {outfile}")

    # 11. 統計結果
    print("\n--- 統計結果 ---")
    for label in ['smash', 'drive']:
        print(f"{label}: 共標記 {label_stats[label]} 段，其中 {label_clean_stats[label]} 段沒有標 -1")


if __name__ == '__main__':
    # 時間區間 + 標籤設定
    time_label_ranges = [
        (pd.to_datetime('2025/5/4 11:00:42.756'), pd.to_datetime('2025/5/4 11:06:46.640'), 'smash'),
        (pd.to_datetime('2025/5/4 11:07:56.537'), pd.to_datetime('2025/5/4 11:23:30.425'), 'smash'),
        (pd.to_datetime('2025/5/4 11:26:20.170'), pd.to_datetime('2025/5/4 11:54:51.497'), 'smash'),
        (pd.to_datetime('2025/5/4 14:08:32.273'), pd.to_datetime('2025/5/4 14:39:57.852'), 'drive'),
        (pd.to_datetime('2025/5/4 14:45:25.088'), pd.to_datetime('2025/5/4 14:48:59.474'), 'drive'),
        (pd.to_datetime('2025/5/4 14:51:34.348'), pd.to_datetime('2025/5/4 15:00:13.137'), 'drive'),
        (pd.to_datetime('2025/5/3 14:17:19.632'), pd.to_datetime('2025/5/3 14:46:10.033'), 'smash'),
        (pd.to_datetime('2025/5/3 15:29:30.841'), pd.to_datetime('2025/5/3 15:51:24.112'), 'drive'),
        (pd.to_datetime('2025/6/4 21:17:28.301'), pd.to_datetime('2025/6/4 21:18:05.757'), 'smash'),
        (pd.to_datetime('2025/6/4 21:19:54.000'), pd.to_datetime('2025/6/4 21:20:54.322'), 'smash'),
        (pd.to_datetime('2025/6/4 21:26:32.143'), pd.to_datetime('2025/6/4 21:38:30.490'), 'smash'),
        (pd.to_datetime('2025/6/4 21:54:06.247'), pd.to_datetime('2025/6/4 21:59:55.494'), 'smash'),
        (pd.to_datetime('2025/6/6 20:13:05.573'), pd.to_datetime('2025/6/6 20:48:02.043'), 'drive'),
        (pd.to_datetime('2025/6/6 20:54:29.976'), pd.to_datetime('2025/6/6 21:23:01.644'), 'drive'),
    ]

    label_events_in_time_ranges(
        infile1="D:/AI/import_full/",
        outfile='D:/AI/import_full/output_combined.xlsx',
        time_label_ranges=time_label_ranges,
        default_pre_samples=19,
        default_post_samples=20,
        std_multiplier=2.0
    )

    #--- 統計結果 ---output_combined
    #smash: 共標記 729 段，其中 725 段沒有標 -1
    #drive: 共標記 647 段，其中 646 段沒有標 -1