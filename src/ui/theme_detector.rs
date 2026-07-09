use qmetaobject::*;
use std::process::Command;
use std::sync::Mutex;

/// 系统主题检测器 — 通过 gsettings / xdg-desktop-portal 检测 OS 深色模式偏好
#[derive(QObject, Default)]
pub struct ThemeDetector {
    base: qt_base_class!(trait QObject),

    system_prefers_dark: qt_property!(bool; READ system_prefers_dark NOTIFY system_prefers_dark_changed),
    system_theme_available: qt_property!(bool; READ system_theme_available),

    detect: qt_method!(fn(&self) -> bool),
    refresh: qt_method!(fn(&self)),

    system_prefers_dark_changed: qt_signal!(),
    _system_prefers_dark: Mutex<bool>,
    _system_theme_available: Mutex<bool>,
}

impl ThemeDetector {
    fn system_prefers_dark(&self) -> bool {
        *self._system_prefers_dark.lock().unwrap()
    }

    fn system_theme_available(&self) -> bool {
        *self._system_theme_available.lock().unwrap()
    }

    fn set_prefers_dark(&self, value: bool) {
        let mut val = self._system_prefers_dark.lock().unwrap();
        if *val != value {
            *val = value;
            self.system_prefers_dark_changed();
        }
    }

    /// 检测系统主题偏好，更新内部状态，返回检测结果
    pub fn detect(&self) -> bool {
        let (dark, available) = Self::detect_system_theme();
        *self._system_theme_available.lock().unwrap() = available;
        self.set_prefers_dark(dark);
        dark
    }

    /// 被 QML 定时器调用的刷新方法
    /// 仅当检测结果变化时触发信号
    pub fn refresh(&self) {
        self.detect();
    }

    /// 底层检测逻辑：
    /// 1. 尝试 gsettings（GNOME / Xfce / Cinnamon）
    /// 2. 尝试 xdg-desktop-portal 环境变量
    /// 3. 降级为默认深色
    fn detect_system_theme() -> (bool, bool) {
        // 方案 1：gsettings（覆盖 GNOME / Budgie / Pop!_OS / Xfce 等）
        if let Ok(output) = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", "color-scheme"])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.contains("prefer-dark") {
                return (true, true);
            }
            if stdout.contains("default") || stdout.contains("prefer-light") {
                return (false, true);
            }
        }

        // 方案 2：gsettings gtk-theme（部分 DE 不支持 color-scheme 键）
        if let Ok(output) = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", "gtk-theme"])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout).to_lowercase();
            if stdout.contains("dark") {
                return (true, true);
            }
        }

        // 方案 3：检查 GTK_THEME 环境变量
        if let Ok(theme) = std::env::var("GTK_THEME") {
            if theme.to_lowercase().contains("dark") {
                return (true, true);
            }
        }

        // 方案 4：尝试 KDE 的 kreadconfig5
        if let Ok(output) = Command::new("kreadconfig5")
            .args([
                "--file", "kdeglobals",
                "--group", "General",
                "--key", "ColorScheme",
            ])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout).to_lowercase();
            if stdout.contains("dark") {
                return (true, true);
            }
        }

        // 降级：默认深色模式
        (true, false)
    }
}