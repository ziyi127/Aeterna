#![allow(ambiguous_glob_reexports)]
#![allow(non_snake_case)]

use crate::core::parser;
use crate::core::player;
use crate::core::types::ExamConfig;
use crate::core::utils::{aeterna_config_dir, strip_file_prefix};
use chrono::Local;
use qmetaobject::*;
use std::path::Path;
use std::sync::Mutex;

/// Editor backend — file I/O and validation for the exam editor window.
///
/// Note: qmetaobject macro-generated fields on this struct are accessed
/// by Qt/QML reflection only, hence the `#[allow(dead_code)]` on the impl.
#[allow(dead_code)]
#[derive(QObject, Default)]
pub struct EditorBackend {
    base: qt_base_class!(trait QObject),

    configValid: qt_property!(bool; READ config_valid NOTIFY configValidChanged),
    examCount: qt_property!(i32; READ exam_count NOTIFY examCountChanged),
    unsaved: qt_property!(bool; READ unsaved WRITE set_unsaved NOTIFY unsavedChanged),
    currentFilePath: qt_property!(QString; READ current_file_path NOTIFY currentFilePathChanged),
    configJson: qt_property!(QString; READ config_json NOTIFY configJsonChanged),
    errorDetails: qt_property!(QString; READ error_details NOTIFY errorDetailsChanged),
    recentFilesJson: qt_property!(QString; READ recent_files_json NOTIFY recentFilesJsonChanged),
    validationReportJson: qt_property!(QString; READ validation_report_json NOTIFY validationReportJsonChanged),
    previewExamIndex: qt_property!(i32; READ preview_exam_index WRITE set_preview_exam_index NOTIFY previewExamIndexChanged),
    examPreviewJson: qt_property!(QString; READ exam_preview_json NOTIFY examPreviewJsonChanged),

    configValidChanged: qt_signal!(),
    examCountChanged: qt_signal!(),
    unsavedChanged: qt_signal!(),
    currentFilePathChanged: qt_signal!(),
    configJsonChanged: qt_signal!(),
    errorDetailsChanged: qt_signal!(),
    recentFilesJsonChanged: qt_signal!(),
    validationReportJsonChanged: qt_signal!(),
    previewExamIndexChanged: qt_signal!(),
    examPreviewJsonChanged: qt_signal!(),
    closeWindowRequested: qt_signal!(),

    loadFile: qt_method!(fn(&self, path: QString) -> bool),
    saveToFile: qt_method!(fn(&self, path: QString, json: QString) -> bool),
    validateConfig: qt_method!(fn(&self, json: QString) -> bool),
    newConfig: qt_method!(fn(&self)),
    markSaved: qt_method!(fn(&self)),
    markUnsaved: qt_method!(fn(&self)),
    addRecentFile: qt_method!(fn(&self, path: QString)),
    validateConfigWithDetails: qt_method!(fn(&self, json: QString) -> bool),
    importFromFile: qt_method!(fn(&self, path: QString) -> bool),
    exportToFile: qt_method!(fn(&self, path: QString, json: QString) -> bool),
    sortExamInfos: qt_method!(fn(&self, json: QString) -> QString),
    requestClose: qt_method!(fn(&self)),
    confirmClose: qt_method!(fn(&self, save: bool) -> bool),
    update_exam_preview: qt_method!(fn(&self, index: i32)),

    _config: Mutex<Option<ExamConfig>>,
    _valid: Mutex<bool>,
    _unsaved: Mutex<bool>,
    _file_path: Mutex<String>,
    _config_json: Mutex<String>,
    _error: Mutex<String>,
    _recent_files: Mutex<Vec<String>>,
    _recent_files_loaded: Mutex<bool>,
    _validation_report_json: Mutex<String>,
    _preview_exam_index: Mutex<i32>,
    _exam_preview_json: Mutex<String>,
}

impl EditorBackend {
    fn config_valid(&self) -> bool {
        *self._valid.lock().unwrap()
    }

    fn exam_count(&self) -> i32 {
        self._config
            .lock()
            .unwrap()
            .as_ref()
            .map(|c| c.exam_infos.len() as i32)
            .unwrap_or(0)
    }

