//! 插件系统
//!
//! 支持动态加载和管理插件，提供插件清单解析、服务注册和插件商店功能。
//!
//! 插件系统处于早期阶段，大量 API 目前仅由测试驱动，因此保留模块级
//! `#[allow(dead_code)]` 直到上游调用者就位。
#![allow(dead_code)]

use crate::core::utils::aeterna_config_dir;
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

/// 已注册的菜单项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisteredMenuItem {
    /// 注册此菜单的插件名称
    pub plugin_name: String,
    /// 菜单路径，如 "文件/导入" 或 "工具/自定义工具"
    pub menu_path: String,
    /// 菜单项标签
    pub label: String,
    /// 回调函数标识符（在 QML 侧通过信号连接实现）
    pub callback_id: String,
}

/// 已注册的页面
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisteredPage {
    /// 注册此页面的插件名称
    pub plugin_name: String,
    /// 页面 ID
    pub page_id: String,
    /// 页面标题
    pub title: String,
    /// 页面图标
    pub icon: String,
}

/// 已注册的服务
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisteredService {
    /// 注册此服务的插件名称
    pub plugin_name: String,
    /// 服务名称
    pub service_name: String,
    /// 服务标识符
    pub service_id: String,
}

/// 插件注入注册表
///
/// 管理插件注册的菜单项、页面和服务。
pub struct PluginRegistry {
    menus: Mutex<Vec<RegisteredMenuItem>>,
    pages: Mutex<Vec<RegisteredPage>>,
    services: Mutex<Vec<RegisteredService>>,
    callbacks: Mutex<HashMap<String, String>>,
}

impl PluginRegistry {
    fn new() -> Self {
        PluginRegistry {
            menus: Mutex::new(Vec::new()),
            pages: Mutex::new(Vec::new()),
            services: Mutex::new(Vec::new()),
            callbacks: Mutex::new(HashMap::new()),
        }
    }

    /// 注册菜单项
    pub fn register_menu_item(
        &self,
        plugin_name: &str,
        menu_path: &str,
        label: &str,
        callback_id: &str,
    ) -> Result<(), String> {
        let mut menus = self.menus.lock().map_err(|e| e.to_string())?;

        // 检查是否已存在相同路径的菜单项
        if menus
            .iter()
            .any(|m| m.menu_path == menu_path && m.label == label)
        {
            return Err(format!("菜单项 '{}' 已存在", menu_path));
        }

        menus.push(RegisteredMenuItem {
            plugin_name: plugin_name.to_string(),
            menu_path: menu_path.to_string(),
            label: label.to_string(),
            callback_id: callback_id.to_string(),
        });

        info!(
            "Plugin '{}' registered menu item: {} -> {}",
            plugin_name, menu_path, label
        );
        Ok(())
    }

    /// 注册页面
    pub fn register_page(
        &self,
        plugin_name: &str,
        page_id: &str,
        title: &str,
        icon: &str,
    ) -> Result<(), String> {
        let mut pages = self.pages.lock().map_err(|e| e.to_string())?;

        if pages.iter().any(|p| p.page_id == page_id) {
            return Err(format!("页面 '{}' 已存在", page_id));
        }

        pages.push(RegisteredPage {
            plugin_name: plugin_name.to_string(),
            page_id: page_id.to_string(),
            title: title.to_string(),
            icon: icon.to_string(),
        });

        info!(
            "Plugin '{}' registered page: {} ({})",
            plugin_name, page_id, title
        );
        Ok(())
    }

    /// 注册服务
    pub fn register_service(
        &self,
        plugin_name: &str,
        service_name: &str,
        service_id: &str,
    ) -> Result<(), String> {
        let mut services = self.services.lock().map_err(|e| e.to_string())?;

        if services.iter().any(|s| s.service_id == service_id) {
            return Err(format!("服务 '{}' 已存在", service_id));
        }

        services.push(RegisteredService {
            plugin_name: plugin_name.to_string(),
            service_name: service_name.to_string(),
            service_id: service_id.to_string(),
        });

        info!(
            "Plugin '{}' registered service: {} ({})",
            plugin_name, service_name, service_id
        );
        Ok(())
    }

