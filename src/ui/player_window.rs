#![allow(non_snake_case)]

use crate::core::parser;
use crate::core::player::PlayerCore;
use crate::core::types::ExamConfig;
use crate::core::utils::parse_date_time_ms;
use crate::core::utils::{aeterna_config_dir, qml_file_input_to_path};
use crate::services::ntp::{NtpConfig, NtpService, NtpSyncStatus};
use chrono::{Local, TimeZone};
use qmetaobject::*;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;

/// Player backend — bridges PlayerCore state to QML properties.
///
/// Note: qmetaobject macro-generated fields on this struct are accessed
/// by Qt/QML reflection only, hence `#[allow(dead_code)]` on the impl.
#[allow(dead_code)]
#[derive(QObject, Default)]
pub struct PlayerBackend {
    base: qt_base_class!(trait QObject),

    // ── 绑定到 QML 的属性（对应 ExamPlayerCore 的 computed / useExamPlayer 暴露的视图）──
    currentTime: qt_property!(QString; READ current_time NOTIFY currentTimeChanged),
    currentDate: qt_property!(QString; READ current_date NOTIFY currentDateChanged),
    examEventName: qt_property!(QString; READ exam_event_name NOTIFY examEventNameChanged),
    message: qt_property!(QString; READ message NOTIFY messageChanged),
    currentExamName: qt_property!(QString; READ current_exam_name NOTIFY currentExamNameChanged),
    currentExamTimeRange: qt_property!(QString; READ current_exam_time_range NOTIFY currentExamTimeRangeChanged),
    remainingTime: qt_property!(QString; READ remaining_time NOTIFY remainingTimeChanged),
    remainingTimeMs: qt_property!(i64; READ remaining_time_ms NOTIFY remainingTimeMsChanged),
    currentExamAlertTime: qt_property!(i32; READ current_exam_alert_time NOTIFY currentExamAlertTimeChanged),
    statusText: qt_property!(QString; READ status_text NOTIFY statusTextChanged),
    progress: qt_property!(f64; READ progress NOTIFY progressChanged),
    roomNumber: qt_property!(QString; READ room_number WRITE setRoomNumber NOTIFY roomNumberChanged),
    roomNumberSaved: qt_property!(QString; READ room_number_saved NOTIFY roomNumberSavedChanged),
    uiScale: qt_property!(f64; READ ui_scale WRITE setUiScale NOTIFY uiScaleChanged),
    density: qt_property!(QString; READ density WRITE setDensity NOTIFY densityChanged),
    bigClock: qt_property!(bool; READ big_clock WRITE setBigClock NOTIFY bigClockChanged),
    bigClockFontSize: qt_property!(f64; READ big_clock_font_size WRITE setBigClockFontSize NOTIFY bigClockFontSizeChanged),
    largeInfoFont: qt_property!(bool; READ large_info_font WRITE setLargeInfoFont NOTIFY largeInfoFontChanged),
    materialsJson: qt_property!(QString; READ materials_json NOTIFY materialsJsonChanged),
    examListJson: qt_property!(QString; READ exam_list_json NOTIFY examListJsonChanged),
    currentExamIndex: qt_property!(i32; READ current_exam_index NOTIFY currentExamIndexChanged),
    loaded: qt_property!(bool; READ loaded NOTIFY loadedChanged),
    error: qt_property!(QString; READ error NOTIFY errorChanged),
    exitAuthorized: qt_property!(bool; READ exit_authorized NOTIFY exitAuthorizedChanged),
    ntpEnabled: qt_property!(bool; READ ntp_enabled WRITE setNtpEnabled NOTIFY ntpEnabledChanged),
    ntpOffsetMs: qt_property!(i64; READ ntp_offset_ms WRITE setNtpOffsetMs NOTIFY ntpOffsetMsChanged),
    uiAccessEnabled: qt_property!(bool; READ ui_access_enabled NOTIFY uiAccessEnabledChanged),
    exitPasswordEnabled: qt_property!(bool; READ exit_password_enabled NOTIFY exitPasswordEnabledChanged),
    exitPassword: qt_property!(QString; READ exit_password NOTIFY exitPasswordChanged),
    showSeconds: qt_property!(bool; READ show_seconds WRITE setShowSeconds NOTIFY showSecondsChanged),
    showDate: qt_property!(bool; READ show_date WRITE setShowDate NOTIFY showDateChanged),

