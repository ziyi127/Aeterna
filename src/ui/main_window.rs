use qmetaobject::*;

/// 注册所有 QML 类型到引擎
pub fn register_types(engine: &mut QmlEngine) {
    ui_backend::register_to_qml(engine);
}

#[allow(dead_code)]
mod ui_backend {
    use qmetaobject::*;
    use std::sync::Mutex;
    use crate::core::parser;
    use crate::core::types::ExamConfig;
    use crate::core::utils::aeterna_config_dir;

    /// 应用信息后端
    #[derive(QObject, Default)]
    pub struct AppInfo {
        base: qt_base_class!(trait QObject),
        version: qt_property!(QString; READ version NOTIFY version_changed),
        name: qt_property!(QString; READ name),
        version_changed: qt_signal!(),
    }

    impl AppInfo {
        fn version(&self) -> QString {
            QString::from(env!("CARGO_PKG_VERSION"))
        }

        fn name(&self) -> QString {
            QString::from("Aeterna")
        }
    }

    /// 导航管理器
    #[derive(QObject, Default)]
    pub struct NavigationManager {
        base: qt_base_class!(trait QObject),
        current_page: qt_property!(i32; READ current_page WRITE set_current_page NOTIFY current_page_changed),
        current_page_changed: qt_signal!(),
        _current_page_value: Mutex<i32>,
    }

    impl NavigationManager {
        fn current_page(&self) -> i32 {
            *self._current_page_value.lock().unwrap()
        }

        fn set_current_page(&self, page: i32) {
            let mut val = self._current_page_value.lock().unwrap();
            if *val != page {
                *val = page;
                self.current_page_changed();
            }
        }
    }

    /// 考试配置管理器
    #[derive(QObject, Default)]
    pub struct ConfigManager {
        base: qt_base_class!(trait QObject),
        config_json: qt_property!(QString; READ config_json WRITE set_config_json NOTIFY config_json_changed),
        config_valid: qt_property!(bool; READ config_valid NOTIFY config_valid_changed),
        exam_count: qt_property!(i32; READ exam_count NOTIFY exam_count_changed),

        config_json_changed: qt_signal!(),
        config_valid_changed: qt_signal!(),
        exam_count_changed: qt_signal!(),

        _config: Mutex<Option<ExamConfig>>,
        _config_json: Mutex<String>,
    }

    impl ConfigManager {
        fn config_json(&self) -> QString {
            QString::from(self._config_json.lock().unwrap().as_str())
        }

        fn set_config_json(&self, json: QString) {
            let json_str = json.to_string();
            *self._config_json.lock().unwrap() = json_str.clone();
            self.config_json_changed();

            match parser::parse_exam_config(&json_str) {
                Some(config) => {
                    if parser::validate_exam_config(&config) {
                        let count = config.exam_infos.len() as i32;
                        *self._config.lock().unwrap() = Some(config);
                        self.set_exam_count(count);
                        self.set_config_valid(true);
                    } else {
                        *self._config.lock().unwrap() = None;
                        self.set_config_valid(false);
                    }
                }
                None => {
                    *self._config.lock().unwrap() = None;
                    self.set_config_valid(false);
                }
            }
        }

        fn config_valid(&self) -> bool {
            self._config.lock().unwrap().is_some()
        }

        fn exam_count(&self) -> i32 {
            self._config.lock().unwrap()
                .as_ref()
                .map(|c| c.exam_infos.len() as i32)
                .unwrap_or(0)
        }

        fn set_config_valid(&self, _valid: bool) {
            self.config_valid_changed();
        }

        fn set_exam_count(&self, _count: i32) {
            self.exam_count_changed();
        }

        #[allow(dead_code)]
        pub fn get_config(&self) -> Option<ExamConfig> {
            self._config.lock().unwrap().clone()
        }
    }

    /// 最近文件模型
    #[derive(QObject, Default)]
    pub struct RecentFilesModel {
        base: qt_base_class!(trait QObject),
        recent_files_json: qt_property!(QString; READ recent_files_json NOTIFY recent_files_json_changed),
        recent_files_json_changed: qt_signal!(),
    }

    impl RecentFilesModel {
        fn recent_files_json(&self) -> QString {
            let path = aeterna_config_dir().join("recent_files.json");

            match std::fs::read_to_string(&path) {
                Ok(content) => QString::from(content.as_str()),
                Err(_) => QString::from("[]"),
            }
        }
    }

    pub fn register_to_qml(_engine: &mut QmlEngine) {
        macro_rules! register {
            ($ty:ty, $name:literal) => {
                qml_register_type::<$ty>(
                    &std::ffi::CString::new("Aeterna").unwrap(),
                    1, 0,
                    &std::ffi::CString::new($name).unwrap(),
                );
            };
        }

        register!(AppInfo, "AppInfo");
        register!(NavigationManager, "NavigationManager");
        register!(ConfigManager, "ConfigManager");
        register!(RecentFilesModel, "RecentFilesModel");
        register!(crate::ui::discover_manager::DiscoverManager, "DiscoverManager");
        register!(crate::ui::player_window::PlayerBackend, "PlayerBackend");
        register!(crate::ui::editor_window::EditorBackend, "EditorBackend");
        register!(crate::ui::theme_detector::ThemeDetector, "ThemeDetector");
        register!(crate::ui::settings_window::SettingsBackend, "SettingsBackend");
    }
}
