//! 窗口管理器 — 多窗口管理和 Deep Link 协议处理。
//!
//! WindowManager 和 DeepLinkHandler 是规划中的功能，目前主要由测试
//! 驱动；外部仅 `DeepLinkHandler::register_protocol()` 在 main.rs 中被调用。
#![allow(dead_code)]

use crate::core::utils::aeterna_config_dir;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

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

/// 单实例锁。
///
/// 保持一个 OS 级排他文件锁直到进程退出；崩溃时内核自动释放该锁。
pub struct SingleInstanceLock {
    file: std::fs::File,
}

impl SingleInstanceLock {
    /// 返回 `Ok(None)` 仅表示已有实例持有锁；其他 I/O 失败必须由调用方处理。
    pub fn acquire(force: bool) -> std::io::Result<Option<Self>> {
        if force {
            ::log::warn!("--force no longer bypasses the single-instance lock");
        }
        let lock_dir = aeterna_config_dir();
        std::fs::create_dir_all(&lock_dir)?;
        Self::acquire_in(&lock_dir)
    }

    fn acquire_in(lock_dir: &std::path::Path) -> std::io::Result<Option<Self>> {
        use fs4::fs_std::FileExt;

        let lock_file = lock_dir.join("aeterna.lock");
        let file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(lock_file)?;
        match file.try_lock_exclusive() {
            Ok(true) => {
                ::log::info!("Single instance lock acquired");
                Ok(Some(Self { file }))
            }
            Ok(false) => {
                focus_existing_window();
                Ok(None)
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                focus_existing_window();
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }

    /// The retained handle proves ownership of the kernel lock.
    pub fn is_valid(&self) -> bool {
        self.file.metadata().is_ok()
    }
}

/// 解析锁文件内容。
///
/// 新格式：第一行 PID，第二行 exe 路径
/// 旧格式：仅一行 PID（兼容旧版本锁文件）
fn parse_lock_content(content: &str) -> (i32, String) {
    let mut lines = content.lines();
    let pid: i32 = lines.next().unwrap_or("0").trim().parse().unwrap_or(0);
    let exe = lines
        .next()
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    (pid, exe)
}

/// 检查进程是否仍在运行，并验证可执行文件路径匹配（跨平台）。
///
/// - **Linux**：检查 `/proc/<pid>` 是否存在；若锁文件记录了可执行文件路径，
///   还会验证 `/proc/<pid>/exe` 指向的目标是否一致，防止 PID 复用导致的误判。
/// - **macOS / 其他类 Unix**：使用 `kill(pid, 0)` 探测进程是否存活。
/// - **Windows**：标准库无法无依赖地查询进程存活，保守地认为锁仍然有效
///   （崩溃后可用 `--force` 强制启动），以此保证单实例语义。
///
/// 旧实现仅使用 `/proc`，在 Windows/macOS 上恒返回 `false`，导致单实例锁
/// 完全失效（可无限启动多个实例）。本实现按平台分别处理。
#[cfg(target_os = "linux")]
fn is_process_running(pid: i32, lock_exe: &str) -> bool {
    if pid <= 0 {
        return false;
    }
    let proc_path = format!("/proc/{}", pid);
    if !std::path::Path::new(&proc_path).exists() {
        return false;
    }
    // 如果锁文件记录了 exe 路径，验证是否匹配
    if !lock_exe.is_empty() {
        let exe_link = format!("/proc/{}/exe", pid);
        if let Ok(target) = std::fs::read_link(&exe_link) {
            let target_str = target.to_string_lossy();
            if target_str != lock_exe {
                ::log::info!(
                    "PID {} path mismatch: lock says '{}', but /proc/{}/exe -> '{}'",
                    pid,
                    lock_exe,
                    pid,
                    target_str
                );
                return false;
            }
        }
        // 如果无法读取 /proc/pid/exe（权限不足等），保守认为进程存在
    }
    true
}

#[cfg(all(unix, not(target_os = "linux")))]
fn is_process_running(pid: i32, _lock_exe: &str) -> bool {
    if pid <= 0 {
        return false;
    }
    // macOS / *BSD 等：kill(pid, 0) 在进程存在且有权限时返回 0。
    unsafe { libc::kill(pid, 0) == 0 }
}

#[cfg(windows)]
fn is_process_running(_pid: i32, _lock_exe: &str) -> bool {
    // 无法无依赖地查询进程存活，保守认定锁有效。
    true
}

/// 聚焦已有实例的窗口。
///
/// 在 Linux 上尝试使用 xdotool 搜索并激活窗口，
/// 同时发送桌面通知告知用户应用已在运行。
fn focus_existing_window() {
    ::log::info!("Attempting to focus existing window");

    #[cfg(target_os = "linux")]
    {
        // 尝试用 xdotool 按窗口类名搜索并聚焦
        let result = std::process::Command::new("xdotool")
            .args(["search", "--class", "aeterna", "windowactivate"])
            .output();

        match &result {
            Ok(output) if output.status.success() => {
                ::log::info!("Successfully focused existing window via xdotool");
                return;
            }
            Ok(output) => {
                ::log::debug!(
                    "xdotool search --class failed (exit {:?}), trying --name",
                    output.status.code()
                );
            }
            Err(e) => {
                ::log::debug!("xdotool not available: {}", e);
            }
        }

        // fallback: 按窗口标题搜索
        let result = std::process::Command::new("xdotool")
            .args(["search", "--name", "Aeterna", "windowactivate"])
            .output();

        if let Ok(output) = &result {
            if output.status.success() {
                ::log::info!("Successfully focused existing window via xdotool (name)");
                return;
            }
        }
    }

    ::log::warn!("Could not focus existing window — xdotool unavailable or window not found");
}

/// 发送桌面通知，告知用户 Aeterna 已在运行。
pub fn notify_already_running() {
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("notify-send")
            .args([
                "Aeterna",
                "Aeterna 已在运行中",
                "--icon=aeterna",
                "--app-name=Aeterna",
                "--hint=string:desktop-entry:aeterna",
            ])
            .spawn();
    }
}

/// 全局待处理的 Deep Link 动作。
///
/// 用于在 Rust 与 QML 之间传递 deep link 动作。由于 deep link 可能在
/// QML 加载前到达，先存入此全局变量，后续由 QML/Rust 通过
/// `take_pending_deep_link` 读取并消费。
pub static PENDING_DEEP_LINK: LazyLock<Mutex<Option<DeepLinkAction>>> =
    LazyLock::new(|| Mutex::new(None));

/// 取出并清空当前待处理的 Deep Link 动作。
pub fn take_pending_deep_link() -> Option<DeepLinkAction> {
    PENDING_DEEP_LINK.lock().unwrap().take()
}

fn percent_decode(value: &str) -> Option<String> {
    let mut decoded = Vec::with_capacity(value.len());
    let bytes = value.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => decoded.push(b' '),
            b'%' if index + 2 < bytes.len() => {
                let high = (bytes[index + 1] as char).to_digit(16)?;
                let low = (bytes[index + 2] as char).to_digit(16)?;
                decoded.push((high * 16 + low) as u8);
                index += 2;
            }
            b'%' => return None,
            byte => decoded.push(byte),
        }
        index += 1;
    }
    String::from_utf8(decoded).ok()
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

        // Decode query values once before routing; protocol URLs routinely
        // encode paths and category names.
        let query_params: HashMap<String, String> = if !params.is_empty() {
            params
                .split('&')
                .filter_map(|pair| {
                    let mut parts = pair.splitn(2, '=');
                    let key = percent_decode(parts.next()?)?;
                    let value = percent_decode(parts.next().unwrap_or(""))?;
                    Some((key, value))
                })
                .collect()
        } else {
            HashMap::new()
        };

        match action {
            "open" => {
                let file_path = query_params.get("file").cloned().unwrap_or_default();
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
                let device = query_params.get("device").cloned().unwrap_or_default();
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

pub static WINDOW_MANAGER: LazyLock<WindowManager> = LazyLock::new(WindowManager::new);

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
        assert_eq!(
            action,
            DeepLinkAction::OpenFile("/path/to/config.aeterna".to_string())
        );
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
