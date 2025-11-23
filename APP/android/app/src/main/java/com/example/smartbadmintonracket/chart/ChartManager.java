package com.example.smartbadmintonracket.chart;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.example.smartbadmintonracket.IMUData;
import com.github.mikephil.charting.charts.LineChart;
import com.github.mikephil.charting.components.XAxis;
import com.github.mikephil.charting.components.YAxis;
import com.github.mikephil.charting.data.Entry;
import com.github.mikephil.charting.data.LineData;
import com.github.mikephil.charting.data.LineDataSet;
import com.github.mikephil.charting.formatter.ValueFormatter;

import java.util.ArrayList;
import java.util.List;

/**
 * 圖表管理器
 * 負責管理 6 個獨立的圖表（加速度 X/Y/Z，角速度 X/Y/Z）
 * 實現資料降採樣（50Hz → 10Hz）和資料緩衝（維持 5 秒資料）
 */
public class ChartManager {
    private static final String TAG = "ChartManager";
    
    // 圖表配置
    private static final int MAX_DATA_POINTS = 50;  // 5 秒 * 10Hz = 50 點
    private static final long UPDATE_INTERVAL_MS = 100;  // 每 100ms 更新一次（10Hz）
    private static final int DOWNSAMPLE_FACTOR = 5;  // 降採樣因子：50Hz / 5 = 10Hz
    
    // 圖表視圖
    private LineChart accelXChart;
    private LineChart accelYChart;
    private LineChart accelZChart;
    private LineChart gyroXChart;
    private LineChart gyroYChart;
    private LineChart gyroZChart;
    
    // 資料緩衝區（用於降採樣）
    private List<IMUData> dataBuffer = new ArrayList<>();
    
    // 圖表資料集
    private LineDataSet accelXDataSet;
    private LineDataSet accelYDataSet;
    private LineDataSet accelZDataSet;
    private LineDataSet gyroXDataSet;
    private LineDataSet gyroYDataSet;
    private LineDataSet gyroZDataSet;
    
    // 更新處理器
    private Handler updateHandler = new Handler(Looper.getMainLooper());
    private Runnable updateRunnable;
    private boolean isUpdating = false;
    
    /**
     * 初始化圖表管理器
     * @param charts 6 個 LineChart 視圖（順序：accelX, accelY, accelZ, gyroX, gyroY, gyroZ）
     */
    public ChartManager(LineChart... charts) {
        if (charts.length != 6) {
            throw new IllegalArgumentException("需要 6 個圖表視圖");
        }
        
        accelXChart = charts[0];
        accelYChart = charts[1];
        accelZChart = charts[2];
        gyroXChart = charts[3];
        gyroYChart = charts[4];
        gyroZChart = charts[5];
        
        initializeCharts();
        setupUpdateRunnable();
    }
    
    /**
     * 初始化所有圖表
     */
    private void initializeCharts() {
        // 初始化加速度圖表
        initializeChart(accelXChart, "加速度 X (g)", 0xFF2196F3, -20f, 20f);
        initializeChart(accelYChart, "加速度 Y (g)", 0xFF4CAF50, -20f, 20f);
        initializeChart(accelZChart, "加速度 Z (g)", 0xFF9C27B0, -20f, 20f);
        
        // 初始化角速度圖表
        initializeChart(gyroXChart, "角速度 X (dps)", 0xFFFF9800, -2500f, 2500f);
        initializeChart(gyroYChart, "角速度 Y (dps)", 0xFFF44336, -2500f, 2500f);
        initializeChart(gyroZChart, "角速度 Z (dps)", 0xFF00BCD4, -2500f, 2500f);
    }
    