    fn unsaved(&self) -> bool {
        *self._unsaved.lock().unwrap()
    }

    fn set_unsaved(&self, value: bool) {
        *self._unsaved.lock().unwrap() = value;
        self.unsavedChanged();
    }

    fn current_file_path(&self) -> QString {
        QString::from(self._file_path.lock().unwrap().as_str())
    }

    fn config_json(&self) -> QString {
        QString::from(self._config_json.lock().unwrap().as_str())
    }

    fn error_details(&self) -> QString {
        QString::from(self._error.lock().unwrap().as_str())
    }

    fn recent_files_json(&self) -> QString {
        self.ensure_recent_files_loaded();
        let files = self._recent_files.lock().unwrap();
        QString::from(serde_json::to_string(&*files).unwrap_or_default().as_str())
    }

    fn validation_report_json(&self) -> QString {
        QString::from(self._validation_report_json.lock().unwrap().as_str())
    }

    fn preview_exam_index(&self) -> i32 {
        *self._preview_exam_index.lock().unwrap()
    }

    fn set_preview_exam_index(&self, value: i32) {
        *self._preview_exam_index.lock().unwrap() = value;
        self.previewExamIndexChanged();
    }

    fn exam_preview_json(&self) -> QString {
        QString::from(self._exam_preview_json.lock().unwrap().as_str())
    }

    fn update_exam_preview(&self, index: i32) {
        if index >= 0 {
            self.set_preview_exam_index(index);
        }
        let config = self._config.lock().unwrap();
        let exam = match config.as_ref().and_then(|c| {
            let idx = *self._preview_exam_index.lock().unwrap() as usize;
            if idx < c.exam_infos.len() {
                Some(&c.exam_infos[idx])
            } else {
                None
            }
        }) {
            Some(e) => e.clone(),
            None => {
                *self._exam_preview_json.lock().unwrap() = String::from("{}");
                self.examPreviewJsonChanged();
                return;
            }
        };
        drop(config);

        // 确保时间戳已缓存
        let mut exam_for_compute = exam.clone();
        if exam_for_compute.start_ts == 0 && exam_for_compute.end_ts == 0 {
            exam_for_compute.cache_timestamps();
        }

        let now_ms = Local::now().timestamp_millis();
        let status = player::compute_exam_status(&exam_for_compute, now_ms);
        let time_range = if let (Some(s), Some(e)) = (
            crate::core::utils::parse_date_time(&exam.start),
            crate::core::utils::parse_date_time(&exam.end),
        ) {
            format!("{} - {}", s.format("%H:%M"), e.format("%H:%M"))
        } else {
            "时间待设置".to_string()
        };

        let json = serde_json::json!({
            "status": format!("{:?}", status.status),
            "statusText": match status.status {
                player::ExamStatus::Pending => "未开始",
                player::ExamStatus::InProgress => "进行中",
                player::ExamStatus::Completed => "已结束",
                player::ExamStatus::Unknown => "",
            },
            "remainingTime": if let Some(ms) = status.time_remaining_ms {
                player::format_duration(ms)
            } else {
                String::new()
            },
            "remainingMs": status.time_remaining_ms.unwrap_or(0),
            "progress": status.progress.unwrap_or(0.0),
            "timeRange": time_range,
            "alertTime": exam.alert_time
        });

        *self._exam_preview_json.lock().unwrap() = serde_json::to_string(&json).unwrap_or_default();
        self.examPreviewJsonChanged();
    }

    /// 返回最近文件持久化路径。
    fn recent_files_path() -> std::path::PathBuf {
        aeterna_config_dir().join("recent_files.json")
    }

    /// 从指定路径加载最近文件列表。
    fn load_recent_files(path: &std::path::Path) -> Vec<String> {
        if let Ok(content) = std::fs::read_to_string(path) {
            if let Ok(list) = serde_json::from_str::<Vec<String>>(&content) {
                return list;
            }
        }
        Vec::new()
    }

