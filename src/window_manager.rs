//! 窗口管理器 — 多窗口管理和 Deep Link 协议处理。
//!
//! WindowManager is a planned future feature, hence `#[allow(dead_code)]`.
#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Mutex;
use std::path::PathBuf;
use crate::core::utils::aeterna_config_dir;

/// 窗口信息
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct WindowInfo {
    pub id: String,
    pub title: String,
    pub window_type: WindowType,
    pub visible: bool,
}

/// 窗口类型
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum WindowType {
    Main,
    Editor,
    Player,
    Settings,
    Popover,
    Custom(String),
}

/// 单实例锁
///
/// 使用文件锁确保只有一个应用实例运行。
pub struct SingleInstanceLock {
    lock_file: PathBuf,
}

impl SingleInstanceLock {
    /// 尝试获取单实例锁
    ///
    /// 返回 Some(lock) 如果成功获取锁，None 如果已有实例在运行。
    pub fn acquire() -> Option<Self> {
        let lock_dir = aeterna_config_dir();

        // 确保目录存在
        if let Err(e) = std::fs::create_dir_all(&lock_dir) {
            ::log::warn!("Failed to create lock directory: {} -> using temp directory", e);
            // 如果创建失败，回退到临时目录
            let temp_dir = std::env::temp_dir().join("Aeterna");
            let _ = std::fs::create_dir_all(&temp_dir);
            return Self::acquire_in(&temp_dir);
        }

        Self::acquire_in(&lock_dir)
    }

    fn acquire_in(lock_dir: &std::path::Path) -> Option<Self> {
        let lock_file = lock_dir.join("aeterna.lock");

        // 如果锁文件存在，检查进程是否存活
        if lock_file.exists() {
            let stale = match std::fs::read_to_string(&lock_file) {
                Ok(content) => {
                    let pid: i32 = content.trim().parse().unwrap_or(0);
                    if pid > 0 && is_process_running(pid) {
                        false    // 进程存活，锁有效
                    } else {
                        true     // 进程已死，锁过期
                    }
                }
                Err(_) => true,  // 无法读取，视为过期
            };

            if stale {
                ::log::info!("Removing stale lock file");
                let _ = std::fs::remove_file(&lock_file);
            } else {
                // 真正的另一个实例在运行
                if let Ok(content) = std::fs::read_to_string(&lock_file) {
                    let pid: i32 = content.trim().parse().unwrap_or(0);
                    ::log::warn!(
                        "Another instance is already running (PID: {}).",
                        pid
                    );
                }
                focus_existing_window();
                return None;
            }
        }

        // 创建新的锁文件
        match std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&lock_file)
        {
            Ok(mut file) => {
                let pid = std::process::id();
                // 尝试写入 PID
                use std::io::Write;
                if writeln!(file, "{}", pid).is_err() {
                    ::log::error!("Failed to write PID to lock file");
                    // 即使写入失败，我们仍然认为我们持有锁（继续运行）
                }
                ::log::info!("Single instance lock acquired (PID: {})", pid);
                Some(SingleInstanceLock {
                    lock_file,
                })
            }
            Err(e) => {
                ::log::warn!("Failed to create lock file: {} -> continuing without lock", e);
                // 创建失败仍然继续运行（不阻止用户打开）
                Some(SingleInstanceLock {
                    lock_file: lock_dir.join("aeterna.lock"),
                })
            }
        }
    }

    /// 检查锁是否仍然有效
    #[allow(dead_code)]
    pub fn is_valid(&self) -> bool {
        self.lock_file.exists()
    }
}

impl Drop for SingleInstanceLock {
    fn drop(&mut self) {
        if self.lock_file.exists() {
            let _ = std::fs::remove_file(&self.lock_file);
            ::log::info!("Single instance lock released");
        }
    }
}

/// 检查进程是否仍在运行
fn is_process_running(pid: i32) -> bool {
    if pid <= 0 {
        return false;
    }
    // 在 Linux 上检查 /proc/<pid> 是否存在
    let proc_path = format!("/proc/{}", pid);
    std::path::Path::new(&proc_path).exists()
}

/// 尝试聚焦已有窗口（平台特定）
fn focus_existing_window() {
    // 在 Linux 上，我们可以使用 xdotool 或 wmctrl
    // 这里使用简单的日志记录，实际聚焦由系统托盘或窗口管理器处理
    ::log::info!("Attempting to focus existing window");
}