    /**
     * 初始化單個圖表
     */
    private void initializeChart(LineChart chart, String label, int color, float yMin, float yMax) {
        // 基本設定
        chart.setTouchEnabled(false);  // 禁用觸控（避免干擾）
        chart.setDragEnabled(false);
        chart.setScaleEnabled(false);
        chart.setPinchZoom(false);
        chart.setDoubleTapToZoomEnabled(false);
        chart.getDescription().setEnabled(false);  // 隱藏描述
        chart.getLegend().setEnabled(false);  // 隱藏圖例
        
        // X 軸設定
        XAxis xAxis = chart.getXAxis();
        xAxis.setPosition(XAxis.XAxisPosition.BOTTOM);
        xAxis.setDrawGridLines(true);
        xAxis.setGridColor(0xFFE0E0E0);
        xAxis.setTextSize(10f);
        xAxis.setLabelCount(6, true);  // 顯示 6 個標籤
        xAxis.setAxisMinimum(0f);
        xAxis.setAxisMaximum(5f);  // 5 秒範圍
        xAxis.setValueFormatter(new ValueFormatter() {
            @Override
            public String getFormattedValue(float value) {
                return String.format("%.1fs", value);
            }
        });
        
        // Y 軸設定
        YAxis leftAxis = chart.getAxisLeft();
        leftAxis.setDrawGridLines(true);
        leftAxis.setGridColor(0xFFE0E0E0);
        leftAxis.setTextSize(10f);
        leftAxis.setAxisMinimum(yMin);
        leftAxis.setAxisMaximum(yMax);
        leftAxis.setLabelCount(5, true);
        
        YAxis rightAxis = chart.getAxisRight();
        rightAxis.setEnabled(false);  // 禁用右側 Y 軸
        
        // 創建資料集
        LineDataSet dataSet = new LineDataSet(null, label);
        dataSet.setColor(color);
        dataSet.setLineWidth(2f);
        dataSet.setDrawCircles(false);  // 不顯示圓點（提高性能）
        dataSet.setDrawValues(false);  // 不顯示數值
        dataSet.setMode(LineDataSet.Mode.CUBIC_BEZIER);  // 平滑曲線
        dataSet.setCubicIntensity(0.2f);
        
        // 設定資料集到圖表
        LineData lineData = new LineData(dataSet);
        chart.setData(lineData);
        
        // 儲存資料集引用
        if (chart == accelXChart) {
            accelXDataSet = dataSet;
            Log.d(TAG, "加速度 X 軸圖表已初始化");
        } else if (chart == accelYChart) {
            accelYDataSet = dataSet;
            Log.d(TAG, "加速度 Y 軸圖表已初始化");
        } else if (chart == accelZChart) {
            accelZDataSet = dataSet;
            Log.d(TAG, "加速度 Z 軸圖表已初始化");
        } else if (chart == gyroXChart) {
            gyroXDataSet = dataSet;
            Log.d(TAG, "角速度 X 軸圖表已初始化");
        } else if (chart == gyroYChart) {
            gyroYDataSet = dataSet;
            Log.d(TAG, "角速度 Y 軸圖表已初始化");
        } else if (chart == gyroZChart) {
            gyroZDataSet = dataSet;
            Log.d(TAG, "角速度 Z 軸圖表已初始化");
        }
    }
    
    /**
     * 設定更新任務
     */
    private void setupUpdateRunnable() {
        updateRunnable = new Runnable() {
            @Override
            public void run() {
                if (isUpdating) {
                    updateCharts();
                    updateHandler.postDelayed(this, UPDATE_INTERVAL_MS);
                }
            }
        };
    }
    
    /**
     * 添加資料點（從 50Hz 資料中）
     */
    public void addDataPoint(IMUData data) {
        synchronized (dataBuffer) {
            dataBuffer.add(data);
            
            // 如果緩衝區太大，移除舊資料（保留足夠的資料供降採樣使用）
            if (dataBuffer.size() > DOWNSAMPLE_FACTOR * 3) {
                dataBuffer.remove(0);
            }
            
            // 除錯日誌（每 50 筆記錄一次，避免日誌過多）
            if (dataBuffer.size() % 50 == 0) {
                Log.d(TAG, "addDataPoint: 緩衝區大小=" + dataBuffer.size() + ", timestamp=" + data.timestamp);
            }
        }
    }
    