    currentTimeChanged: qt_signal!(),
    currentDateChanged: qt_signal!(),
    examEventNameChanged: qt_signal!(),
    messageChanged: qt_signal!(),
    currentExamNameChanged: qt_signal!(),
    currentExamTimeRangeChanged: qt_signal!(),
    remainingTimeChanged: qt_signal!(),
    remainingTimeMsChanged: qt_signal!(),
    currentExamAlertTimeChanged: qt_signal!(),
    statusTextChanged: qt_signal!(),
    progressChanged: qt_signal!(),
    roomNumberChanged: qt_signal!(),
    roomNumberSavedChanged: qt_signal!(),
    uiScaleChanged: qt_signal!(),
    densityChanged: qt_signal!(),
    bigClockChanged: qt_signal!(),
    bigClockFontSizeChanged: qt_signal!(),
    largeInfoFontChanged: qt_signal!(),
    materialsJsonChanged: qt_signal!(),
    examListJsonChanged: qt_signal!(),
    currentExamIndexChanged: qt_signal!(),
    loadedChanged: qt_signal!(),
    errorChanged: qt_signal!(),
    exitAuthorizedChanged: qt_signal!(),
    ntpEnabledChanged: qt_signal!(),
    ntpOffsetMsChanged: qt_signal!(),
    uiAccessEnabledChanged: qt_signal!(),
    exitPasswordEnabledChanged: qt_signal!(),
    exitPasswordChanged: qt_signal!(),
    showSecondsChanged: qt_signal!(),
    showDateChanged: qt_signal!(),
    reminderEvent: qt_signal!(kind: QString, title: QString, message: QString),

    loadConfig: qt_method!(fn(&self, json: QString) -> bool),
    loadConfigFromFile: qt_method!(fn(&self, path: QString) -> bool),
    setRoomNumber: qt_method!(fn(&self, room: QString)),
    saveRoomNumber: qt_method!(fn(&self, room: QString) -> bool),
    setUiScale: qt_method!(fn(&self, scale: f64)),
    setDensity: qt_method!(fn(&self, density: QString)),
    setBigClock: qt_method!(fn(&self, value: bool)),
    setBigClockFontSize: qt_method!(fn(&self, value: f64)),
    setLargeInfoFont: qt_method!(fn(&self, value: bool)),
    setNtpEnabled: qt_method!(fn(&self, value: bool)),
    setNtpOffsetMs: qt_method!(fn(&self, offset: i64)),
    setShowSeconds: qt_method!(fn(&self, value: bool)),
    setShowDate: qt_method!(fn(&self, value: bool)),
    syncNtp: qt_method!(fn(&self) -> bool),
    loadPlayerSettings: qt_method!(fn(&self)),
    authorizeExit: qt_method!(fn(&self)),
    checkExitPassword: qt_method!(fn(&self, password: QString) -> bool),
    switchToExam: qt_method!(fn(&self, index: i32) -> bool),
    refresh: qt_method!(fn(&self)),
    start: qt_method!(fn(&self)),
    stop: qt_method!(fn(&self)),

    _player: Mutex<Option<Arc<PlayerCore>>>,
    _room_number: Mutex<String>,
    _room_number_saved: Mutex<String>,
    _room_number_loaded: Mutex<bool>,
    _scale: Mutex<f64>,
    _density: Mutex<String>,
    _big_clock: Mutex<bool>,
    _big_clock_font_size: Mutex<f64>,
    _large_info_font: Mutex<bool>,
    _materials_json: Mutex<String>,
    _exam_list_json: Mutex<String>,
    _exam_event_name: Mutex<String>,
    _message: Mutex<String>,
    _loaded: Mutex<bool>,
    _error: Mutex<String>,
    _exit_authorized: Mutex<bool>,
    _ntp_enabled: Mutex<bool>,
    _ntp_offset_ms: Mutex<i64>,
    _ui_access_enabled: Mutex<bool>,
    _exit_password_enabled: Mutex<bool>,
    _exit_password: Mutex<String>,
    _show_seconds: Mutex<bool>,
    _show_date: Mutex<bool>,
    _ntp_periodic_enabled: Mutex<bool>,
    _ntp_sync_interval_ms: Mutex<i64>,
    _ntp_last_sync_ms: Mutex<i64>,
}