lazy_static::lazy_static! {
    /// 全局待处理的 Deep Link 动作。
    ///
    /// 用于在 Rust 与 QML 之间传递 deep link 动作。由于 deep link 可能在
    /// QML 加载前到达，先存入此全局变量，后续由 QML/Rust 通过
    /// `take_pending_deep_link` 读取并消费。
    pub static ref PENDING_DEEP_LINK: Mutex<Option<DeepLinkAction>> = Mutex::new(None);
}

/// 取出并清空当前待处理的 Deep Link 动作。
#[allow(dead_code)]
pub fn take_pending_deep_link() -> Option<DeepLinkAction> {
    PENDING_DEEP_LINK.lock().unwrap().take()
}

/// Deep Link 协议处理
///
/// 处理 aeterna:// 协议的 URL 解析和路由。
pub struct DeepLinkHandler;

/// 解析后的 Deep Link 动作
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum DeepLinkAction {
    /// 打开文件
    OpenFile(String),
    /// 启动播放器
    StartPlayer,
    /// 打开设置页面
    OpenSettings(String),
    /// 打开编辑器
    OpenEditor,
    /// 投屏到设备
    CastTo(String),
    /// 未知动作
    Unknown(String),
}

impl DeepLinkHandler {
    /// 注册自定义协议处理器
    ///
    /// 在支持的平台上注册 aeterna:// 协议。
    pub fn register_protocol() -> Result<(), String> {
        ::log::info!("Registering aeterna:// protocol handler");

        #[cfg(target_os = "linux")]
        {
            // Linux 上通过 .desktop 文件注册
            let desktop_dir = dirs::data_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("applications");

            if let Err(e) = std::fs::create_dir_all(&desktop_dir) {
                return Err(format!("创建 desktop 目录失败: {}", e));
            }

            let desktop_file = desktop_dir.join("aeterna-handler.desktop");
            let exec_path = std::env::current_exe()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| "aeterna".to_string());

            let content = format!(
                "[Desktop Entry]\n\
                 Type=Application\n\
                 Name=Aeterna Protocol Handler\n\
                 Exec={} --deep-link %u\n\
                 StartupNotify=false\n\
                 MimeType=x-scheme-handler/aeterna;\n\
                 NoDisplay=true\n",
                exec_path
            );

            std::fs::write(&desktop_file, content)
                .map_err(|e| format!("写入 desktop 文件失败: {}", e))?;

            ::log::info!("Protocol handler registered at {:?}", desktop_file);
        }

        #[cfg(target_os = "macos")]
        {
            ::log::info!("Protocol registration on macOS is handled via Info.plist");
        }

        #[cfg(target_os = "windows")]
        {
            ::log::info!("Protocol registration on Windows is handled via registry");
        }

        Ok(())
    }

    /// 解析 aeterna:// URL 并返回对应的动作
    ///
    /// 支持的 URL 格式：
    /// - aeterna://open?file=/path/to/config.aeterna
    /// - aeterna://player
    /// - aeterna://settings?category=time
    /// - aeterna://editor
    /// - aeterna://cast?device=192.168.1.100
    #[allow(dead_code)]
    pub fn parse_url(url: &str) -> DeepLinkAction {
        if !url.starts_with("aeterna://") {
            return DeepLinkAction::Unknown(url.to_string());
        }

        let rest = &url["aeterna://".len()..];
        let (action, params) = if let Some(pos) = rest.find('?') {
            (&rest[..pos], &rest[pos + 1..])
        } else {
            (rest, "")
        };

        // 解析查询参数
        let query_params: HashMap<String, String> = if !params.is_empty() {
            params
                .split('&')
                .filter_map(|pair| {
                    let mut parts = pair.splitn(2, '=');
                    let key = parts.next()?.to_string();
                    let value = parts.next().unwrap_or("").to_string();
                    Some((key, value))
                })
                .collect()
        } else {
            HashMap::new()
        };

        match action {
            "open" => {
                let file_path = query_params
                    .get("file")
                    .cloned()
                    .unwrap_or_default();
                DeepLinkAction::OpenFile(file_path)
            }
            "player" => DeepLinkAction::StartPlayer,
            "settings" => {
                let category = query_params
                    .get("category")
                    .cloned()
                    .unwrap_or_else(|| "basic".to_string());
                DeepLinkAction::OpenSettings(category)
            }
            "editor" => DeepLinkAction::OpenEditor,
            "cast" => {
                let device = query_params
                    .get("device")
                    .cloned()
                    .unwrap_or_default();
                DeepLinkAction::CastTo(device)
            }
            _ => DeepLinkAction::Unknown(url.to_string()),
        }
    }

    /// 处理 Deep Link
    ///
    /// 根据解析后的动作执行相应的操作。解析后的动作会存入全局
    /// `PENDING_DEEP_LINK`，供 QML 或后续 Rust 代码通过
    /// `take_pending_deep_link` 读取。
    #[allow(dead_code)]
    pub fn handle_deep_link(url: &str) -> Result<(), String> {
        let action = Self::parse_url(url);

        ::log::info!("Handling deep link: {} -> {:?}", url, action);

        match &action {
            DeepLinkAction::OpenFile(file_path) => {
                if file_path.is_empty() {
                    return Err("缺少文件路径参数".to_string());
                }
                ::log::info!("Opening file via deep link: {}", file_path);
            }
            DeepLinkAction::StartPlayer => {
                ::log::info!("Starting player via deep link");
            }
            DeepLinkAction::OpenSettings(category) => {
                ::log::info!("Opening settings (category: {}) via deep link", category);
            }
            DeepLinkAction::OpenEditor => {
                ::log::info!("Opening editor via deep link");
            }
            DeepLinkAction::CastTo(device) => {
                if device.is_empty() {
                    return Err("缺少设备地址参数".to_string());
                }
                ::log::info!("Casting to device via deep link: {}", device);
            }
            DeepLinkAction::Unknown(url) => {
                ::log::warn!("Unknown deep link: {}", url);
            }
        }

        *PENDING_DEEP_LINK.lock().unwrap() = Some(action);
        Ok(())
    }
}

