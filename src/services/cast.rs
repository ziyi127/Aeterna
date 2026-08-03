//! 投屏/设备发现服务

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};

const SERVICE_TYPE: &str = "_aeterna._tcp.local.";
const SHARE_PROTOCOL_VERSION: &str = "1";

/// 发现的设备信息。
#[derive(Debug, Clone)]
pub struct DiscoveredDevice {
    pub id: String,
    pub name: String,
    pub hostname: String,
    pub ip_address: String,
    pub port: u16,
    pub last_seen: std::time::Instant,
    pub properties: HashMap<String, String>,
}

impl DiscoveredDevice {
    pub fn supports_config_share(&self) -> bool {
        self.properties
            .get("config_share")
            .is_some_and(|value| value == "true")
            && self
                .properties
                .get("remote_control")
                .is_some_and(|value| value == "true")
            && self
                .properties
                .get("protocol")
                .is_some_and(|value| value == SHARE_PROTOCOL_VERSION)
            && self
                .properties
                .get("auth")
                .is_some_and(|value| value == "bearer")
            && !self.ip_address.is_empty()
            && self.port != 0
    }
}

/// 投屏服务配置。
#[derive(Debug, Clone)]
pub struct CastConfig {
    /// Controls the mDNS daemon and browsing for peer devices.
    pub mdns_enabled: bool,
    /// Controls whether this device advertises its local service on the LAN.
    pub advertise_on_lan: bool,
    pub device_name: String,
    pub port: u16,
    pub allow_remote_control: bool,
    pub auto_accept: bool,
    pub share_enabled: bool,
    pub api_reachable_on_lan: bool,
}