    /// 注册回调函数
    pub fn register_callback(&self, callback_id: &str, qml_signal: &str) -> Result<(), String> {
        let mut callbacks = self.callbacks.lock().map_err(|e| e.to_string())?;
        callbacks.insert(callback_id.to_string(), qml_signal.to_string());
        Ok(())
    }

    /// 获取所有已注册的菜单项
    pub fn get_registered_menus(&self) -> Vec<RegisteredMenuItem> {
        self.menus.lock().map(|m| m.clone()).unwrap_or_default()
    }

    /// 获取所有已注册的页面
    pub fn get_registered_pages(&self) -> Vec<RegisteredPage> {
        self.pages.lock().map(|p| p.clone()).unwrap_or_default()
    }

    /// 获取所有已注册的服务
    pub fn get_registered_services(&self) -> Vec<RegisteredService> {
        self.services.lock().map(|s| s.clone()).unwrap_or_default()
    }

    /// 获取指定回调的 QML 信号
    pub fn get_callback(&self, callback_id: &str) -> Option<String> {
        self.callbacks.lock().ok()?.get(callback_id).cloned()
    }

    /// 注销指定插件的所有注册项
    pub fn unregister_plugin(&self, plugin_name: &str) {
        if let Ok(mut menus) = self.menus.lock() {
            menus.retain(|m| m.plugin_name != plugin_name);
        }
        if let Ok(mut pages) = self.pages.lock() {
            pages.retain(|p| p.plugin_name != plugin_name);
        }
        if let Ok(mut services) = self.services.lock() {
            services.retain(|s| s.plugin_name != plugin_name);
        }
        info!("Unregistered all items for plugin '{}'", plugin_name);
    }
}

/// 全局插件注册表
pub static PLUGIN_REGISTRY: LazyLock<PluginRegistry> = LazyLock::new(PluginRegistry::new);

/// 便捷的全局注册方法
pub mod injection {
    use super::*;

    pub fn register_menu_item(
        plugin_name: &str,
        menu_path: &str,
        label: &str,
        callback_id: &str,
    ) -> Result<(), String> {
        PLUGIN_REGISTRY.register_menu_item(plugin_name, menu_path, label, callback_id)
    }

    pub fn register_page(
        plugin_name: &str,
        page_id: &str,
        title: &str,
        icon: &str,
    ) -> Result<(), String> {
        PLUGIN_REGISTRY.register_page(plugin_name, page_id, title, icon)
    }

    pub fn register_service(
        plugin_name: &str,
        service_name: &str,
        service_id: &str,
    ) -> Result<(), String> {
        PLUGIN_REGISTRY.register_service(plugin_name, service_name, service_id)
    }

    pub fn get_registered_menus() -> Vec<RegisteredMenuItem> {
        PLUGIN_REGISTRY.get_registered_menus()
    }

    pub fn get_registered_pages() -> Vec<RegisteredPage> {
        PLUGIN_REGISTRY.get_registered_pages()
    }

    pub fn get_registered_services() -> Vec<RegisteredService> {
        PLUGIN_REGISTRY.get_registered_services()
    }
}

/// 插件清单
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginManifest {
    /// 插件名称
    pub name: String,
    /// 插件版本
    pub version: String,
    /// 插件描述
    pub description: String,
    /// 作者
    pub author: String,
    /// 许可证
    pub license: Option<String>,
    /// 入口文件
    pub main: Option<String>,
    /// 图标路径
    pub icon: Option<String>,
    /// 依赖项
    pub dependencies: HashMap<String, String>,
    /// 插件类型
    #[serde(rename = "type")]
    pub plugin_type: PluginType,
    /// 权限列表
    pub permissions: Vec<PluginPermission>,
}