impl PlayerBackend {
    fn current_time(&self) -> QString {
        let now_ms = self.corrected_now_ms();
        let fmt = if self.show_seconds() {
            "%H:%M:%S"
        } else {
            "%H:%M"
        };
        let text = Local
            .timestamp_millis_opt(now_ms)
            .single()
            .map(|d| d.format(fmt).to_string())
            .unwrap_or_default();
        QString::from(text)
    }

    fn current_date(&self) -> QString {
        if !self.show_date() {
            return QString::from("");
        }
        let now_ms = self.corrected_now_ms();
        let now = Local
            .timestamp_millis_opt(now_ms)
            .single()
            .unwrap_or_else(Local::now);
        let days = ["日", "一", "二", "三", "四", "五", "六"];
        let wd = now.format("%u").to_string().parse::<usize>().unwrap_or(1);
        QString::from(format!(
            "{}年{}月{}日 星期{}",
            now.format("%Y"),
            now.format("%m"),
            now.format("%d"),
            days[wd % 7]
        ))
    }

    fn corrected_now_ms(&self) -> i64 {
        let base = Local::now().timestamp_millis();
        if self.ntp_enabled() {
            base + self.ntp_offset_ms()
        } else {
            base
        }
    }

    fn exam_event_name(&self) -> QString {
        QString::from(self._exam_event_name.lock().unwrap().as_str())
    }

    fn message(&self) -> QString {
        QString::from(self._message.lock().unwrap().as_str())
    }