    /// 将最近文件列表持久化到指定路径。
    fn persist_recent_files(path: &std::path::Path, files: &[String]) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(
            path,
            serde_json::to_string_pretty(files).unwrap_or_default(),
        )
    }

    /// 维护最近文件列表核心逻辑：去重、移到最前、最多保留 10 条。
    fn maintain_recent_files(files: &mut Vec<String>, path: String) {
        if path.trim().is_empty() {
            return;
        }
        files.retain(|p| p != &path);
        files.insert(0, path);
        if files.len() > 10 {
            files.truncate(10);
        }
    }

    /// 确保最近文件列表已从磁盘加载。
    fn ensure_recent_files_loaded(&self) {
        let mut loaded = self._recent_files_loaded.lock().unwrap();
        if *loaded {
            return;
        }
        let path = Self::recent_files_path();
        *self._recent_files.lock().unwrap() = Self::load_recent_files(&path);
        *loaded = true;
    }

    /// 将最近文件列表持久化到磁盘。
    fn persist_recent_files_internal(&self) {
        let path = Self::recent_files_path();
        let list = self._recent_files.lock().unwrap();
        let _ = Self::persist_recent_files(&path, &list);
    }

    /// 从文件打开配置。对应 `fileUtils.readJSONFile` + 校验 + 载入。
    fn loadFile(&self, path: QString) -> bool {
        let path_str = strip_file_prefix(&path.to_string());
        let content = match std::fs::read_to_string(&path_str) {
            Ok(c) => c,
            Err(e) => {
                *self._error.lock().unwrap() = format!("无法读取文件 {}: {}", path_str, e);
                *self._valid.lock().unwrap() = false;
                self.errorDetailsChanged();
                self.configValidChanged();
                ::log::warn!("EditorBackend: {}", self._error.lock().unwrap());
                return false;
            }
        };

        match serde_json::from_str::<ExamConfig>(&content) {
            Ok(config) => {
                let valid = parser::validate_exam_config(&config);
                let pretty =
                    serde_json::to_string_pretty(&config).unwrap_or_else(|_| content.clone());
                *self._config.lock().unwrap() = Some(config);
                *self._config_json.lock().unwrap() = pretty;
                *self._valid.lock().unwrap() = valid;
                *self._unsaved.lock().unwrap() = false;
                *self._file_path.lock().unwrap() = path_str.clone();
                *self._error.lock().unwrap() = if valid {
                    String::new()
                } else {
                    "配置验证失败".to_string()
                };
                self.emit_all();
                self.update_exam_preview(-1);
                ::log::info!("EditorBackend: loaded config from {}", path_str);
                true
            }
            Err(e) => {
                *self._error.lock().unwrap() = format!("JSON 解析失败: {}", e);
                *self._valid.lock().unwrap() = false;
                *self._config.lock().unwrap() = None;
                self.emit_all();
                false
            }
        }
    }

    /// 保存配置到指定路径。对应 `fileUtils.writeJSONFile` + 校验 + 持久化。
    ///
    /// `json` 由 QML（renderer）构造，`path` 为目标文件路径。
    fn saveToFile(&self, path: QString, json: QString) -> bool {
        let path_str = strip_file_prefix(&path.to_string());
        let json_str = json.to_string();

        let config: ExamConfig = match serde_json::from_str::<ExamConfig>(&json_str) {
            Ok(c) => c,
            Err(e) => {
                *self._error.lock().unwrap() = format!("JSON 解析失败: {}", e);
                *self._valid.lock().unwrap() = false;
                self.emit_all();
                return false;
            }
        };

        if !parser::validate_exam_config(&config) {
            *self._error.lock().unwrap() = "配置验证失败：字段不合法".to_string();
            *self._valid.lock().unwrap() = false;
            self.emit_all();
            return false;
        }
        if parser::has_exam_time_overlap(&config) {
            *self._error.lock().unwrap() = "配置验证失败：考试时间存在重叠".to_string();
            *self._valid.lock().unwrap() = false;
            self.emit_all();
            return false;
        }

        let pretty = serde_json::to_string_pretty(&config).unwrap_or_else(|_| json_str.clone());

        // 确保父目录存在
        if let Some(parent) = Path::new(&path_str).parent() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                *self._error.lock().unwrap() = format!("无法创建目录: {}", e);
                self.emit_all();
                return false;
            }
        }

        match std::fs::write(&path_str, &pretty) {
            Ok(_) => {
                *self._config.lock().unwrap() = Some(config);
                *self._config_json.lock().unwrap() = pretty;
                *self._file_path.lock().unwrap() = path_str.clone();
                *self._valid.lock().unwrap() = true;
                *self._unsaved.lock().unwrap() = false;
                *self._error.lock().unwrap() = String::new();
                self.emit_all();
                ::log::info!("EditorBackend: saved config to {}", path_str);
                true
            }
            Err(e) => {
                *self._error.lock().unwrap() = format!("写入文件失败: {}", e);
                self.emit_all();
                false
            }
        }
    }

    /// 仅校验配置（不持久化）。对应 `validateExamConfig` + `hasExamTimeOverlap`。
    fn validateConfig(&self, json: QString) -> bool {
        let json_str = json.to_string();
        match serde_json::from_str::<ExamConfig>(&json_str) {
            Ok(config) => {
                let valid = parser::validate_exam_config(&config)
                    && !parser::has_exam_time_overlap(&config);
                *self._valid.lock().unwrap() = valid;
                *self._config.lock().unwrap() = Some(config.clone());
                *self._config_json.lock().unwrap() =
                    serde_json::to_string_pretty(&config).unwrap_or(json_str);
                *self._error.lock().unwrap() = if valid {
                    String::new()
                } else {
                    "配置无效（字段不合法或时间重叠）".to_string()
                };
                self.emit_all();
                self.update_exam_preview(-1);
                valid
            }
            Err(e) => {
                *self._valid.lock().unwrap() = false;
                *self._config.lock().unwrap() = None;
                *self._error.lock().unwrap() = format!("JSON 解析失败: {}", e);
                self.emit_all();
                false
            }
        }
    }

    /// 新建空白配置。
    fn newConfig(&self) {
        *self._config.lock().unwrap() = Some(ExamConfig {
            exam_name: String::new(),
            message: String::new(),
            exam_infos: Vec::new(),
        });
        *self._config_json.lock().unwrap() =
            "{\n  \"examName\": \"\",\n  \"message\": \"\",\n  \"examInfos\": []\n}".to_string();
        *self._valid.lock().unwrap() = true;
        *self._unsaved.lock().unwrap() = false;
        *self._file_path.lock().unwrap() = String::new();
        *self._error.lock().unwrap() = String::new();
        self.emit_all();
    }

    fn markSaved(&self) {
        self.set_unsaved(false);
    }

    fn markUnsaved(&self) {
        self.set_unsaved(true);
    }

    fn emit_all(&self) {
        self.configValidChanged();
        self.examCountChanged();
        self.unsavedChanged();
        self.currentFilePathChanged();
        self.configJsonChanged();
        self.errorDetailsChanged();
    }

    /// 将校验报告中的问题格式化为可读字符串。
    fn format_report_errors(report: &parser::ValidationReport) -> String {
        if report.errors.is_empty() {
            if report.warnings.is_empty() {
                String::new()
            } else {
                report
                    .warnings
                    .iter()
                    .map(|w| format!("[警告] {}", w.message))
                    .collect::<Vec<_>>()
                    .join("\n")
            }
        } else {
            report
                .errors
                .iter()
                .map(|e| format!("[错误] {}", e.message))
                .collect::<Vec<_>>()
                .join("\n")
        }
    }

    /// 根据校验报告统一更新现有属性。
    fn apply_validation_report(
        &self,
        config: Option<ExamConfig>,
        config_json: String,
        report: parser::ValidationReport,
    ) {
        let valid = report.errors.is_empty();
        let error_text = Self::format_report_errors(&report);
        let report_json = serde_json::to_string(&report).unwrap_or_default();

        *self._config.lock().unwrap() = config;
        *self._config_json.lock().unwrap() = config_json;
        *self._valid.lock().unwrap() = valid;
        *self._error.lock().unwrap() = error_text;
        *self._validation_report_json.lock().unwrap() = report_json;

        self.emit_all();
        self.validationReportJsonChanged();
        self.update_exam_preview(-1);
    }

    /// 添加文件路径到最近文件列表，移到最前并去重，最多保留 10 条。
    fn addRecentFile(&self, path: QString) {
        self.ensure_recent_files_loaded();
        let path_str = strip_file_prefix(&path.to_string());

        {
            let mut files = self._recent_files.lock().unwrap();
            Self::maintain_recent_files(&mut files, path_str);
        }

        self.persist_recent_files_internal();
        self.recentFilesJsonChanged();
    }

    /// 结构化校验配置，并更新报告与现有属性。
    fn validateConfigWithDetails(&self, json: QString) -> bool {
        let json_str = json.to_string();
        match serde_json::from_str::<ExamConfig>(&json_str) {
            Ok(config) => {
                let report = parser::validate_exam_config_with_details(&config);
                let pretty = serde_json::to_string_pretty(&config).unwrap_or(json_str);
                self.apply_validation_report(Some(config), pretty, report.clone());
                report.errors.is_empty()
            }
            Err(e) => {
                let report =
                    parser::ValidationReport::single_error("json", format!("JSON 解析失败: {}", e));
                self.apply_validation_report(None, json_str, report);
                false
            }
        }
    }

    /// 从 .aeterna/.json 文件导入配置。
    fn importFromFile(&self, path: QString) -> bool {
        let path_str = strip_file_prefix(&path.to_string());
        let content = match std::fs::read_to_string(&path_str) {
            Ok(c) => c,
            Err(e) => {
                let report = parser::ValidationReport::single_error(
                    "file",
                    format!("无法读取文件 {}: {}", path_str, e),
                );
                self.apply_validation_report(None, String::new(), report);
                return false;
            }
        };

        match serde_json::from_str::<ExamConfig>(&content) {
            Ok(config) => {
                let report = parser::validate_exam_config_with_details(&config);
                if !report.errors.is_empty() {
                    let pretty = serde_json::to_string_pretty(&config).unwrap_or(content);
                    self.apply_validation_report(Some(config), pretty, report);
                    return false;
                }
                let pretty = serde_json::to_string_pretty(&config).unwrap_or(content);
                self.apply_validation_report(Some(config), pretty, report);
                *self._unsaved.lock().unwrap() = true;
                *self._file_path.lock().unwrap() = String::new();
                self.unsavedChanged();
                self.currentFilePathChanged();
                self.addRecentFile(QString::from(path_str.as_str()));
                true
            }
            Err(e) => {
                let report =
                    parser::ValidationReport::single_error("json", format!("JSON 解析失败: {}", e));
                self.apply_validation_report(None, String::new(), report);
                false
            }
        }
    }

    /// 将 JSON 格式化后导出到指定路径。
    fn exportToFile(&self, path: QString, json: QString) -> bool {
        let path_str = strip_file_prefix(&path.to_string());
        let json_str = json.to_string();

        let pretty = match serde_json::from_str::<serde_json::Value>(&json_str) {
            Ok(value) => serde_json::to_string_pretty(&value).unwrap_or(json_str),
            Err(_) => json_str,
        };

        if let Some(parent) = Path::new(&path_str).parent() {
            if std::fs::create_dir_all(parent).is_err() {
                return false;
            }
        }

        std::fs::write(&path_str, pretty).is_ok()
    }

    /// 按考试开始时间对配置进行排序，返回排序后的格式化 JSON。
    fn sortExamInfos(&self, json: QString) -> QString {
        let json_str = json.to_string();
        match serde_json::from_str::<ExamConfig>(&json_str) {
            Ok(config) => {
                let sorted = parser::sort_exam_config_by_start(config);
                QString::from(
                    serde_json::to_string_pretty(&sorted)
                        .unwrap_or_default()
                        .as_str(),
                )
            }
            Err(_) => QString::from(""),
        }
    }

    /// 请求关闭窗口，触发 QML 处理关闭逻辑。
    fn requestClose(&self) {
        self.closeWindowRequested();
    }

    /// 确认关闭窗口。save=true 时尝试保存当前文件。
    fn confirmClose(&self, save: bool) -> bool {
        if !save {
            return true;
        }
        let path = self._file_path.lock().unwrap().clone();
        if path.is_empty() {
            return false;
        }
        let json = QString::from(self._config_json.lock().unwrap().as_str());
        self.saveToFile(QString::from(path.as_str()), json)
    }
}