/// 插件类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginType {
    #[serde(rename = "ui")]
    Ui,
    #[serde(rename = "service")]
    Service,
    #[serde(rename = "theme")]
    Theme,
    #[serde(rename = "extension")]
    Extension,
}

/// 插件权限
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginPermission {
    #[serde(rename = "read_config")]
    ReadConfig,
    #[serde(rename = "write_config")]
    WriteConfig,
    #[serde(rename = "network")]
    Network,
    #[serde(rename = "filesystem")]
    FileSystem,
    #[serde(rename = "display")]
    Display,
    #[serde(rename = "audio")]
    Audio,
}

/// 插件状态
#[derive(Debug, Clone, PartialEq)]
pub enum PluginState {
    /// 已安装但未加载
    Installed,
    /// 已加载
    Loaded,
    /// 已激活（运行中）
    Active,
    /// 已禁用
    Disabled,
    /// 错误
    Error(String),
}

/// 已安装的插件
#[derive(Debug, Clone)]
pub struct InstalledPlugin {
    /// 插件清单
    pub manifest: PluginManifest,
    /// 插件状态
    pub state: PluginState,
    /// 安装路径
    pub path: String,
    /// 安装时间
    pub installed_at: String,
}

/// 插件商店条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginStoreEntry {
    /// 插件名称
    pub name: String,
    /// 插件版本
    pub version: String,
    /// 描述
    pub description: String,
    /// 作者
    pub author: String,
    /// 下载 URL
    pub download_url: String,
    /// 评分
    pub rating: f64,
    /// 下载次数
    pub downloads: u64,
    /// 兼容版本
    pub compatible_version: String,
}

/// Read-only inventory result for local plugin manifests. Discovery never loads,
/// executes, installs, removes, or creates plugin directories.
#[derive(Debug, Clone, Default)]
pub struct DiscoveryResult {
    pub plugins: Vec<InstalledPlugin>,
    pub diagnostics: Vec<String>,
}

pub fn default_plugin_dir() -> PathBuf {
    aeterna_config_dir().join("plugins")
}

pub fn discover_default() -> DiscoveryResult {
    discover_from_root(&default_plugin_dir())
}

pub fn discover_from_root(root: &Path) -> DiscoveryResult {
    let mut result = DiscoveryResult::default();
    if !root.exists() {
        return result;
    }

    let entries = match std::fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) => {
            result
                .diagnostics
                .push(format!("无法读取插件目录: {}", error));
            return result;
        }
    };

    let mut candidates = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false))
        .collect::<Vec<_>>();
    candidates.sort_by_key(|entry| entry.file_name());

    let mut discovered = BTreeMap::<String, InstalledPlugin>::new();
    for entry in candidates {
        let manifest_path = entry.path().join("manifest.json");
        if !manifest_path.is_file() {
            continue;
        }
        let content = match std::fs::read_to_string(&manifest_path) {
            Ok(content) => content,
            Err(error) => {
                result
                    .diagnostics
                    .push(format!("无法读取 {}: {}", manifest_path.display(), error));
                continue;
            }
        };
        let manifest = match PluginManager::parse_manifest(&content) {
            Ok(manifest) => manifest,
            Err(error) => {
                result
                    .diagnostics
                    .push(format!("{}: {}", manifest_path.display(), error));
                continue;
            }
        };
        let name = manifest.name.clone();
        let plugin = InstalledPlugin {
            manifest,
            state: PluginState::Installed,
            path: entry.path().to_string_lossy().to_string(),
            installed_at: String::new(),
        };
        match discovered.entry(name) {
            std::collections::btree_map::Entry::Occupied(entry) => {
                result.diagnostics.push(format!(
                    "发现重复插件清单 '{}'; 保留排序靠前的目录",
                    entry.key()
                ));
            }
            std::collections::btree_map::Entry::Vacant(entry) => {
                entry.insert(plugin);
            }
        }
    }

    result.plugins = discovered.into_values().collect();
    result
}

