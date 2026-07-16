#![allow(ambiguous_glob_reexports)]

use crate::core::utils::aeterna_config_dir;
use qmetaobject::*;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

/// Settings structures and backend for user preferences.
///
/// SettingsBackend's qmetaobject macro-generated fields are accessed
/// by Qt/QML reflection only, hence the `#[allow(dead_code)]` on the impl.
///
/// 设置值
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub version: String,
    pub basic: BasicSettings,
    pub appearance: AppearanceSettings,
    pub player: PlayerSettings,
    pub editor: EditorSettings,
    pub time: TimeSettings,
    pub http_api: HttpApiSettings,
    pub cast: CastSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BasicSettings {
    pub auto_start: bool,
    pub minimize_to_tray: bool,
    pub auto_load_last: bool,
    pub config_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppearanceSettings {
    pub theme: String,
    pub theme_mode: String,           // "auto" / "dark" / "light"
    pub custom_primary_color: String, // 空字符串 = 使用 Pinguo Blue
    pub body_font: String,
    pub number_font: String,
    pub font_size: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerSettings {
    pub default_fullscreen: bool,
    pub disable_shortcuts: bool,
    pub show_gradient_bg: bool,
    pub auto_hide_toolbar: bool,
    pub clock_style: String,
    pub show_seconds: bool,
    pub show_date: bool,
    pub primary_color: String,
    pub bg_color: String,
    pub ui_scale: f64,
    pub density: String,
    pub big_clock: bool,
    pub large_info_font: bool,
    pub room_number: String,
    pub ntp_enabled: bool,
    pub ui_access_enabled: bool,
    pub exit_password_enabled: bool,
    pub exit_password: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorSettings {
    pub recent_files: Vec<String>,
    pub auto_save: bool,
    pub default_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeSettings {
    pub ntp_servers: Vec<String>,
    pub auto_sync: bool,
    pub periodic_sync: bool,
    pub sync_interval_minutes: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpApiSettings {
    pub enabled: bool,
    pub port: i32,
    pub bind_address: String,
    pub token_auth: bool,
    pub token: String,
    pub allow_cors: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CastSettings {
    pub enabled: bool,
    pub allow_discovery: bool,
    pub device_name: String,
    pub allow_remote_control: bool,
    pub auto_accept: bool,
    pub show_status_bar: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            version: env!("CARGO_PKG_VERSION").to_string(),
            basic: BasicSettings {
                auto_start: false,
                minimize_to_tray: true,
                auto_load_last: true,
                config_dir: default_config_dir(),
            },
            appearance: AppearanceSettings {
                theme: "dark".to_string(),
                theme_mode: "auto".to_string(),
                custom_primary_color: String::new(),
                body_font: "DM Sans".to_string(),
                number_font: "DM Sans".to_string(),
                font_size: 14,
            },
            player: PlayerSettings {
                default_fullscreen: true,
                disable_shortcuts: true,
                show_gradient_bg: true,
                auto_hide_toolbar: false,
                clock_style: "digital".to_string(),
                show_seconds: true,
                show_date: true,
                primary_color: String::new(), // empty = use Pinguo Blue #007aff
                bg_color: String::new(),      // empty = use theme background
                ui_scale: 1.0,
                density: "comfortable".to_string(),
                big_clock: false,
                large_info_font: false,
                room_number: "101".to_string(),
                ntp_enabled: false,
                ui_access_enabled: false,
                exit_password_enabled: false,
                exit_password: String::new(),
            },
            editor: EditorSettings {
                recent_files: vec![],
                auto_save: false,
                default_path: default_config_dir(),
            },
            time: TimeSettings {
                ntp_servers: vec![
                    "ntp.aliyun.com".to_string(),
                    "ntp.tencent.com".to_string(),
                    "pool.ntp.org".to_string(),
                    "time.windows.com".to_string(),
                ],
                auto_sync: true,
                periodic_sync: true,
                sync_interval_minutes: 30,
            },
            http_api: HttpApiSettings {
                enabled: true,
                port: 9527,
                bind_address: "0.0.0.0".to_string(),
                token_auth: false,
                token: String::new(),
                allow_cors: true,
            },
            cast: CastSettings {
                enabled: true,
                allow_discovery: true,
                device_name: "Aeterna-001".to_string(),
                allow_remote_control: false,
                auto_accept: false,
                show_status_bar: true,
            },
        }
    }
}

fn default_config_dir() -> String {
    aeterna_config_dir().to_string_lossy().to_string()
}

/// 设置窗口的 Rust 后端逻辑
#[allow(dead_code)]
#[derive(QObject, Default)]
pub struct SettingsBackend {
    base: qt_base_class!(trait QObject),

    settings_json: qt_property!(QString; READ settings_json NOTIFY settings_json_changed),
    config_path: qt_property!(QString; READ config_path NOTIFY config_path_changed),
    theme_mode: qt_property!(QString; READ theme_mode WRITE set_theme_mode NOTIFY theme_mode_changed),
    custom_primary_color: qt_property!(QString; READ custom_primary_color WRITE set_custom_primary_color NOTIFY custom_primary_color_changed),
    ui_access_enabled: qt_property!(bool; READ ui_access_enabled WRITE set_ui_access_enabled NOTIFY ui_access_enabled_changed),
    exit_password_enabled: qt_property!(bool; READ exit_password_enabled WRITE set_exit_password_enabled NOTIFY exit_password_enabled_changed),
    exit_password: qt_property!(QString; READ exit_password WRITE set_exit_password NOTIFY exit_password_changed),
    // Time / NTP settings
    ntp_servers_json: qt_property!(QString; READ ntp_servers_json NOTIFY ntp_servers_json_changed),
    ntp_auto_sync: qt_property!(bool; READ ntp_auto_sync WRITE set_ntp_auto_sync NOTIFY ntp_auto_sync_changed),
    ntp_periodic_sync: qt_property!(bool; READ ntp_periodic_sync WRITE set_ntp_periodic_sync NOTIFY ntp_periodic_sync_changed),
    ntp_sync_interval_minutes: qt_property!(i32; READ ntp_sync_interval_minutes WRITE set_ntp_sync_interval_minutes NOTIFY ntp_sync_interval_minutes_changed),
    ntp_last_offset_ms: qt_property!(i64; READ ntp_last_offset_ms NOTIFY ntp_last_offset_ms_changed),
    ntp_sync_status: qt_property!(QString; READ ntp_sync_status NOTIFY ntp_sync_status_changed),
    // Player display settings
    show_seconds: qt_property!(bool; READ show_seconds WRITE set_show_seconds NOTIFY show_seconds_changed),
    show_date: qt_property!(bool; READ show_date WRITE set_show_date NOTIFY show_date_changed),

    load: qt_method!(fn(&self)),
    save: qt_method!(fn(&self) -> bool),
    update_settings: qt_method!(fn(&self, json: QString) -> bool),
    test_ntp_server: qt_method!(fn(&self, server: QString) -> bool),
    sync_ntp_all: qt_method!(fn(&self) -> bool),
    add_ntp_server: qt_method!(fn(&self)),
    remove_ntp_server: qt_method!(fn(&self, index: i32)),

    settings_json_changed: qt_signal!(),
    config_path_changed: qt_signal!(),
    theme_mode_changed: qt_signal!(),
    custom_primary_color_changed: qt_signal!(),
    ui_access_enabled_changed: qt_signal!(),
    exit_password_enabled_changed: qt_signal!(),
    exit_password_changed: qt_signal!(),
    ntp_servers_json_changed: qt_signal!(),
    ntp_auto_sync_changed: qt_signal!(),
    ntp_periodic_sync_changed: qt_signal!(),
    ntp_sync_interval_minutes_changed: qt_signal!(),
    ntp_last_offset_ms_changed: qt_signal!(),
    ntp_sync_status_changed: qt_signal!(),
    show_seconds_changed: qt_signal!(),
    show_date_changed: qt_signal!(),
    ntp_test_result: qt_signal!(index: i32, success: bool, message: QString),

    _settings: Mutex<Settings>,
    _config_path: Mutex<String>,
}

impl SettingsBackend {
    fn settings_json(&self) -> QString {
        let settings = self._settings.lock().unwrap();
        let json = serde_json::to_string_pretty(&*settings).unwrap_or_default();
        QString::from(json)
    }

    fn config_path(&self) -> QString {
        QString::from(self._config_path.lock().unwrap().as_str())
    }

    /// 初始化：从文件加载设置
    pub fn load(&self) {
        let config_path = get_config_path();

        // Ensure config directory exists before reading
        if let Some(parent) = std::path::Path::new(&config_path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        *self._config_path.lock().unwrap() = config_path.clone();
        self.config_path_changed();

        if let Ok(content) = std::fs::read_to_string(&config_path) {
            if let Ok(settings) = serde_json::from_str::<Settings>(&content) {
                *self._settings.lock().unwrap() = settings;
                self.settings_json_changed();
                return;
            }
        }

        // 使用默认设置并保存
        let default_settings = Settings::default();
        self.save_settings_to_file(&default_settings, &config_path);
        *self._settings.lock().unwrap() = default_settings;
        self.settings_json_changed();
    }

    /// 保存设置
    pub fn save(&self) -> bool {
        let settings = self._settings.lock().unwrap().clone();
        let config_path = self._config_path.lock().unwrap().clone();
        self.save_settings_to_file(&settings, &config_path)
    }

    /// 更新设置（从 JSON）。自动确保 config dir 存在后再写入。
    pub fn update_settings(&self, json: QString) -> bool {
        let json_str = json.to_string();
        if let Ok(new_settings) = serde_json::from_str::<Settings>(&json_str) {
            *self._settings.lock().unwrap() = new_settings;
            self.settings_json_changed();

            // Ensure config directory exists, then save
            let config_path = get_config_path();
            if let Some(parent) = std::path::Path::new(&config_path).parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            *self._config_path.lock().unwrap() = config_path.clone();
            self.save()
        } else {
            false
        }
    }

    /// 获取当前设置
    #[allow(dead_code)]
    pub fn get_settings(&self) -> Settings {
        self._settings.lock().unwrap().clone()
    }

    fn theme_mode(&self) -> QString {
        let s = self._settings.lock().unwrap();
        QString::from(s.appearance.theme_mode.as_str())
    }

    fn set_theme_mode(&self, mode: QString) {
        let mode_str = mode.to_string();
        let valid = ["auto", "dark", "light"].contains(&mode_str.as_str());
        if valid {
            let mut s = self._settings.lock().unwrap();
            if s.appearance.theme_mode != mode_str {
                s.appearance.theme_mode = mode_str;
                drop(s);
                self.theme_mode_changed();
                self.save();
            }
        }
    }

    fn custom_primary_color(&self) -> QString {
        let s = self._settings.lock().unwrap();
        QString::from(s.appearance.custom_primary_color.as_str())
    }

    fn set_custom_primary_color(&self, color: QString) {
        let color_str = color.to_string();
        let mut s = self._settings.lock().unwrap();
        if s.appearance.custom_primary_color != color_str {
            s.appearance.custom_primary_color = color_str;
            drop(s);
            self.custom_primary_color_changed();
            self.save();
        }
    }

    fn ui_access_enabled(&self) -> bool {
        self._settings.lock().unwrap().player.ui_access_enabled
    }

    fn set_ui_access_enabled(&self, enabled: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.player.ui_access_enabled != enabled {
            s.player.ui_access_enabled = enabled;
            drop(s);
            self.ui_access_enabled_changed();
            self.save();
        }
    }

    fn exit_password_enabled(&self) -> bool {
        self._settings.lock().unwrap().player.exit_password_enabled
    }

    fn set_exit_password_enabled(&self, enabled: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.player.exit_password_enabled != enabled {
            s.player.exit_password_enabled = enabled;
            drop(s);
            self.exit_password_enabled_changed();
            self.save();
        }
    }

    fn exit_password(&self) -> QString {
        QString::from(self._settings.lock().unwrap().player.exit_password.as_str())
    }

    fn set_exit_password(&self, password: QString) {
        let password_str = password.to_string();
        let mut s = self._settings.lock().unwrap();
        if s.player.exit_password != password_str {
            s.player.exit_password = password_str;
            drop(s);
            self.exit_password_changed();
            self.save();
        }
    }

    // ── Time / NTP properties ──

    fn ntp_servers_json(&self) -> QString {
        let s = self._settings.lock().unwrap();
        let json = serde_json::to_string(&s.time.ntp_servers).unwrap_or_else(|_| "[]".to_string());
        QString::from(json)
    }

    fn ntp_auto_sync(&self) -> bool {
        self._settings.lock().unwrap().time.auto_sync
    }

    fn set_ntp_auto_sync(&self, value: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.time.auto_sync != value {
            s.time.auto_sync = value;
            drop(s);
            self.ntp_auto_sync_changed();
            self.save();
        }
    }

    fn ntp_periodic_sync(&self) -> bool {
        self._settings.lock().unwrap().time.periodic_sync
    }

    fn set_ntp_periodic_sync(&self, value: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.time.periodic_sync != value {
            s.time.periodic_sync = value;
            drop(s);
            self.ntp_periodic_sync_changed();
            self.save();
        }
    }

    fn ntp_sync_interval_minutes(&self) -> i32 {
        self._settings.lock().unwrap().time.sync_interval_minutes
    }

    fn set_ntp_sync_interval_minutes(&self, value: i32) {
        let mut s = self._settings.lock().unwrap();
        if s.time.sync_interval_minutes != value {
            s.time.sync_interval_minutes = value.clamp(1, 1440);
            drop(s);
            self.ntp_sync_interval_minutes_changed();
            self.save();
        }
    }

    fn ntp_last_offset_ms(&self) -> i64 {
        0 // 由 PlayerBackend 维护，SettingsBackend 返回 0
    }

    fn ntp_sync_status(&self) -> QString {
        QString::from("idle")
    }

    // ── Player display settings ──

    fn show_seconds(&self) -> bool {
        self._settings.lock().unwrap().player.show_seconds
    }

    fn set_show_seconds(&self, value: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.player.show_seconds != value {
            s.player.show_seconds = value;
            drop(s);
            self.show_seconds_changed();
            self.save();
        }
    }

    fn show_date(&self) -> bool {
        self._settings.lock().unwrap().player.show_date
    }

    fn set_show_date(&self, value: bool) {
        let mut s = self._settings.lock().unwrap();
        if s.player.show_date != value {
            s.player.show_date = value;
            drop(s);
            self.show_date_changed();
            self.save();
        }
    }

    // ── NTP methods ──

    /// 测试单个 NTP 服务器。异步执行，结果通过 ntp_test_result 信号返回。
    fn test_ntp_server(&self, server: QString) -> bool {
        let server_str = server.to_string();
        let qptr = QPointer::from(self);
        let sender = queued_callback(move |(idx, success, msg): (i32, bool, String)| {
            if let Some(this) = qptr.as_ref() {
                this.ntp_test_result(idx, success, QString::from(msg));
            }
        });
        // 找到 server 在列表中的索引
        let idx = {
            let s = self._settings.lock().unwrap();
            s.time
                .ntp_servers
                .iter()
                .position(|srv| srv == &server_str)
                .map(|i| i as i32)
                .unwrap_or(-1)
        };
        std::thread::spawn(move || {
            let service = crate::services::ntp::NtpService::new();
            let result = service.sync();
            if result.status == crate::services::ntp::NtpSyncStatus::Synced {
                sender((
                    idx,
                    true,
                    format!(
                        "延迟 {}ms, 偏移 {}ms",
                        result.round_trip_delay_ms, result.offset_ms
                    ),
                ));
            } else {
                let err = match &result.status {
                    crate::services::ntp::NtpSyncStatus::Failed(e) => e.clone(),
                    _ => "未知错误".to_string(),
                };
                sender((idx, false, err));
            }
        });
        true
    }

    /// 同步所有 NTP 服务器，取第一个成功的结果。
    fn sync_ntp_all(&self) -> bool {
        let servers = { self._settings.lock().unwrap().time.ntp_servers.clone() };
        if servers.is_empty() {
            return false;
        }
        let qptr = QPointer::from(self);
        let sender = queued_callback(move |(success, msg): (bool, String)| {
            if let Some(this) = qptr.as_ref() {
                this.ntp_test_result(-1, success, QString::from(msg));
            }
        });
        std::thread::spawn(move || {
            let config = crate::services::ntp::NtpConfig {
                servers,
                ..crate::services::ntp::NtpConfig::default()
            };
            let service = crate::services::ntp::NtpService::with_config(config);
            let result = service.sync();
            if result.status == crate::services::ntp::NtpSyncStatus::Synced {
                sender((
                    true,
                    format!("同步成功: {} (偏移 {}ms)", result.server, result.offset_ms),
                ));
            } else {
                let err = match &result.status {
                    crate::services::ntp::NtpSyncStatus::Failed(e) => e.clone(),
                    _ => "未知错误".to_string(),
                };
                sender((false, err));
            }
        });
        true
    }

    /// 添加一个空的 NTP 服务器条目
    fn add_ntp_server(&self) {
        let mut s = self._settings.lock().unwrap();
        s.time.ntp_servers.push(String::new());
        drop(s);
        self.ntp_servers_json_changed();
        self.save();
    }

    /// 删除指定索引的 NTP 服务器
    fn remove_ntp_server(&self, index: i32) {
        let mut s = self._settings.lock().unwrap();
        let idx = index as usize;
        if idx < s.time.ntp_servers.len() {
            s.time.ntp_servers.remove(idx);
            drop(s);
            self.ntp_servers_json_changed();
            self.save();
        }
    }

    fn save_settings_to_file(&self, settings: &Settings, path: &str) -> bool {
        let p = std::path::Path::new(path);
        if let Some(parent) = p.parent() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                ::log::error!(
                    "Failed to create settings directory {}: {}",
                    parent.display(),
                    e
                );
                return false;
            }
        }

        match serde_json::to_string_pretty(settings) {
            Ok(json) => match std::fs::write(path, json) {
                Ok(_) => {
                    ::log::info!("Settings saved to {}", path);
                    true
                }
                Err(e) => {
                    ::log::error!("Failed to write settings file: {}", e);
                    false
                }
            },
            Err(e) => {
                ::log::error!("Failed to serialize settings: {}", e);
                false
            }
        }
    }
}

fn get_config_path() -> String {
    aeterna_config_dir()
        .join("settings.json")
        .to_string_lossy()
        .to_string()
}