    fn current_exam_name(&self) -> QString {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => QString::from(p.current_exam_name()),
            None => QString::from("暂无考试"),
        }
    }

    fn current_exam_time_range(&self) -> QString {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => QString::from(p.exam_time_range()),
            None => QString::from("暂无安排"),
        }
    }

    fn remaining_time(&self) -> QString {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => QString::from(p.remaining_time_text()),
            None => QString::from("00:00"),
        }
    }

    fn remaining_time_ms(&self) -> i64 {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => p.remaining_time_ms().unwrap_or(0),
            None => 0,
        }
    }

    fn current_exam_alert_time(&self) -> i32 {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => p.current_exam_alert_time(),
            None => 0,
        }
    }

    fn status_text(&self) -> QString {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => {
                let status = p.exam_status();
                QString::from(match status.status {
                    crate::core::player::ExamStatus::Pending => "未开始",
                    crate::core::player::ExamStatus::InProgress => "进行中",
                    crate::core::player::ExamStatus::Completed => "已结束",
                    crate::core::player::ExamStatus::Unknown => "暂无考试",
                })
            }
            None => QString::from("等待开始"),
        }
    }

    fn progress(&self) -> f64 {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => p.exam_status().progress.unwrap_or(0.0),
            None => 0.0,
        }
    }

    fn room_number(&self) -> QString {
        QString::from(self._room_number.lock().unwrap().as_str())
    }

    fn ui_scale(&self) -> f64 {
        *self._scale.lock().unwrap()
    }

    fn materials_json(&self) -> QString {
        QString::from(self._materials_json.lock().unwrap().as_str())
    }

    fn exam_list_json(&self) -> QString {
        QString::from(self._exam_list_json.lock().unwrap().as_str())
    }

    fn current_exam_index(&self) -> i32 {
        match self._player.lock().unwrap().as_ref() {
            Some(p) => p.state().current_exam_index as i32,
            None => 0,
        }
    }

    fn loaded(&self) -> bool {
        *self._loaded.lock().unwrap()
    }

    fn error(&self) -> QString {
        QString::from(self._error.lock().unwrap().as_str())
    }

    fn room_number_saved(&self) -> QString {
        let need_load = {
            let loaded = self._room_number_loaded.lock().unwrap();
            !*loaded
        };
        if need_load {
            let path = Self::room_number_save_path();
            if let Ok(content) = std::fs::read_to_string(&path) {
                let trimmed = content.trim().to_string();
                if !trimmed.is_empty() {
                    *self._room_number_saved.lock().unwrap() = trimmed;
                }
            }
            *self._room_number_loaded.lock().unwrap() = true;
        }
        QString::from(self._room_number_saved.lock().unwrap().as_str())
    }

    fn density(&self) -> QString {
        let s = self._density.lock().unwrap();
        if s.is_empty() {
            QString::from("comfortable")
        } else {
            QString::from(s.as_str())
        }
    }

    fn big_clock(&self) -> bool {
        *self._big_clock.lock().unwrap()
    }

    fn big_clock_font_size(&self) -> f64 {
        let v = *self._big_clock_font_size.lock().unwrap();
        if v < 48.0 {
            196.0
        } else {
            v
        }
    }

    fn large_info_font(&self) -> bool {
        *self._large_info_font.lock().unwrap()
    }

    fn exit_authorized(&self) -> bool {
        *self._exit_authorized.lock().unwrap()
    }

    fn ntp_enabled(&self) -> bool {
        *self._ntp_enabled.lock().unwrap()
    }

    fn ntp_offset_ms(&self) -> i64 {
        *self._ntp_offset_ms.lock().unwrap()
    }

    fn ui_access_enabled(&self) -> bool {
        *self._ui_access_enabled.lock().unwrap()
    }

    fn exit_password_enabled(&self) -> bool {
        *self._exit_password_enabled.lock().unwrap()
    }

    fn exit_password(&self) -> QString {
        QString::from(self._exit_password.lock().unwrap().as_str())
    }

    fn setRoomNumber(&self, room: QString) {
        *self._room_number.lock().unwrap() = room.to_string();
        self.roomNumberChanged();
    }

    fn setUiScale(&self, scale: f64) {
        *self._scale.lock().unwrap() = scale;
        self.uiScaleChanged();
    }

    fn setDensity(&self, density: QString) {
        *self._density.lock().unwrap() = density.to_string();
        self.densityChanged();
    }

    fn setBigClock(&self, value: bool) {
        *self._big_clock.lock().unwrap() = value;
        self.bigClockChanged();
    }

    fn setBigClockFontSize(&self, value: f64) {
        *self._big_clock_font_size.lock().unwrap() = value;
        self.bigClockFontSizeChanged();
    }

    fn setLargeInfoFont(&self, value: bool) {
        *self._large_info_font.lock().unwrap() = value;
        self.largeInfoFontChanged();
    }

    fn setNtpEnabled(&self, value: bool) {
        *self._ntp_enabled.lock().unwrap() = value;
        self.ntpEnabledChanged();
        self.sync_player_time_fn();
    }

    fn setNtpOffsetMs(&self, offset: i64) {
        *self._ntp_offset_ms.lock().unwrap() = offset;
        self.ntpOffsetMsChanged();
        self.sync_player_time_fn();
    }

    fn show_seconds(&self) -> bool {
        *self._show_seconds.lock().unwrap()
    }

    fn setShowSeconds(&self, value: bool) {
        *self._show_seconds.lock().unwrap() = value;
        self.showSecondsChanged();
    }

    fn show_date(&self) -> bool {
        *self._show_date.lock().unwrap()
    }

    fn setShowDate(&self, value: bool) {
        *self._show_date.lock().unwrap() = value;
        self.showDateChanged();
    }

    fn sync_player_time_fn(&self) {
        if let Some(player) = self._player.lock().unwrap().as_ref() {
            player.set_time_fn(self.build_time_fn());
        }
    }

    /// 根据当前 NTP 设置构建时间函数。
    fn build_time_fn(&self) -> Box<dyn Fn() -> i64 + Send + 'static> {
        if self.ntp_enabled() {
            let offset = self.ntp_offset_ms();
            Box::new(move || Local::now().timestamp_millis() + offset)
        } else {
            Box::new(|| Local::now().timestamp_millis())
        }
    }

    fn syncNtp(&self) -> bool {
        // 从 settings.json 读取 NTP 服务器列表
        let servers = self.load_ntp_servers();
        let qptr = QPointer::from(self);
        let sender = queued_callback(move |offset: i64| {
            if let Some(this) = qptr.as_ref() {
                this.setNtpEnabled(true);
                this.setNtpOffsetMs(offset);
            }
        });
        thread::spawn(move || {
            let config = NtpConfig {
                servers,
                ..Default::default()
            };
            let service = NtpService::with_config(config);
            let result = service.sync();
            if result.status == NtpSyncStatus::Synced {
                sender(result.offset_ms);
            }
        });
        true
    }

    /// 从 settings.json 读取 NTP 服务器列表
    fn load_ntp_servers(&self) -> Vec<String> {
        let path = aeterna_config_dir().join("settings.json");
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(time) = json.get("time") {
                    if let Some(servers) = time.get("ntp_servers").and_then(|v| v.as_array()) {
                        return servers
                            .iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .filter(|s| !s.is_empty())
                            .collect();
                    }
                }
            }
        }
        // 返回默认服务器列表
        vec!["ntp.aliyun.com".to_string(), "pool.ntp.org".to_string()]
    }

    fn saveRoomNumber(&self, room: QString) -> bool {
        let path = Self::room_number_save_path();
        let room_str = room.to_string();
        let result = std::fs::create_dir_all(path.parent().unwrap_or(&path))
            .and_then(|_| std::fs::write(&path, &room_str));
        match result {
            Ok(_) => {
                *self._room_number_saved.lock().unwrap() = room_str;
                self.roomNumberSavedChanged();
                true
            }
            Err(_) => false,
        }
    }

    fn authorizeExit(&self) {
        *self._exit_authorized.lock().unwrap() = true;
        self.exitAuthorizedChanged();
    }

    fn checkExitPassword(&self, password: QString) -> bool {
        let expected = self._exit_password.lock().unwrap();
        let input = password.to_string();
        if expected.is_empty() {
            return true;
        }
        input == *expected
    }

    /// 从 settings.json 加载播放器设置
    fn loadPlayerSettings(&self) {
        let path = aeterna_config_dir().join("settings.json");
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(player) = json.get("player") {
                    let ui_access = player
                        .get("ui_access_enabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    *self._ui_access_enabled.lock().unwrap() = ui_access;
                    self.uiAccessEnabledChanged();

                    let exit_password_enabled = player
                        .get("exit_password_enabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    *self._exit_password_enabled.lock().unwrap() = exit_password_enabled;
                    self.exitPasswordEnabledChanged();

                    let exit_password = player
                        .get("exit_password")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    *self._exit_password.lock().unwrap() = exit_password.to_string();
                    self.exitPasswordChanged();

                    let show_seconds = player
                        .get("show_seconds")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    *self._show_seconds.lock().unwrap() = show_seconds;
                    self.showSecondsChanged();

                    let show_date = player
                        .get("show_date")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    *self._show_date.lock().unwrap() = show_date;
                    self.showDateChanged();
                }

                // 读取时间/NTP 设置
                if let Some(time) = json.get("time") {
                    let auto_sync = time
                        .get("auto_sync")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    let periodic_sync = time
                        .get("periodic_sync")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    let sync_interval = time
                        .get("sync_interval_minutes")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(30) as i32;

                    if auto_sync {
                        self.syncNtp();
                    }

                    if periodic_sync {
                        self.start_periodic_sync(sync_interval);
                    }
                }
            }
        }
    }

    /// 启动定时 NTP 同步（使用 refresh 每秒触发一次检查）
    fn start_periodic_sync(&self, interval_minutes: i32) {
        let interval_ms = (interval_minutes as i64).min(1440) * 60 * 1000;
        *self._ntp_periodic_enabled.lock().unwrap() = true;
        *self._ntp_sync_interval_ms.lock().unwrap() = interval_ms;
        *self._ntp_last_sync_ms.lock().unwrap() = Local::now().timestamp_millis();
    }

    fn room_number_save_path() -> PathBuf {
        aeterna_config_dir().join("room_number.txt")
    }

    /// 从 JSON 字符串加载考试配置。对应 TS 的 `updateConfig()`。
    fn loadConfig(&self, json: QString) -> bool {
        let json_str = json.to_string();
        let mut config: ExamConfig = match serde_json::from_str::<ExamConfig>(&json_str) {
            Ok(c) => c,
            Err(e) => {
                *self._error.lock().unwrap() = format!("配置解析失败: {}", e);
                *self._loaded.lock().unwrap() = false;
                self.errorChanged();
                self.loadedChanged();
                return false;
            }
        };

        // QML 与文件入口都在这里汇合，确保后续重叠检测和调度使用缓存时间戳。
        config.cache_timestamps();

        if !parser::validate_exam_config(&config) {
            *self._error.lock().unwrap() = "配置验证失败".to_string();
            *self._loaded.lock().unwrap() = false;
            self.errorChanged();
            self.loadedChanged();
            return false;
        }
        if parser::has_exam_time_overlap(&config) {
            *self._error.lock().unwrap() = "考试时间存在重叠".to_string();
            *self._loaded.lock().unwrap() = false;
            self.errorChanged();
            self.loadedChanged();
            return false;
        }

        let time_fn = self.build_time_fn();
        let player = PlayerCore::new(Some(config.clone()), time_fn);
        player.update_config(config.clone());

        // 注册考试事件回调，通过 queued_callback 将信号发送到 Qt 线程。
        let qptr = QPointer::from(self);

        let start_sender = {
            let qptr = qptr.clone();
            queued_callback(move |name: String| {
                if let Some(this) = qptr.as_ref() {
                    this.reminderEvent(
                        QString::from("start"),
                        QString::from("考试开始"),
                        QString::from(format!("{} 考试已开始", name)),
                    );
                }
            })
        };
        player.on_exam_start(move |exam| {
            start_sender(exam.name.clone());
        });

        let alert_sender = {
            let qptr = qptr.clone();
            queued_callback(move |(name, alert_time): (String, i32)| {
                if let Some(this) = qptr.as_ref() {
                    this.reminderEvent(
                        QString::from("alert"),
                        QString::from("考试即将结束"),
                        QString::from(format!("{} 考试还有 {} 分钟结束", name, alert_time)),
                    );
                }
            })
        };
        player.on_exam_alert(move |exam, alert_time| {
            alert_sender((exam.name.clone(), alert_time));
        });

        let end_sender = {
            let qptr = qptr;
            queued_callback(move |name: String| {
                if let Some(this) = qptr.as_ref() {
                    this.reminderEvent(
                        QString::from("end"),
                        QString::from("考试结束"),
                        QString::from(format!("{} 考试已结束", name)),
                    );
                }
            })
        };
        player.on_exam_end(move |exam| {
            end_sender(exam.name.clone());
        });

        player.start();

        *self._player.lock().unwrap() = Some(Arc::new(player));
        *self._exam_event_name.lock().unwrap() = config.exam_name.clone();
        *self._message.lock().unwrap() = config.message.clone();
        *self._loaded.lock().unwrap() = true;
        *self._error.lock().unwrap() = String::new();

        self.recompute();
        true
    }

    /// 从文件加载考试配置。对应桌面端 `fileUtils.readJSONFile` + `updateConfig`。
    fn loadConfigFromFile(&self, path: QString) -> bool {
        let path = match qml_file_input_to_path(&path.to_string()) {
            Ok(path) => path,
            Err(e) => {
                *self._error.lock().unwrap() = e;
                *self._loaded.lock().unwrap() = false;
                self.errorChanged();
                self.loadedChanged();
                return false;
            }
        };
        let path_str = path.to_string_lossy().to_string();
        let content = match std::fs::read_to_string(&path) {
            Ok(c) => c,
            Err(e) => {
                *self._error.lock().unwrap() = format!("无法读取文件 {}: {}", path_str, e);
                *self._loaded.lock().unwrap() = false;
                self.errorChanged();
                self.loadedChanged();
                return false;
            }
        };
        self.loadConfig(QString::from(content))
    }

    /// 切换当前显示的考试。对应 TS 的 `switchToExam()`。
    fn switchToExam(&self, index: i32) -> bool {
        let guard = self._player.lock().unwrap();
        match guard.as_ref() {
            Some(player) => {
                let ok = player.switch_to_exam(index as usize);
                drop(guard);
                if ok {
                    self.recompute();
                }
                ok
            }
            None => false,
        }
    }

    /// 每秒 tick：重算所有动态属性并通知 QML。
    /// 对应 TS 的 `startTimeUpdates` 定时器（每 1 秒推进 `currentTime`）。
    fn refresh(&self) {
        // currentTime / current_date 始终基于真实时间，无需缓存直接通知。
        self.currentTimeChanged();
        self.currentDateChanged();
        self.recompute();

        // 定时 NTP 同步检查
        let should_sync = {
            let periodic = *self._ntp_periodic_enabled.lock().unwrap();
            if !periodic {
                false
            } else {
                let now = Local::now().timestamp_millis();
                let last = *self._ntp_last_sync_ms.lock().unwrap();
                let interval = *self._ntp_sync_interval_ms.lock().unwrap();
                if now - last >= interval {
                    *self._ntp_last_sync_ms.lock().unwrap() = now;
                    true
                } else {
                    false
                }
            }
        };
        if should_sync {
            self.syncNtp();
        }
    }

    fn start(&self) {
        if let Some(p) = self._player.lock().unwrap().as_ref() {
            p.start();
        }
    }

    fn stop(&self) {
        if let Some(p) = self._player.lock().unwrap().as_ref() {
            p.stop();
        }
    }

    /// 根据 `PlayerCore` 的当前状态重算所有派生属性（状态/倒计时/进度/列表/材料）。
    /// 对应 `ExamDataProcessor` 的各计算方法。
    fn recompute(&self) {
        let guard = self._player.lock().unwrap();
        let player = match guard.as_ref() {
            Some(p) => p,
            None => {
                // 未加载：清空列表与材料
                *self._materials_json.lock().unwrap() = "[]".to_string();
                *self._exam_list_json.lock().unwrap() = "[]".to_string();
                drop(guard);
                self.materialsJsonChanged();
                self.examListJsonChanged();
                self.currentExamIndexChanged();
                self.currentExamNameChanged();
                self.currentExamTimeRangeChanged();
                self.remainingTimeChanged();
                self.remainingTimeMsChanged();
                self.currentExamAlertTimeChanged();
                self.statusTextChanged();
                self.progressChanged();
                self.examEventNameChanged();
                self.messageChanged();
                return;
            }
        };

        let config = player.config();
        let now_ms = player.current_time_ms();

        // 材料清单：当前考试的 materials（对应 ExamInfoCard 的材料渲染）。
        let materials_json = match player.current_exam() {
            Some(exam) => match &exam.materials {
                Some(mats) if !mats.is_empty() => {
                    let arr: Vec<serde_json::Value> = mats
                        .iter()
                        .map(|m| {
                            serde_json::json!({
                                "name": m.name,
                                "quantity": m.quantity,
                                "unit": m.unit,
                            })
                        })
                        .collect();
                    serde_json::to_string(&arr).unwrap_or_else(|_| "[]".to_string())
                }
                _ => "[]".to_string(),
            },
            None => "[]".to_string(),
        };
        *self._materials_json.lock().unwrap() = materials_json;

        // 带状态的考试列表：对应 `ExamDataProcessor.formatExamInfos`。
        let exam_list_json = match &config {
            Some(cfg) => build_formatted_exam_list(cfg, now_ms),
            None => "[]".to_string(),
        };
        *self._exam_list_json.lock().unwrap() = exam_list_json;

        let _ = config; // 仅用于上面分支
        drop(guard);

        self.materialsJsonChanged();
        self.examListJsonChanged();
        self.currentExamIndexChanged();
        self.currentExamNameChanged();
        self.currentExamTimeRangeChanged();
        self.remainingTimeChanged();
        self.remainingTimeMsChanged();
        self.currentExamAlertTimeChanged();
        self.statusTextChanged();
        self.progressChanged();
        self.examEventNameChanged();
        self.messageChanged();
        self.loadedChanged();
        self.errorChanged();
    }
}