/// 插件管理器
pub struct PluginManager {
    plugins: Mutex<HashMap<String, InstalledPlugin>>,
    plugin_dir: Mutex<String>,
}

impl PluginManager {
    /// 创建新的插件管理器
    pub fn new() -> Self {
        let plugin_dir = aeterna_config_dir()
            .join("plugins")
            .to_string_lossy()
            .to_string();

        PluginManager {
            plugins: Mutex::new(HashMap::new()),
            plugin_dir: Mutex::new(plugin_dir),
        }
    }

    /// 使用自定义插件目录创建
    pub fn with_dir(plugin_dir: String) -> Self {
        PluginManager {
            plugins: Mutex::new(HashMap::new()),
            plugin_dir: Mutex::new(plugin_dir),
        }
    }

    /// 加载插件目录中的所有插件
    pub fn load_all(&self) -> Result<usize, String> {
        let plugin_dir = self.plugin_dir.lock().map_err(|e| e.to_string())?.clone();
        let path = std::path::Path::new(&plugin_dir);

        if !path.exists() {
            std::fs::create_dir_all(path).map_err(|e| format!("创建插件目录失败: {}", e))?;
            info!("Created plugin directory: {}", plugin_dir);
            return Ok(0);
        }

        let mut loaded = 0;
        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let manifest_path = entry.path().join("manifest.json");
                if manifest_path.exists() {
                    match self.load_plugin(&entry.path()) {
                        Ok(_) => loaded += 1,
                        Err(e) => warn!("Failed to load plugin at {:?}: {}", entry.path(), e),
                    }
                }
            }
        }

        info!("Loaded {} plugins from {}", loaded, plugin_dir);
        Ok(loaded)
    }

    /// 加载单个插件
    fn load_plugin(&self, path: &std::path::Path) -> Result<(), String> {
        let manifest_path = path.join("manifest.json");
        let manifest_content = std::fs::read_to_string(&manifest_path)
            .map_err(|e| format!("读取 manifest.json 失败: {}", e))?;

        let manifest: PluginManifest = serde_json::from_str(&manifest_content)
            .map_err(|e| format!("解析 manifest.json 失败: {}", e))?;

        let installed = InstalledPlugin {
            manifest: manifest.clone(),
            state: PluginState::Installed,
            path: path.to_string_lossy().to_string(),
            installed_at: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        };

        if let Ok(mut plugins) = self.plugins.lock() {
            plugins.insert(manifest.name.clone(), installed);
        }

        info!("Loaded plugin: {} v{}", manifest.name, manifest.version);
        Ok(())
    }

    /// 安装插件
    pub fn install(&self, name: &str, _manifest: &PluginManifest) -> Result<(), String> {
        let plugin_dir = self.plugin_dir.lock().map_err(|e| e.to_string())?.clone();
        let install_path = std::path::Path::new(&plugin_dir).join(name);

        if install_path.exists() {
            return Err(format!("插件 {} 已安装", name));
        }

        std::fs::create_dir_all(&install_path).map_err(|e| format!("创建插件目录失败: {}", e))?;

        info!("Plugin {} installed at {:?}", name, install_path);
        Ok(())
    }

    /// 卸载插件
    pub fn uninstall(&self, name: &str) -> Result<(), String> {
        let plugin_dir = self.plugin_dir.lock().map_err(|e| e.to_string())?.clone();
        let install_path = std::path::Path::new(&plugin_dir).join(name);

        if install_path.exists() {
            std::fs::remove_dir_all(&install_path)
                .map_err(|e| format!("删除插件目录失败: {}", e))?;
        }

        if let Ok(mut plugins) = self.plugins.lock() {
            plugins.remove(name);
        }

        info!("Plugin {} uninstalled", name);
        Ok(())
    }

    /// 激活插件
    pub fn activate(&self, name: &str) -> Result<(), String> {
        self.set_state(name, PluginState::Active, "activated")
    }

    /// 禁用插件
    pub fn disable(&self, name: &str) -> Result<(), String> {
        self.set_state(name, PluginState::Disabled, "disabled")
    }

    /// 统一的插件状态切换实现，供 activate/disable 复用。
    fn set_state(&self, name: &str, state: PluginState, action: &str) -> Result<(), String> {
        if let Ok(mut plugins) = self.plugins.lock() {
            if let Some(plugin) = plugins.get_mut(name) {
                plugin.state = state;
                info!("Plugin {} {}", name, action);
                Ok(())
            } else {
                Err(format!("插件 {} 未找到", name))
            }
        } else {
            Err("插件列表锁定失败".to_string())
        }
    }

    /// 获取所有已安装插件
    pub fn get_all(&self) -> Vec<InstalledPlugin> {
        self.plugins
            .lock()
            .map(|p| p.values().cloned().collect())
            .unwrap_or_default()
    }

    /// 获取指定插件
    pub fn get(&self, name: &str) -> Option<InstalledPlugin> {
        self.plugins.lock().ok()?.get(name).cloned()
    }

    /// 解析插件清单
    pub fn parse_manifest(json: &str) -> Result<PluginManifest, String> {
        serde_json::from_str(json).map_err(|e| format!("解析插件清单失败: {}", e))
    }

    /// 获取插件商店列表（模拟数据）
    pub fn get_store_entries() -> Vec<PluginStoreEntry> {
        vec![
            PluginStoreEntry {
                name: "主题切换器".to_string(),
                version: "1.0.0".to_string(),
                description: "提供多种主题样式切换".to_string(),
                author: "Aeterna Community".to_string(),
                download_url: "https://plugins.aeterna.app/themeswitcher".to_string(),
                rating: 4.5,
                downloads: 1200,
                compatible_version: "1.3.0".to_string(),
            },
            PluginStoreEntry {
                name: "语音播报".to_string(),
                version: "0.9.0".to_string(),
                description: "考试开始/结束语音提醒".to_string(),
                author: "Aeterna Community".to_string(),
                download_url: "https://plugins.aeterna.app/voice".to_string(),
                rating: 4.2,
                downloads: 800,
                compatible_version: "1.3.0".to_string(),
            },
            PluginStoreEntry {
                name: "数据统计".to_string(),
                version: "1.1.0".to_string(),
                description: "考试数据分析和统计报表".to_string(),
                author: "Aeterna Official".to_string(),
                download_url: "https://plugins.aeterna.app/stats".to_string(),
                rating: 4.8,
                downloads: 2100,
                compatible_version: "1.3.0".to_string(),
            },
        ]
    }
}

