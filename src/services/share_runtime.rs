//! Shared configuration-sharing runtime.
//!
//! Keeps the active validated configuration and the queue of incoming shares
//! independent from QML objects, so HTTP worker threads and the UI can safely
//! coordinate through one application-owned state.

use crate::core::parser::{has_exam_time_overlap, parse_exam_config, validate_exam_config};
use crate::core::utils::{aeterna_config_dir, atomic_write};
use crate::ui::settings_window::Settings;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

pub const SHARE_PROTOCOL_VERSION: u32 = 1;
const MAX_PENDING_SHARES: usize = 32;
const MAX_SEEN_SHARE_IDS: usize = 256;
const SHARE_REPLAY_WINDOW: Duration = Duration::from_secs(15 * 60);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareSender {
    pub device_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareEnvelope {
    pub protocol_version: u32,
    pub share_id: String,
    pub sender: ShareSender,
    pub config: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct IncomingShareSummary {
    pub share_id: String,
    pub sender_name: String,
    pub sender_id: String,
    pub exam_name: String,
    pub exam_count: usize,
}

#[derive(Debug, Clone)]
pub enum IncomingShareResult {
    Pending(IncomingShareSummary),
    AutoAccepted(IncomingShareSummary),
    Duplicate,
}

#[derive(Default)]
struct ShareState {
    settings: Option<Settings>,
    active_config_json: Option<String>,
    active_digest: Option<String>,
    pending: HashMap<String, (ShareEnvelope, Instant)>,
    seen_share_ids: HashMap<String, Instant>,
    last_status: String,
}

pub struct ShareRuntime {
    state: Mutex<ShareState>,
    #[cfg(feature = "cast")]
    cast_service: Arc<crate::services::cast::CastService>,
}

static RUNTIME: OnceLock<Arc<ShareRuntime>> = OnceLock::new();

pub fn install(runtime: Arc<ShareRuntime>) -> Result<(), Arc<ShareRuntime>> {
    RUNTIME.set(runtime)
}

pub fn global() -> Option<Arc<ShareRuntime>> {
    RUNTIME.get().cloned()
}

impl ShareRuntime {
    #[cfg(feature = "cast")]
    pub fn new(settings: Settings, cast_service: Arc<crate::services::cast::CastService>) -> Self {
        Self {
            state: Mutex::new(ShareState {
                settings: Some(settings),
                ..ShareState::default()
            }),
            cast_service,
        }
    }

    #[cfg(not(feature = "cast"))]
    pub fn new(settings: Settings) -> Self {
        Self {
            state: Mutex::new(ShareState {
                settings: Some(settings),
                ..ShareState::default()
            }),
        }
    }

    pub fn update_settings(&self, settings: Settings) {
        #[cfg(feature = "cast")]
        {
            let api = crate::services::http_api::ApiConfig::from_settings(&settings.http_api);
            let lan_reachable =
                !matches!(api.bind_address.as_str(), "127.0.0.1" | "::1" | "localhost")
                    && !api.token.trim().is_empty();
            let _ = self
                .cast_service
                .update_config(crate::services::cast::CastConfig {
                    mdns_enabled: settings.cast.mdns_enabled,
                    advertise_on_lan: settings.cast.advertise_on_lan,
                    device_name: settings.cast.device_name.clone(),
                    port: api.port,
                    allow_remote_control: settings.cast.allow_remote_control,
                    auto_accept: settings.cast.auto_accept,
                    share_enabled: settings.cast.allow_remote_control,
                    api_reachable_on_lan: lan_reachable,
                });
        }
        if let Ok(mut state) = self.state.lock() {
            state.settings = Some(settings);
        }
        self.share_active_config();
    }

    pub fn accepts_remote_shares(&self) -> bool {
        self.state
            .lock()
            .ok()
            .and_then(|state| {
                state
                    .settings
                    .as_ref()
                    .map(|settings| settings.cast.allow_remote_control)
            })
            .unwrap_or(false)
    }

    pub fn auto_accepts_remote_shares(&self) -> bool {
        self.state
            .lock()
            .ok()
            .and_then(|state| {
                state
                    .settings
                    .as_ref()
                    .map(|settings| settings.cast.auto_accept)
            })
            .unwrap_or(false)
    }

    pub fn active_config_json(&self) -> Option<String> {
        self.state.lock().ok()?.active_config_json.clone()
    }

    pub fn last_status(&self) -> String {
        self.state
            .lock()
            .map(|state| state.last_status.clone())
            .unwrap_or_else(|_| "分享服务状态不可用".to_string())
    }

    pub fn pending_summary_json(&self) -> String {
        let summaries: Vec<IncomingShareSummary> = self
            .state
            .lock()
            .map(|state| {
                state
                    .pending
                    .values()
                    .filter_map(|(envelope, _)| summary_for_envelope(envelope))
                    .collect()
            })
            .unwrap_or_default();
        serde_json::to_string(&summaries).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn set_local_config(&self, json: &str, auto_share: bool) -> Result<(), String> {
        self.store_valid_config(json)?;
        if auto_share {
            self.share_active_config();
        }
        Ok(())
    }

    pub fn receive(&self, envelope: ShareEnvelope) -> Result<IncomingShareResult, String> {
        if envelope.protocol_version != SHARE_PROTOCOL_VERSION {
            return Err("不支持的配置分享协议版本".to_string());
        }
        if envelope.share_id.trim().is_empty() || envelope.sender.device_id.trim().is_empty() {
            return Err("分享请求缺少标识信息".to_string());
        }
        let config_json = serde_json::to_string(&envelope.config)
            .map_err(|e| format!("无法读取分享配置: {e}"))?;
        validate_config_json(&config_json)?;
        let summary = summary_for_envelope(&envelope).ok_or_else(|| "分享配置无效".to_string())?;

        let auto_accept = {
            let mut state = self.state.lock().map_err(|e| e.to_string())?;
            if !state
                .settings
                .as_ref()
                .map(|settings| settings.cast.allow_remote_control)
                .unwrap_or(false)
            {
                return Err("此设备未允许接收远程配置".to_string());
            }
            prune_share_state(&mut state);
            let replay_key = format!("{}:{}", envelope.sender.device_id, envelope.share_id);
            if state.seen_share_ids.contains_key(&replay_key) {
                return Ok(IncomingShareResult::Duplicate);
            }
            if state.pending.len() >= MAX_PENDING_SHARES {
                return Err("待确认的远程配置过多，请先处理现有请求".to_string());
            }
            let auto_accept = state
                .settings
                .as_ref()
                .map(|settings| settings.cast.auto_accept)
                .unwrap_or(false);
            state.seen_share_ids.insert(replay_key, Instant::now());
            if !auto_accept {
                state.pending.insert(
                    envelope.share_id.clone(),
                    (envelope.clone(), Instant::now()),
                );
                state.last_status = format!("收到来自 {} 的配置，等待确认", summary.sender_name);
            }
            auto_accept
        };

        if auto_accept {
            self.store_valid_config(&config_json)?;
            if let Ok(mut state) = self.state.lock() {
                state.last_status = format!("已自动接受来自 {} 的配置", summary.sender_name);
            }
            Ok(IncomingShareResult::AutoAccepted(summary))
        } else {
            Ok(IncomingShareResult::Pending(summary))
        }
    }

    pub fn approve(&self, share_id: &str) -> Result<Option<String>, String> {
        let envelope = self
            .state
            .lock()
            .map_err(|e| e.to_string())?
            .pending
            .remove(share_id);
        let Some((envelope, _received_at)) = envelope else {
            return Ok(None);
        };
        let config_json = serde_json::to_string(&envelope.config)
            .map_err(|e| format!("无法读取待确认配置: {e}"))?;
        self.store_valid_config(&config_json)?;
        if let Ok(mut state) = self.state.lock() {
            state.last_status = format!("已接受来自 {} 的配置", envelope.sender.name);
        }
        Ok(Some(config_json))
    }

    pub fn reject(&self, share_id: &str) -> bool {
        let mut state = match self.state.lock() {
            Ok(state) => state,
            Err(_) => return false,
        };
        let removed = state.pending.remove(share_id).is_some();
        if removed {
            state.last_status = "已拒绝远程配置".to_string();
        }
        removed
    }

    pub fn restore_active_config(&self) -> Option<String> {
        let path = active_config_path();
        let json = std::fs::read_to_string(path).ok()?;
        self.store_valid_config(&json).ok()?;
        Some(json)
    }

    fn store_valid_config(&self, json: &str) -> Result<(), String> {
        validate_config_json(json)?;
        let canonical = serde_json::to_string(
            &serde_json::from_str::<serde_json::Value>(json).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        let digest = simple_digest(&canonical);
        let changed = {
            let mut state = self.state.lock().map_err(|e| e.to_string())?;
            let changed = state.active_digest.as_deref() != Some(digest.as_str());
            state.active_config_json = Some(canonical.clone());
            state.active_digest = Some(digest);
            changed
        };
        if changed {
            let path = active_config_path();
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            atomic_write(&path, canonical.as_bytes()).map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    pub fn share_active_config(&self) {
        #[cfg(feature = "cast")]
        {
            let (json, token, name, device_id, enabled) = match self.state.lock() {
                Ok(state) => {
                    let Some(settings) = state.settings.as_ref() else {
                        return;
                    };
                    (
                        state.active_config_json.clone(),
                        settings.http_api.token.trim().to_string(),
                        settings.cast.device_name.clone(),
                        settings.cast.device_id.clone(),
                        settings.cast.allow_remote_control,
                    )
                }
                Err(_) => return,
            };
            let Some(config_json) = json else { return };
            if !enabled || token.is_empty() {
                if let Ok(mut state) = self.state.lock() {
                    state.last_status = "自动分享未启动：需要启用远程控制并配置 Token".to_string();
                }
                return;
            }
            let value = match serde_json::from_str(&config_json) {
                Ok(value) => value,
                Err(_) => return,
            };
            let share_id = new_share_id();
            if share_id.is_empty() || device_id.is_empty() {
                return;
            }
            let envelope = ShareEnvelope {
                protocol_version: SHARE_PROTOCOL_VERSION,
                share_id,
                sender: ShareSender { device_id, name },
                config: value,
            };
            let body = match serde_json::to_string(&envelope) {
                Ok(body) => body,
                Err(_) => return,
            };
            let devices = self.cast_service.get_share_targets();
            if devices.is_empty() {
                if let Ok(mut state) = self.state.lock() {
                    state.last_status = "未发现可授权分享的设备".to_string();
                }
                return;
            }
            let service = self.cast_service.clone();
            std::thread::spawn(move || {
                for device in devices {
                    let _ = service.cast_to_device(&device, &body, &token);
                }
            });
        }
    }

    #[cfg(feature = "cast")]
    pub fn cast_service(&self) -> Arc<crate::services::cast::CastService> {
        self.cast_service.clone()
    }

    #[cfg(feature = "cast")]
    pub fn share_active_config_to(&self, device_id: &str) -> Result<(), String> {
        let (config_json, token, enabled) = self.share_payload()?;
        if !enabled || token.is_empty() {
            return Err("自动分享需要启用远程控制并配置 Token".to_string());
        }
        let device = self
            .cast_service
            .get_share_targets()
            .into_iter()
            .find(|device| device.id == device_id)
            .ok_or_else(|| "目标设备不可用或未授权分享".to_string())?;
        let body = self.share_envelope_json(&config_json)?;
        self.cast_service.cast_to_device(&device, &body, &token)?;
        if let Ok(mut state) = self.state.lock() {
            state.last_status = format!("已向 {} 发送配置", device.name);
        }
        Ok(())
    }

    #[cfg(not(feature = "cast"))]
    pub fn share_active_config_to(&self, _device_id: &str) -> Result<(), String> {
        Err("当前构建未包含投屏功能".to_string())
    }

    #[cfg(feature = "cast")]
    fn share_payload(&self) -> Result<(String, String, bool), String> {
        let state = self.state.lock().map_err(|e| e.to_string())?;
        let settings = state
            .settings
            .as_ref()
            .ok_or_else(|| "分享设置不可用".to_string())?;
        let config_json = state
            .active_config_json
            .clone()
            .ok_or_else(|| "没有可分享的配置".to_string())?;
        Ok((
            config_json,
            settings.http_api.token.trim().to_string(),
            settings.cast.mdns_enabled && settings.cast.allow_remote_control,
        ))
    }

    #[cfg(feature = "cast")]
    fn share_envelope_json(&self, config_json: &str) -> Result<String, String> {
        let (name, device_id) = self
            .state
            .lock()
            .map_err(|e| e.to_string())?
            .settings
            .as_ref()
            .map(|settings| {
                (
                    settings.cast.device_name.clone(),
                    settings.cast.device_id.clone(),
                )
            })
            .ok_or_else(|| "分享设置不可用".to_string())?;
        let value = serde_json::from_str(config_json).map_err(|e| e.to_string())?;
        if device_id.is_empty() {
            return Err("本机设备标识不可用".to_string());
        }
        let share_id = new_share_id();
        if share_id.is_empty() {
            return Err("无法生成安全的分享标识".to_string());
        }
        let envelope = ShareEnvelope {
            protocol_version: SHARE_PROTOCOL_VERSION,
            share_id,
            sender: ShareSender { device_id, name },
            config: value,
        };
        serde_json::to_string(&envelope).map_err(|e| e.to_string())
    }
}

fn prune_share_state(state: &mut ShareState) {
    let cutoff = Instant::now() - SHARE_REPLAY_WINDOW;
    state
        .pending
        .retain(|_, (_, received_at)| *received_at > cutoff);
    state.seen_share_ids.retain(|_, seen_at| *seen_at > cutoff);
    if state.seen_share_ids.len() > MAX_SEEN_SHARE_IDS {
        let mut oldest: Vec<(String, Instant)> = state
            .seen_share_ids
            .iter()
            .map(|(id, seen_at)| (id.clone(), *seen_at))
            .collect();
        oldest.sort_by_key(|(_, seen_at)| *seen_at);
        for (id, _) in oldest
            .into_iter()
            .take(state.seen_share_ids.len() - MAX_SEEN_SHARE_IDS)
        {
            state.seen_share_ids.remove(&id);
        }
    }
}

fn validate_config_json(json: &str) -> Result<(), String> {
    let config = parse_exam_config(json).ok_or_else(|| "考试配置 JSON 无效".to_string())?;
    if !validate_exam_config(&config) {
        return Err("考试配置未通过校验".to_string());
    }
    if has_exam_time_overlap(&config) {
        return Err("考试时间存在重叠".to_string());
    }
    Ok(())
}

fn summary_for_envelope(envelope: &ShareEnvelope) -> Option<IncomingShareSummary> {
    let json = serde_json::to_string(&envelope.config).ok()?;
    let config = parse_exam_config(&json)?;
    Some(IncomingShareSummary {
        share_id: envelope.share_id.clone(),
        sender_name: envelope.sender.name.clone(),
        sender_id: envelope.sender.device_id.clone(),
        exam_name: config.exam_name,
        exam_count: config.exam_infos.len(),
    })
}

fn new_share_id() -> String {
    let id = crate::ui::settings_window::generate_secure_id();
    if id.is_empty() {
        // Refuse to send rather than silently weakening replay protection.
        ::log::error!("Unable to create a cryptographically secure share ID");
    }
    id
}

fn simple_digest(value: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in value.bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn active_config_path() -> std::path::PathBuf {
    aeterna_config_dir().join("active_config.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_config() -> &'static str {
        r#"{"examName":"测试","message":"","examInfos":[{"name":"数学","start":"2026-08-02 09:00:00","end":"2026-08-02 10:00:00","alertTime":5}]}"#
    }

    fn overlapping_config() -> &'static str {
        r#"{"examName":"测试","message":"","examInfos":[{"name":"数学","start":"2026-08-02 09:00:00","end":"2026-08-02 10:00:00","alertTime":5},{"name":"英语","start":"2026-08-02 09:30:00","end":"2026-08-02 10:30:00","alertTime":5}]}"#
    }

    fn runtime(settings: Settings) -> ShareRuntime {
        #[cfg(feature = "cast")]
        {
            ShareRuntime::new(
                settings,
                Arc::new(crate::services::cast::CastService::new()),
            )
        }
        #[cfg(not(feature = "cast"))]
        {
            ShareRuntime::new(settings)
        }
    }

    fn envelope(share_id: &str, sender_id: &str, config: &str) -> ShareEnvelope {
        ShareEnvelope {
            protocol_version: SHARE_PROTOCOL_VERSION,
            share_id: share_id.to_string(),
            sender: ShareSender {
                device_id: sender_id.to_string(),
                name: "Sender".to_string(),
            },
            config: serde_json::from_str(config).unwrap(),
        }
    }

    #[test]
    fn generated_share_ids_are_nonempty_and_unique() {
        let first = new_share_id();
        let second = new_share_id();
        assert_eq!(first.len(), 32);
        assert_eq!(second.len(), 32);
        assert_ne!(first, second);
    }

    #[test]
    fn replay_detection_is_scoped_to_sender_identity() {
        let mut settings = Settings::default();
        settings.cast.allow_remote_control = true;
        let runtime = runtime(settings);

        assert!(matches!(
            runtime.receive(envelope("share", "sender-a", valid_config())),
            Ok(IncomingShareResult::Pending(_))
        ));
        assert!(matches!(
            runtime.receive(envelope("share", "sender-a", valid_config())),
            Ok(IncomingShareResult::Duplicate)
        ));
        assert!(matches!(
            runtime.receive(envelope("share", "sender-b", valid_config())),
            Ok(IncomingShareResult::Pending(_))
        ));
    }

    #[test]
    fn rejects_invalid_share_protocol() {
        let result = runtime(Settings::default()).receive(ShareEnvelope {
            protocol_version: 99,
            share_id: "one".to_string(),
            sender: ShareSender {
                device_id: "sender".to_string(),
                name: "Sender".to_string(),
            },
            config: serde_json::from_str(valid_config()).unwrap(),
        });
        assert!(result.is_err());
    }

    #[test]
    fn rejects_overlapping_remote_configurations_before_queueing() {
        let mut settings = Settings::default();
        settings.cast.allow_remote_control = true;
        let runtime = runtime(settings);
        let result = runtime.receive(ShareEnvelope {
            protocol_version: SHARE_PROTOCOL_VERSION,
            share_id: "overlap".to_string(),
            sender: ShareSender {
                device_id: "sender".to_string(),
                name: "Sender".to_string(),
            },
            config: serde_json::from_str(overlapping_config()).unwrap(),
        });

        assert_eq!(result.unwrap_err(), "考试时间存在重叠");
        assert_eq!(runtime.pending_summary_json(), "[]");
        assert!(runtime.active_config_json().is_none());
    }
}