/// 窗口管理器
#[allow(dead_code)]
pub struct WindowManager {
    windows: Mutex<HashMap<String, WindowInfo>>,
    counter: Mutex<u64>,
}

impl WindowManager {
    /// 创建新的窗口管理器。
    pub fn new() -> Self {
        WindowManager {
            windows: Mutex::new(HashMap::new()),
            counter: Mutex::new(0),
        }
    }

    /// 注册一个新窗口，返回分配的窗口 ID。
    pub fn register(&self, title: String, window_type: WindowType) -> String {
        let mut counter = self.counter.lock().unwrap();
        *counter += 1;
        let id = format!("window-{}", counter);

        let info = WindowInfo {
            id: id.clone(),
            title,
            window_type,
            visible: false,
        };

        if let Ok(mut windows) = self.windows.lock() {
            windows.insert(id.clone(), info);
        }

        ::log::info!("Window registered: {}", id);
        id
    }

    /// 注销指定窗口。
    pub fn unregister(&self, id: &str) {
        if let Ok(mut windows) = self.windows.lock() {
            if windows.remove(id).is_some() {
                ::log::info!("Window unregistered: {}", id);
            }
        }
    }

    /// 将窗口标记为可见。
    pub fn show(&self, id: &str) {
        if let Ok(mut windows) = self.windows.lock() {
            if let Some(info) = windows.get_mut(id) {
                info.visible = true;
            }
        }
    }

    /// 将窗口标记为隐藏。
    pub fn hide(&self, id: &str) {
        if let Ok(mut windows) = self.windows.lock() {
            if let Some(info) = windows.get_mut(id) {
                info.visible = false;
            }
        }
    }

    /// 获取所有注册的窗口信息。
    pub fn get_all(&self) -> Vec<WindowInfo> {
        self.windows
            .lock()
            .map(|w| w.values().cloned().collect())
            .unwrap_or_default()
    }