impl Default for PluginManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovery_of_missing_directory_is_empty_and_read_only() {
        let root = std::env::temp_dir().join(format!(
            "aeterna-plugin-discovery-missing-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);

        let result = discover_from_root(&root);
        assert!(result.plugins.is_empty());
        assert!(result.diagnostics.is_empty());
        assert!(!root.exists());
    }

    #[test]
    fn test_plugin_manager_creation() {
        let manager = PluginManager::new();
        let plugins = manager.get_all();
        assert!(plugins.is_empty());
    }

    #[test]
    fn test_parse_manifest() {
        let json = r#"{
            "name": "test-plugin",
            "version": "1.0.0",
            "description": "A test plugin",
            "author": "Test Author",
            "dependencies": {},
            "type": "ui",
            "permissions": ["read_config"]
        }"#;

        let manifest = PluginManager::parse_manifest(json);
        assert!(manifest.is_ok());
        let manifest = manifest.unwrap();
        assert_eq!(manifest.name, "test-plugin");
        assert_eq!(manifest.version, "1.0.0");
        assert_eq!(manifest.plugin_type, PluginType::Ui);
        assert_eq!(manifest.permissions.len(), 1);
    }

    #[test]
    fn test_parse_manifest_invalid() {
        let result = PluginManager::parse_manifest("not valid json");
        assert!(result.is_err());
    }

