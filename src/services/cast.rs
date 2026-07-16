//! 投屏/设备发现服务

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// 发现的设备信息
#[derive(Debug, Clone)]
pub struct DiscoveredDevice {
    pub name: String,
    pub hostname: String,
    pub ip_address: String,
    pub port: u16,
    pub last_seen: std::time::Instant,
    pub properties: HashMap<String, String>,
}

/// 投屏服务配置
#[derive(Debug, Clone)]
pub struct CastConfig {
    pub enabled: bool,
    pub allow_discovery: bool,
    pub device_name: String,
    pub port: u16,
    pub allow_remote_control: bool,
    pub auto_accept: bool,
}

impl Default for CastConfig {
    fn default() -> Self {
        CastConfig {
            enabled: true,
            allow_discovery: true,
            device_name: "Aeterna-001".to_string(),
            port: 9527,
            allow_remote_control: false,
            auto_accept: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum CastStatus {
    Stopped,
    Starting,
    Running,
    Error(String),
}

/// 投屏服务
pub struct CastService {
    config: Mutex<CastConfig>,
    daemon: Mutex<Option<ServiceDaemon>>,
    devices: Arc<Mutex<HashMap<String, DiscoveredDevice>>>,
    status: Mutex<CastStatus>,
    service_name: Mutex<Option<String>>,
}

impl CastService {
    pub fn new() -> Self {
        Self::with_config(CastConfig::default())
    }

    pub fn with_config(config: CastConfig) -> Self {
        Self {
            config: Mutex::new(config),
            daemon: Mutex::new(None),
            devices: Arc::new(Mutex::new(HashMap::new())),
            status: Mutex::new(CastStatus::Stopped),
            service_name: Mutex::new(None),
        }
    }

    pub fn start(&self) -> Result<(), String> {
        let config = self.config.lock().map_err(|e| e.to_string())?.clone();

        if !config.enabled {
            *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Stopped;
            ::log::info!("Cast service is disabled");
            return Ok(());
        }

        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Starting;

        let daemon = ServiceDaemon::new().map_err(|e| format!("创建 mDNS daemon 失败: {}", e))?;

        if config.allow_discovery {
            self.register_service(&daemon, &config)?;
        }

        self.start_discovery(&daemon)?;

        *self.daemon.lock().map_err(|e| e.to_string())? = Some(daemon);
        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Running;

        ::log::info!("Cast service started successfully");
        Ok(())
    }

    fn register_service(&self, daemon: &ServiceDaemon, config: &CastConfig) -> Result<(), String> {
        let service_type = "_aeterna._tcp.local.";
        let instance_name = &config.device_name;
        let hostname = get_hostname();

        let properties: [(&str, &str); 3] = [
            ("version", env!("CARGO_PKG_VERSION")),
            ("type", "player"),
            (
                "remote_control",
                if config.allow_remote_control {
                    "true"
                } else {
                    "false"
                },
            ),
        ];

        let service_info = ServiceInfo::new(
            service_type,
            instance_name,
            &hostname,
            "",
            config.port,
            &properties[..],
        )
        .map_err(|e| format!("创建服务信息失败: {}", e))?;

        daemon
            .register(service_info)
            .map_err(|e| format!("注册 mDNS 服务失败: {}", e))?;

        let full_name = format!("{}.{}", instance_name, service_type);
        *self.service_name.lock().map_err(|e| e.to_string())? = Some(full_name);

        ::log::info!(
            "mDNS service registered: {} on port {}",
            config.device_name,
            config.port
        );
        Ok(())
    }

    fn start_discovery(&self, daemon: &ServiceDaemon) -> Result<(), String> {
        let service_type = "_aeterna._tcp.local.";

        let receiver = daemon
            .browse(service_type)
            .map_err(|e| format!("启动服务浏览失败: {}", e))?;

        // Use a separate thread for discovery
        let devices_arc = self.devices.clone();
        std::thread::spawn(move || loop {
            match receiver.recv() {
                Ok(event) => match event {
                    ServiceEvent::ServiceResolved(info) => {
                        let fullname = info.get_fullname().to_string();
                        let device = DiscoveredDevice {
                            name: info.get_hostname().to_string(),
                            hostname: info.get_hostname().to_string(),
                            ip_address: info
                                .get_addresses()
                                .iter()
                                .next()
                                .map(|a| a.to_string())
                                .unwrap_or_default(),
                            port: info.get_port(),
                            last_seen: std::time::Instant::now(),
                            properties: {
                                let mut m = HashMap::new();
                                let props = info.get_properties();
                                for prop in props.iter() {
                                    m.insert(prop.key().to_string(), prop.val_str().to_string());
                                }
                                m
                            },
                        };
                        ::log::info!("Discovered device: {} ({})", device.name, device.ip_address);
                        let mut devices = devices_arc.lock().unwrap();
                        devices.insert(fullname.clone(), device);
                    }
                    ServiceEvent::ServiceRemoved(_service_type, fullname) => {
                        ::log::info!("Device removed: {}", fullname);
                        let mut devices = devices_arc.lock().unwrap();
                        devices.remove(&fullname);
                    }
                    _ => {}
                },
                Err(e) => {
                    ::log::warn!("Service discovery error: {}", e);
                    break;
                }
            }

            std::thread::sleep(Duration::from_millis(100));
        });

        ::log::info!("Device discovery started");
        Ok(())
    }

    pub fn stop(&self) -> Result<(), String> {
        // Unregister service
        if let Ok(daemon_guard) = self.daemon.lock() {
            if let Some(daemon) = daemon_guard.as_ref() {
                if let Ok(name_guard) = self.service_name.lock() {
                    if let Some(name) = name_guard.as_ref() {
                        let _ = daemon.unregister(name);
                    }
                }
            }
        }

        *self.daemon.lock().map_err(|e| e.to_string())? = None;
        *self.devices.lock().map_err(|e| e.to_string())? = HashMap::new();
        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Stopped;

        ::log::info!("Cast service stopped");
        Ok(())
    }

    pub fn get_devices(&self) -> Vec<DiscoveredDevice> {
        self.devices
            .lock()
            .map(|d| d.values().cloned().collect())
            .unwrap_or_default()
    }

    pub fn get_status(&self) -> CastStatus {
        self.status
            .lock()
            .map(|s| s.clone())
            .unwrap_or(CastStatus::Error("状态锁定失败".to_string()))
    }

    pub fn update_config(&self, config: CastConfig) {
        if let Ok(mut c) = self.config.lock() {
            *c = config;
        }
    }

    pub fn cast_to_device(
        &self,
        device: &DiscoveredDevice,
        config_json: &str,
    ) -> Result<(), String> {
        ::log::info!("Casting to device: {} ({})", device.name, device.ip_address);

        let url = format!("http://{}:{}/api/config", device.ip_address, device.port);

        // 验证 JSON 配置
        if let Err(e) = serde_json::from_str::<serde_json::Value>(config_json) {
            return Err(format!("无效的 JSON 配置: {}", e));
        }

        // 使用当前线程所在 tokio runtime 发送 HTTP POST 请求
        let handle = tokio::runtime::Handle::try_current()
            .map_err(|e| format!("不在 tokio runtime 上下文中: {}", e))?;

        let result = handle.block_on(async {
            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .map_err(|e| format!("创建 HTTP 客户端失败: {}", e))?;

            let response = client
                .post(&url)
                .header("Content-Type", "application/json")
                .header("X-Cast-Source", "Aeterna")
                .body(config_json.to_string())
                .send()
                .await
                .map_err(|e| format!("投屏请求失败: {}", e))?;

            if response.status().is_success() {
                ::log::info!(
                    "Successfully cast config to {}: HTTP {}",
                    device.name,
                    response.status()
                );
                Ok(())
            } else {
                let status = response.status();
                let body = response
                    .text()
                    .await
                    .unwrap_or_else(|_| "无法读取响应".to_string());
                Err(format!("投屏请求被拒绝: HTTP {} - {}", status, body))
            }
        });

        if let Err(ref e) = result {
            ::log::error!("Cast to device {} failed: {}", device.name, e);
        }

        result
    }
}

impl Default for CastService {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for CastService {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

fn get_hostname() -> String {
    #[cfg(unix)]
    {
        let mut buf = [0u8; 256];
        let result = unsafe { libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) };
        if result == 0 {
            let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
            let hostname = String::from_utf8_lossy(&buf[..end]).to_string();
            return format!("{}.local.", hostname);
        }
    }
    "Aeterna.local.".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cast_service_creation() {
        let service = CastService::new();
        assert_eq!(service.get_status(), CastStatus::Stopped);
    }

    #[test]
    fn test_cast_service_with_config() {
        let config = CastConfig {
            enabled: false,
            allow_discovery: false,
            device_name: "TestDevice".to_string(),
            port: 8080,
            allow_remote_control: true,
            auto_accept: false,
        };
        let service = CastService::with_config(config);
        assert_eq!(service.get_status(), CastStatus::Stopped);
    }

    #[test]
    fn test_cast_config_default() {
        let config = CastConfig::default();
        assert!(config.enabled);
        assert!(config.allow_discovery);
        assert_eq!(config.device_name, "Aeterna-001");
        assert_eq!(config.port, 9527);
    }

    #[test]
    fn test_discovered_device_properties() {
        let device = DiscoveredDevice {
            name: "TestDevice".to_string(),
            hostname: "test.local".to_string(),
            ip_address: "192.168.1.100".to_string(),
            port: 9527,
            last_seen: std::time::Instant::now(),
            properties: {
                let mut m = HashMap::new();
                m.insert("version".to_string(), "1.3.0".to_string());
                m
            },
        };
        assert_eq!(device.name, "TestDevice");
        assert_eq!(device.ip_address, "192.168.1.100");
        assert_eq!(device.port, 9527);
    }
}