impl Drop for PlayerBackend {
    fn drop(&mut self) {
        if let Some(player) = self._player.lock().unwrap().take() {
            drop(player);
        }
    }
}

/// 构造带状态的考试列表 JSON，严格照抄 `ExamDataProcessor.formatExamInfos`。
///
/// 返回数组，每个元素：`{ index, name, date, timeRange, status, statusText }`
/// - status: `pending` / `inProgress` / `completed`
/// - timeRange: `HH:MM ~ HH:MM`
fn build_formatted_exam_list(config: &ExamConfig, now_ms: i64) -> String {
    let sorted = parser::get_sorted_exam_config(config.clone());
    let mut last_displayed_date = String::new();
    let mut arr: Vec<serde_json::Value> = Vec::new();

    for (index, exam) in sorted.exam_infos.iter().enumerate() {
        let start_ms = parse_date_time_ms(&exam.start);
        let end_ms = parse_date_time_ms(&exam.end);

        // 状态判断（与 TS 完全一致：now > end => completed; now >= start => inProgress; 否则 pending）
        let (status, status_text) = if now_ms > end_ms {
            ("completed", "已结束")
        } else if now_ms >= start_ms {
            ("inProgress", "进行中")
        } else {
            ("pending", "未开始")
        };

        // 日期（zh-CN MM/DD），仅在与上一个不同时显示
        let date_string = Local
            .timestamp_millis_opt(start_ms)
            .single()
            .map(|d| d.format("%m/%d").to_string())
            .unwrap_or_default();
        let display_date = if date_string != last_displayed_date {
            last_displayed_date = date_string.clone();
            date_string
        } else {
            String::new()
        };

        let time_range = format!(
            "{} ~ {}",
            format_hour_minute(start_ms),
            format_hour_minute(end_ms)
        );

        arr.push(serde_json::json!({
            "index": index,
            "name": exam.name,
            "date": display_date,
            "timeRange": time_range,
            "status": status,
            "statusText": status_text,
        }));
    }

    serde_json::to_string(&arr).unwrap_or_else(|_| "[]".to_string())
}