    pub fn get_by_type(&self, window_type: WindowType) -> Vec<WindowInfo> {
        self.windows
            .lock()
            .map(|w| {
                w.values()
                    .filter(|info| info.window_type == window_type)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn count(&self) -> usize {
        self.windows.lock().map(|w| w.len()).unwrap_or(0)
    }

    pub fn count_by_type(&self, window_type: WindowType) -> usize {
        self.windows
            .lock()
            .map(|w| {
                w.values()
                    .filter(|info| info.window_type == window_type)
                    .count()
            })
            .unwrap_or(0)
    }

    pub fn close_all_by_type(&self, window_type: WindowType) {
        if let Ok(mut windows) = self.windows.lock() {
            let ids: Vec<String> = windows
                .iter()
                .filter(|(_, info)| info.window_type == window_type)
                .map(|(id, _)| id.clone())
                .collect();

            for id in ids {
                windows.remove(&id);
                ::log::info!("Closed window: {}", id);
            }
        }
    }

    pub fn close_all(&self) {
        if let Ok(mut windows) = self.windows.lock() {
            let count = windows.len();
            windows.clear();
            ::log::info!("Closed all {} windows", count);
        }
    }
}

impl Default for WindowManager {
    fn default() -> Self {
        Self::new()
    }
}

lazy_static::lazy_static! {
    pub static ref WINDOW_MANAGER: WindowManager = WindowManager::new();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_window() {
        let manager = WindowManager::new();
        let id = manager.register("Test Window".to_string(), WindowType::Main);
        assert!(!id.is_empty());
        assert_eq!(manager.count(), 1);
    }

    #[test]
    fn test_unregister_window() {
        let manager = WindowManager::new();
        let id = manager.register("Test".to_string(), WindowType::Editor);
        assert_eq!(manager.count(), 1);
        manager.unregister(&id);
        assert_eq!(manager.count(), 0);
    }

    #[test]
    fn test_count_by_type() {
        let manager = WindowManager::new();
        manager.register("Main".to_string(), WindowType::Main);
        manager.register("Editor".to_string(), WindowType::Editor);
        manager.register("Player".to_string(), WindowType::Player);

        assert_eq!(manager.count_by_type(WindowType::Main), 1);
        assert_eq!(manager.count_by_type(WindowType::Editor), 1);
        assert_eq!(manager.count_by_type(WindowType::Settings), 0);
    }

    #[test]
    fn test_show_hide() {
        let manager = WindowManager::new();
        let id = manager.register("Test".to_string(), WindowType::Main);

        manager.show(&id);
        let windows = manager.get_all();
        assert!(windows[0].visible);

        manager.hide(&id);
        let windows = manager.get_all();
        assert!(!windows[0].visible);
    }

    #[test]
    fn test_close_all_by_type() {
        let manager = WindowManager::new();
        manager.register("E1".to_string(), WindowType::Editor);
        manager.register("E2".to_string(), WindowType::Editor);
        manager.register("P1".to_string(), WindowType::Player);

        assert_eq!(manager.count(), 3);
        manager.close_all_by_type(WindowType::Editor);
        assert_eq!(manager.count(), 1);
        assert_eq!(manager.count_by_type(WindowType::Player), 1);
    }

    #[test]
    fn test_deep_link_parse_open() {
        let action = DeepLinkHandler::parse_url("aeterna://open?file=/path/to/config.aeterna");
        assert_eq!(action, DeepLinkAction::OpenFile("/path/to/config.aeterna".to_string()));
    }

    #[test]
    fn test_deep_link_parse_player() {
        let action = DeepLinkHandler::parse_url("aeterna://player");
        assert_eq!(action, DeepLinkAction::StartPlayer);
    }

    #[test]
    fn test_deep_link_parse_settings() {
        let action = DeepLinkHandler::parse_url("aeterna://settings?category=time");
        assert_eq!(action, DeepLinkAction::OpenSettings("time".to_string()));
    }

    #[test]
    fn test_deep_link_parse_editor() {
        let action = DeepLinkHandler::parse_url("aeterna://editor");
        assert_eq!(action, DeepLinkAction::OpenEditor);
    }

    #[test]
    fn test_deep_link_parse_cast() {
        let action = DeepLinkHandler::parse_url("aeterna://cast?device=192.168.1.100");
        assert_eq!(action, DeepLinkAction::CastTo("192.168.1.100".to_string()));
    }

    #[test]
    fn test_deep_link_parse_unknown() {
        let action = DeepLinkHandler::parse_url("aeterna://unknown");
        assert!(matches!(action, DeepLinkAction::Unknown(_)));
    }

    #[test]
    fn test_deep_link_parse_invalid_url() {
        let action = DeepLinkHandler::parse_url("https://example.com");
        assert!(matches!(action, DeepLinkAction::Unknown(_)));
    }

    #[test]
    fn test_deep_link_handle_open() {
        let result = DeepLinkHandler::handle_deep_link("aeterna://open?file=/test.aeterna");
        assert!(result.is_ok());
    }

    #[test]
    fn test_deep_link_handle_open_empty() {
        let result = DeepLinkHandler::handle_deep_link("aeterna://open");
        assert!(result.is_err());
    }

    #[test]
    fn test_deep_link_handle_cast_empty() {
        let result = DeepLinkHandler::handle_deep_link("aeterna://cast");
        assert!(result.is_err());
    }
}