    #[test]
    fn test_store_entries() {
        let entries = PluginManager::get_store_entries();
        assert!(!entries.is_empty());
        assert!(entries.iter().any(|e| e.name == "主题切换器"));
    }

    #[test]
    fn test_plugin_type_serialization() {
        let entry = PluginStoreEntry {
            name: "test".to_string(),
            version: "1.0.0".to_string(),
            description: "test".to_string(),
            author: "test".to_string(),
            download_url: "https://test.com".to_string(),
            rating: 5.0,
            downloads: 100,
            compatible_version: "1.0.0".to_string(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"name\":\"test\""));
    }

    #[test]
    fn test_register_menu_item() {
        PLUGIN_REGISTRY.unregister_plugin("test-plugin");
        let result = injection::register_menu_item(
            "test-plugin",
            "tools/custom",
            "自定义工具",
            "custom_tool_cb",
        );
        assert!(result.is_ok());
    }

    #[test]
    fn test_register_menu_item_duplicate() {
        let _ = injection::register_menu_item(
            "test-plugin",
            "tools/custom",
            "自定义工具",
            "custom_tool_cb",
        );
        let result = injection::register_menu_item(
            "test-plugin-2",
            "tools/custom",
            "自定义工具",
            "custom_tool_cb_2",
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_register_page() {
        let result = injection::register_page("test-plugin", "stats_page", "数据统计", "📊");
        assert!(result.is_ok());
    }

    #[test]
    fn test_register_page_duplicate() {
        let _ = injection::register_page("test-plugin", "test_page", "测试", "📄");
        let result = injection::register_page("test-plugin-2", "test_page", "测试2", "📄");
        assert!(result.is_err());
    }

    #[test]
    fn test_register_service() {
        let result = injection::register_service("test-plugin", "数据导出服务", "export_service");
        assert!(result.is_ok());
    }

    #[test]
    fn test_register_service_duplicate() {
        let _ = injection::register_service("test-plugin", "Svc", "svc_id");
        let result = injection::register_service("test-plugin-2", "Svc2", "svc_id");
        assert!(result.is_err());
    }

    #[test]
    fn test_get_registered_menus() {
        PLUGIN_REGISTRY.unregister_plugin("cleanup-menus-test");
        let _ = injection::register_menu_item("cleanup-menus-test", "file/test", "Test", "cb1");
        let menus = injection::get_registered_menus();
        assert!(!menus.is_empty());
        assert!(menus.iter().any(|m| m.plugin_name == "cleanup-menus-test"));
    }

    #[test]
    fn test_get_registered_pages() {
        PLUGIN_REGISTRY.unregister_plugin("test-plugin");
        let _ = injection::register_page("test-plugin", "p1", "Page 1", "📄");
        let pages = injection::get_registered_pages();
        assert!(!pages.is_empty());
        assert!(pages.iter().any(|p| p.page_id == "p1"));
    }

    #[test]
    fn test_get_registered_services() {
        PLUGIN_REGISTRY.unregister_plugin("test-plugin");
        let _ = injection::register_service("test-plugin", "Service 1", "s1");
        let services = injection::get_registered_services();
        assert!(!services.is_empty());
        assert!(services.iter().any(|s| s.service_id == "s1"));
    }

    #[test]
    fn test_unregister_plugin() {
        PLUGIN_REGISTRY.unregister_plugin("unregister-test");
        let _ = injection::register_menu_item("unregister-test", "test", "Test", "cb");
        let _ = injection::register_page("unregister-test", "ptest", "Test", "📄");
        let _ = injection::register_service("unregister-test", "Test", "stest");

        PLUGIN_REGISTRY.unregister_plugin("unregister-test");

        assert!(injection::get_registered_menus()
            .iter()
            .all(|m| m.plugin_name != "unregister-test"));
        assert!(injection::get_registered_pages()
            .iter()
            .all(|p| p.plugin_name != "unregister-test"));
        assert!(injection::get_registered_services()
            .iter()
            .all(|s| s.plugin_name != "unregister-test"));
    }
}