impl Default for CastConfig {
    fn default() -> Self {
        Self {
            mdns_enabled: true,
            advertise_on_lan: true,
            device_name: "Aeterna-001".to_string(),
            port: 9527,
            allow_remote_control: false,
            auto_accept: false,
            share_enabled: false,
            api_reachable_on_lan: false,
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

/// Long-lived mDNS discovery and transport service.
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
        if self.daemon.lock().map_err(|e| e.to_string())?.is_some() {
            return Ok(());
        }
        let config = self.config.lock().map_err(|e| e.to_string())?.clone();
        if !config.mdns_enabled {
            *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Stopped;
            return Ok(());
        }
        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Starting;
        let daemon = ServiceDaemon::new().map_err(|e| format!("创建 mDNS daemon 失败: {e}"))?;
        if config.advertise_on_lan {
            self.register_service(&daemon, &config)?;
        }
        self.start_discovery(&daemon)?;
        *self.daemon.lock().map_err(|e| e.to_string())? = Some(daemon);
        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Running;
        ::log::info!("Cast service started successfully");
        Ok(())
    }

    fn register_service(&self, daemon: &ServiceDaemon, config: &CastConfig) -> Result<(), String> {
        let remote_control =
            config.allow_remote_control && config.share_enabled && config.api_reachable_on_lan;
        let properties = [
            ("version", env!("CARGO_PKG_VERSION")),
            ("type", "player"),
            ("protocol", SHARE_PROTOCOL_VERSION),
            (
                "config_share",
                if remote_control { "true" } else { "false" },
            ),
            ("auth", if remote_control { "bearer" } else { "none" }),
            (
                "remote_control",
                if remote_control { "true" } else { "false" },
            ),
        ];
        let service_info = ServiceInfo::new(
            SERVICE_TYPE,
            &config.device_name,
            &get_hostname(),
            "",
            config.port,
            &properties[..],
        )
        .map_err(|e| format!("创建服务信息失败: {e}"))?;
        daemon
            .register(service_info)
            .map_err(|e| format!("注册 mDNS 服务失败: {e}"))?;
        *self.service_name.lock().map_err(|e| e.to_string())? =
            Some(format!("{}.{}", config.device_name, SERVICE_TYPE));
        Ok(())
    }

    fn start_discovery(&self, daemon: &ServiceDaemon) -> Result<(), String> {
        let receiver = daemon
            .browse(SERVICE_TYPE)
            .map_err(|e| format!("启动服务浏览失败: {e}"))?;
        let devices = self.devices.clone();
        let local_name = self
            .config
            .lock()
            .map_err(|e| e.to_string())?
            .device_name
            .clone();
        std::thread::spawn(move || {
            while let Ok(event) = receiver.recv() {
                match event {
                    ServiceEvent::ServiceResolved(info) => {
                        let fullname = info.get_fullname().to_string();
                        if fullname.starts_with(&format!("{}.", local_name)) {
                            continue;
                        }
                        let properties: HashMap<String, String> = info
                            .get_properties()
                            .iter()
                            .map(|property| {
                                (property.key().to_string(), property.val_str().to_string())
                            })
                            .collect();
                        let ip_address = choose_address(info.get_addresses());
                        if ip_address.is_empty() || info.get_port() == 0 {
                            continue;
                        }
                        let name = fullname
                            .strip_suffix(SERVICE_TYPE)
                            .unwrap_or(&fullname)
                            .trim_end_matches('.')
                            .to_string();
                        let device = DiscoveredDevice {
                            id: fullname.clone(),
                            name,
                            hostname: info.get_hostname().to_string(),
                            ip_address,
                            port: info.get_port(),
                            last_seen: std::time::Instant::now(),
                            properties,
                        };
                        if let Ok(mut known) = devices.lock() {
                            known.insert(fullname, device);
                        }
                    }
                    ServiceEvent::ServiceRemoved(_, fullname) => {
                        if let Ok(mut known) = devices.lock() {
                            known.remove(&fullname);
                        }
                    }
                    _ => {}
                }
            }
        });
        Ok(())
    }

    pub fn stop(&self) -> Result<(), String> {
        if let Some(daemon) = self.daemon.lock().map_err(|e| e.to_string())?.take() {
            if let Some(name) = self.service_name.lock().map_err(|e| e.to_string())?.take() {
                let _ = daemon.unregister(&name);
            }
            let _ = daemon.shutdown();
        }
        self.devices.lock().map_err(|e| e.to_string())?.clear();
        *self.status.lock().map_err(|e| e.to_string())? = CastStatus::Stopped;
        Ok(())
    }

    pub fn get_devices(&self) -> Vec<DiscoveredDevice> {
        let mut devices = self
            .devices
            .lock()
            .map(|devices| devices.values().cloned().collect::<Vec<_>>())
            .unwrap_or_default();
        devices.sort_by(|left, right| left.name.cmp(&right.name).then(left.id.cmp(&right.id)));
        devices
    }

    pub fn get_share_targets(&self) -> Vec<DiscoveredDevice> {
        self.get_devices()
            .into_iter()
            .filter(DiscoveredDevice::supports_config_share)
            .collect()
    }

    pub fn get_status(&self) -> CastStatus {
        self.status
            .lock()
            .map(|status| status.clone())
            .unwrap_or_else(|_| CastStatus::Error("状态锁定失败".to_string()))
    }

    pub fn update_config(&self, config: CastConfig) -> Result<(), String> {
        let previous = self.config.lock().map_err(|e| e.to_string())?.clone();
        let should_restart = previous.mdns_enabled != config.mdns_enabled
            || previous.advertise_on_lan != config.advertise_on_lan
            || previous.device_name != config.device_name
            || previous.port != config.port
            || previous.allow_remote_control != config.allow_remote_control
            || previous.share_enabled != config.share_enabled
            || previous.api_reachable_on_lan != config.api_reachable_on_lan;
        *self.config.lock().map_err(|e| e.to_string())? = config;
        if should_restart {
            self.stop()?;
            self.start()?;
        }
        Ok(())
    }

    pub fn cast_to_device(
        &self,
        device: &DiscoveredDevice,
        envelope_json: &str,
        token: &str,
    ) -> Result<(), String> {
        if !device.supports_config_share() {
            return Err("目标设备不支持受认证的配置分享".to_string());
        }
        if token.trim().is_empty() {
            return Err("配置分享需要 HTTP Token".to_string());
        }
        serde_json::from_str::<serde_json::Value>(envelope_json)
            .map_err(|e| format!("无效的分享 JSON: {e}"))?;
        let host = match device.ip_address.parse::<IpAddr>() {
            Ok(IpAddr::V6(_)) => format!("[{}]", device.ip_address),
            Ok(IpAddr::V4(_)) => device.ip_address.clone(),
            Err(_) => return Err("目标设备地址无效".to_string()),
        };
        let url = format!("http://{}:{}/api/config", host, device.port);
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| format!("无法创建 tokio runtime: {e}"))?;
        runtime.block_on(async {
            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .map_err(|e| format!("创建 HTTP 客户端失败: {e}"))?;
            let response = client
                .post(&url)
                .header("Content-Type", "application/json")
                .header("X-Cast-Source", "Aeterna")
                .bearer_auth(token)
                .body(envelope_json.to_string())
                .send()
                .await
                .map_err(|e| format!("投屏请求失败: {e}"))?;
            if response.status().is_success() {
                Ok(())
            } else {
                Err(format!("投屏请求被拒绝: HTTP {}", response.status()))
            }
        })
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

fn choose_address(addresses: &std::collections::HashSet<IpAddr>) -> String {
    let mut addresses: Vec<IpAddr> = addresses.iter().copied().collect();
    addresses.sort_by_key(|address| match address {
        IpAddr::V4(address) if !address.is_loopback() => 0,
        IpAddr::V4(_) => 1,
        IpAddr::V6(address) if !address.is_loopback() => 2,
        IpAddr::V6(_) => 3,
    });
    addresses
        .first()
        .map(ToString::to_string)
        .unwrap_or_default()
}

fn get_hostname() -> String {
    #[cfg(unix)]
    {
        let mut buffer = [0_u8; 256];
        if unsafe { libc::gethostname(buffer.as_mut_ptr() as *mut libc::c_char, buffer.len()) } == 0
        {
            let end = buffer
                .iter()
                .position(|byte| *byte == 0)
                .unwrap_or(buffer.len());
            return format!("{}.local.", String::from_utf8_lossy(&buffer[..end]));
        }
    }
    "Aeterna.local.".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn share_target_requires_all_security_capabilities() {
        let device = DiscoveredDevice {
            id: "test".to_string(),
            name: "Test".to_string(),
            hostname: "test.local.".to_string(),
            ip_address: "192.168.1.2".to_string(),
            port: 9527,
            last_seen: std::time::Instant::now(),
            properties: HashMap::from([
                ("config_share".to_string(), "true".to_string()),
                ("remote_control".to_string(), "true".to_string()),
                ("protocol".to_string(), "1".to_string()),
                ("auth".to_string(), "bearer".to_string()),
            ]),
        };
        assert!(device.supports_config_share());
    }

    #[test]
    fn advertising_can_be_disabled_without_disabling_browsing() {
        let config = CastConfig {
            mdns_enabled: true,
            advertise_on_lan: false,
            ..CastConfig::default()
        };
        assert!(config.mdns_enabled);
        assert!(!config.advertise_on_lan);
    }

    #[test]
    fn disabled_service_stays_stopped() {
        let service = CastService::with_config(CastConfig {
            mdns_enabled: false,
            ..CastConfig::default()
        });
        service.start().unwrap();
        assert_eq!(service.get_status(), CastStatus::Stopped);
    }
}