/// 将毫秒时间戳格式化为 `HH:MM`，对应 `ExamDataProcessor.formatHourMinute`。
/// 对于无效/零时间戳返回空字符串。
fn format_hour_minute(ms: i64) -> String {
    if ms <= 0 {
        return String::new();
    }
    Local
        .timestamp_millis_opt(ms)
        .single()
        .map(|d| d.format("%H:%M").to_string())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::types::{ExamConfig, ExamInfo};
    use crate::core::utils::parse_date_time;

    #[test]
    fn test_format_hour_minute_valid() {
        let ts = parse_date_time("2025-06-15 08:30:00")
            .unwrap()
            .timestamp_millis();
        assert_eq!(format_hour_minute(ts), "08:30");
    }

    #[test]
    fn test_format_hour_minute_invalid() {
        assert_eq!(format_hour_minute(0), "");
    }

    #[test]
    fn test_build_formatted_exam_list_status() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();

        // 09:00，语文进行中，数学未开始
        let now = parse_date_time("2025-06-15 09:00:00")
            .unwrap()
            .timestamp_millis();
        let json = build_formatted_exam_list(&config, now);
        let list: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0]["status"], "inProgress");
        assert_eq!(list[0]["statusText"], "进行中");
        assert_eq!(list[1]["status"], "pending");
        assert_eq!(list[1]["statusText"], "未开始");
    }

    #[test]
    fn test_build_formatted_exam_list_completed() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![ExamInfo {
                name: "语文".to_string(),
                start: "2025-06-15 08:00:00".to_string(),
                end: "2025-06-15 10:00:00".to_string(),
                alert_time: 5,
                materials: None,
                start_ts: 0,
                end_ts: 0,
            }],
        };
        config.cache_timestamps();

        let now = parse_date_time("2025-06-15 11:00:00")
            .unwrap()
            .timestamp_millis();
        let json = build_formatted_exam_list(&config, now);
        let list: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0]["status"], "completed");
        assert_eq!(list[0]["statusText"], "已结束");
    }

    #[test]
    fn test_build_formatted_exam_list_time_range() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![ExamInfo {
                name: "语文".to_string(),
                start: "2025-06-15 08:00:00".to_string(),
                end: "2025-06-15 10:00:00".to_string(),
                alert_time: 5,
                materials: None,
                start_ts: 0,
                end_ts: 0,
            }],
        };
        config.cache_timestamps();

        let now = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let json = build_formatted_exam_list(&config, now);
        let list: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(list[0]["timeRange"], "08:00 ~ 10:00");
    }

    #[test]
    fn test_build_formatted_exam_list_date_dedup() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();

        let now = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let json = build_formatted_exam_list(&config, now);
        let list: Vec<serde_json::Value> = serde_json::from_str(&json).unwrap();
        assert_eq!(list[0]["date"], "06/15");
        // 第二场与第一场同一天，日期应留空避免重复显示
        assert_eq!(list[1]["date"], "");
    }
}
