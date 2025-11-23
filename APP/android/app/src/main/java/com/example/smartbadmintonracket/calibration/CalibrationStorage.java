package com.example.smartbadmintonracket.calibration;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

/**
 * 校正資料儲存管理
 * 使用 SharedPreferences 儲存校正值
 */
public class CalibrationStorage {
    private static final String TAG = "CalibrationStorage";
    private static final String PREF_NAME = "imu_calibration";
    private static final String KEY_CALIBRATION_DATA = "calibration_data";
    
    private SharedPreferences prefs;
    private Gson gson;
    
    public CalibrationStorage(Context context) {
        prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        gson = new GsonBuilder().create();
    }
    
    /**
     * 儲存校正資料
     */
    public void saveCalibration(CalibrationData data) {
        try {
            String json = gson.toJson(data);
            prefs.edit()
                .putString(KEY_CALIBRATION_DATA, json)
                .apply();
            Log.d(TAG, "校正資料已儲存: " + data.toString());
        } catch (Exception e) {
            Log.e(TAG, "儲存校正資料失敗", e);
        }
    }
    
    /**
     * 載入校正資料
     * @return 校正資料，如果不存在則返回 null
     */
    public CalibrationData loadCalibration() {
        try {
            String json = prefs.getString(KEY_CALIBRATION_DATA, null);
            if (json == null) {
                Log.d(TAG, "沒有找到已儲存的校正資料");
                return null;
            }
            
            CalibrationData data = gson.fromJson(json, CalibrationData.class);
            if (data != null && data.isValid()) {
                Log.d(TAG, "校正資料已載入: " + data.toString());
                return data;
            } else {
                Log.w(TAG, "載入的校正資料無效");
                return null;
            }
        } catch (Exception e) {
            Log.e(TAG, "載入校正資料失敗", e);
            return null;
        }
    }
    
    /**
     * 清除校正資料
     */
    public void clearCalibration() {
        prefs.edit()
            .remove(KEY_CALIBRATION_DATA)
            .apply();
        Log.d(TAG, "校正資料已清除");
    }
    
    /**
     * 檢查是否有已儲存的校正資料
     */
    public boolean hasCalibration() {
        return prefs.contains(KEY_CALIBRATION_DATA);
    }
}