    /**
     * 更新所有圖表（每 100ms 調用一次）
     */
    private void updateCharts() {
        synchronized (dataBuffer) {
            if (dataBuffer.isEmpty()) {
                // 只在第一次為空時記錄，避免日誌過多
                return;
            }
            
            // 降採樣：每 100ms 取最新的資料點（從 50Hz 降採樣到 10Hz）
            // 直接取緩衝區中最後一筆資料（最新的）
            IMUData latestData = dataBuffer.get(dataBuffer.size() - 1);
            Log.d(TAG, "updateCharts: 緩衝區大小=" + dataBuffer.size() + ", 取最新資料 timestamp=" + latestData.timestamp);
            
            // 更新所有圖表
            updateChart(accelXChart, accelXDataSet, latestData.accelX, 0);
            updateChart(accelYChart, accelYDataSet, latestData.accelY, 1);
            updateChart(accelZChart, accelZDataSet, latestData.accelZ, 2);
            updateChart(gyroXChart, gyroXDataSet, latestData.gyroX, 3);
            updateChart(gyroYChart, gyroYDataSet, latestData.gyroY, 4);
            updateChart(gyroZChart, gyroZDataSet, latestData.gyroZ, 5);
            
            // 清除已處理的資料（保留最新的幾筆以備下次使用）
            if (dataBuffer.size() > DOWNSAMPLE_FACTOR) {
                int removeCount = dataBuffer.size() - DOWNSAMPLE_FACTOR;
                for (int i = 0; i < removeCount; i++) {
                    dataBuffer.remove(0);
                }
            }
        }
    }
    
    /**
     * 更新單個圖表
     */
    private void updateChart(LineChart chart, LineDataSet dataSet, float value, int chartIndex) {
        if (dataSet == null) {
            Log.w(TAG, "updateChart: dataSet 為 null，圖表索引: " + chartIndex);
            return;
        }
        
        if (chart == null) {
            Log.w(TAG, "updateChart: chart 為 null，圖表索引: " + chartIndex);
            return;
        }
        
        // 獲取當前資料點數量
        int currentSize = dataSet.getEntryCount();
        
        // 計算時間（X 軸）：從 0 到 5 秒
        // 每 100ms = 0.1 秒，所以時間 = 資料點索引 * 0.1
        float time;
        if (currentSize < MAX_DATA_POINTS) {
            // 還沒達到最大值，時間從 0 開始遞增
            time = currentSize * 0.1f;
        } else {
            // 達到最大值後，移除最舊的點
            dataSet.removeEntry(0);
            // 重新計算所有點的時間（向左移動）
            List<Entry> entries = dataSet.getValues();
            for (int i = 0; i < entries.size(); i++) {
                entries.get(i).setX(i * 0.1f);
            }
            time = (MAX_DATA_POINTS - 1) * 0.1f;  // 最後一個點的時間（4.9秒）
        }
        
        // 添加新資料點
        Entry entry = new Entry(time, value);
        dataSet.addEntry(entry);
        
        // 通知圖表更新
        chart.getData().notifyDataChanged();
        chart.notifyDataSetChanged();
        chart.invalidate();
        
        // 除錯日誌（每 10 次更新記錄一次，避免日誌過多）
        if (currentSize % 10 == 0) {
            Log.d(TAG, String.format("圖表 %d 更新: 時間=%.1fs, 數值=%.3f, 資料點數=%d", 
                chartIndex, time, value, dataSet.getEntryCount()));
        }
    }
    
    /**
     * 開始更新圖表
     */
    public void startUpdating() {
        if (!isUpdating) {
            isUpdating = true;
            updateHandler.post(updateRunnable);
            Log.d(TAG, "圖表更新已啟動，將每 " + UPDATE_INTERVAL_MS + "ms 更新一次");
        } else {
            Log.d(TAG, "圖表更新已在運行中");
        }
    }
    
    /**
     * 停止更新圖表
     */
    public void stopUpdating() {
        if (isUpdating) {
            isUpdating = false;
            updateHandler.removeCallbacks(updateRunnable);
            Log.d(TAG, "圖表更新已停止");
        }
    }
    
    /**
     * 清除所有圖表資料
     */
    public void clearAllCharts() {
        synchronized (dataBuffer) {
            dataBuffer.clear();
        }
        
        if (accelXDataSet != null) accelXDataSet.clear();
        if (accelYDataSet != null) accelYDataSet.clear();
        if (accelZDataSet != null) accelZDataSet.clear();
        if (gyroXDataSet != null) gyroXDataSet.clear();
        if (gyroYDataSet != null) gyroYDataSet.clear();
        if (gyroZDataSet != null) gyroZDataSet.clear();
        
        accelXChart.invalidate();
        accelYChart.invalidate();
        accelZChart.invalidate();
        gyroXChart.invalidate();
        gyroYChart.invalidate();
        gyroZChart.invalidate();
        
        Log.d(TAG, "所有圖表資料已清除");
    }
    
    /**
     * 釋放資源
     */
    public void release() {
        stopUpdating();
        clearAllCharts();
    }
}

