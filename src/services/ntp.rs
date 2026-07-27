//! NTP 时间同步服务
//!
//! 使用手动解析 NTP 协议实现时间同步，支持多服务器配置和偏移量计算。

use log::{error, info, warn};
use std::sync::Mutex;
use std::time::Duration;

/// NTP 时间同步状态
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum NtpSyncStatus {
    Idle,
    Syncing,
    Synced,
    Failed(String),
}

/// NTP 时间同步结果
#[derive(Debug, Clone)]
pub struct NtpSyncResult {
    pub offset_ms: i64,
    pub round_trip_delay_ms: i64,
    pub server: String,
    pub status: NtpSyncStatus,
}

/// NTP 客户端配置
#[derive(Debug, Clone)]
pub struct NtpConfig {
    pub servers: Vec<String>,
    pub timeout: Duration,
    pub port: u16,
}

impl Default for NtpConfig {
    fn default() -> Self {
        NtpConfig {
            servers: vec!["ntp.aliyun.com".to_string(), "pool.ntp.org".to_string()],
            timeout: Duration::from_secs(5),
            port: 123,
        }
    }
}

/// NTP 时间同步服务
pub struct NtpService {
    config: Mutex<NtpConfig>,
    last_result: Mutex<Option<NtpSyncResult>>,
}

impl NtpService {
    pub fn new() -> Self {
        NtpService {
            config: Mutex::new(NtpConfig::default()),
            last_result: Mutex::new(None),
        }
    }

    pub fn with_config(config: NtpConfig) -> Self {
        NtpService {
            config: Mutex::new(config),
            last_result: Mutex::new(None),
        }
    }

    #[allow(dead_code)]
    pub fn set_servers(&self, servers: Vec<String>) {
        if let Ok(mut config) = self.config.lock() {
            config.servers = servers;
        }
    }

    /// 执行一次 NTP 时间同步
    pub fn sync(&self) -> NtpSyncResult {
        let config = match self.config.lock() {
            Ok(c) => c.clone(),
            Err(e) => {
                error!("Failed to lock NTP config: {}", e);
                return NtpSyncResult {
                    offset_ms: 0,
                    round_trip_delay_ms: 0,
                    server: String::new(),
                    status: NtpSyncStatus::Failed("配置锁定失败".to_string()),
                };
            }
        };

        for server in &config.servers {
            info!("Attempting NTP sync with server: {}", server);

            match self.sync_with_server(server, config.port, config.timeout) {
                Ok(result) => {
                    info!(
                        "NTP sync successful: server={}, offset={}ms",
                        server, result.offset_ms
                    );
                    if let Ok(mut last) = self.last_result.lock() {
                        *last = Some(result.clone());
                    }
                    return result;
                }
                Err(e) => {
                    warn!("NTP sync failed for server {}: {}", server, e);
                }
            }
        }

        let result = NtpSyncResult {
            offset_ms: 0,
            round_trip_delay_ms: 0,
            server: String::new(),
            status: NtpSyncStatus::Failed("所有 NTP 服务器均同步失败".to_string()),
        };

        if let Ok(mut last) = self.last_result.lock() {
            *last = Some(result.clone());
        }
        result
    }

    fn sync_with_server(
        &self,
        server: &str,
        port: u16,
        timeout: Duration,
    ) -> Result<NtpSyncResult, String> {
        use std::net::ToSocketAddrs;

        let addr_str = format!("{}:{}", server, port);
        let addrs: Vec<std::net::SocketAddr> = addr_str
            .to_socket_addrs()
            .map_err(|e| format!("DNS 解析失败: {}", e))?
            .collect();

        let addr = addrs.first().ok_or("无可用地址")?;

        let socket = std::net::UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("无法绑定 UDP socket: {}", e))?;

        socket
            .set_read_timeout(Some(timeout))
            .map_err(|e| format!("设置超时失败: {}", e))?;
        socket
            .set_write_timeout(Some(timeout))
            .map_err(|e| format!("设置超时失败: {}", e))?;
        socket
            .connect(addr)
            .map_err(|e| format!("连接失败: {}", e))?;

        // 构建 NTP 请求（SNTP v4，客户端模式）
        let mut request = [0u8; 48];
        request[0] = 0x23; // LI=0, VN=4, Mode=3 (client)

        // 记录 T1：客户端发送时间
        let t1 = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| format!("系统时间错误: {}", e))?;

        socket
            .send(&request)
            .map_err(|e| format!("发送请求失败: {}", e))?;

        let mut response = [0u8; 48];
        let _len = socket
            .recv(&mut response)
            .map_err(|e| format!("接收响应失败: {}", e))?;

        // 记录 T4：客户端接收时间
        let t4 = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| format!("系统时间错误: {}", e))?;

        // 手动解析 NTP 响应
        let ntp_result = parse_ntp_response(&response, t1, t4)
            .map_err(|e| format!("解析 NTP 响应失败: {}", e))?;

        Ok(NtpSyncResult {
            offset_ms: ntp_result.offset_ms,
            round_trip_delay_ms: ntp_result.round_trip_delay_ms,
            server: server.to_string(),
            status: NtpSyncStatus::Synced,
        })
    }

    #[allow(dead_code)]
    pub fn last_result(&self) -> Option<NtpSyncResult> {
        self.last_result.lock().ok()?.clone()
    }

    #[allow(dead_code)]
    pub fn offset_ms(&self) -> Option<i64> {
        self.last_result()
            .filter(|r| r.status == NtpSyncStatus::Synced)
            .map(|r| r.offset_ms)
    }
}

/// 手动解析 NTP 响应
struct NtpResponse {
    offset_ms: i64,
    round_trip_delay_ms: i64,
}

fn parse_ntp_response(
    data: &[u8; 48],
    t1: std::time::Duration,
    t4: std::time::Duration,
) -> Result<NtpResponse, String> {
    // 检查 LI/VN/Mode 字节
    let mode = data[0] & 0x07;
    if mode != 4 {
        return Err(format!("无效的 NTP 模式: {}", mode));
    }

    // 提取 NTP 时间戳（NTP 时间戳 = 秒 + 小数部分，从 1900-01-01 开始）
    // T2: 服务器接收时间戳 - 字节 32-39
    let t2_ntp = read_ntp_timestamp(data, 32);
    // T3: 服务器传输时间戳 - 字节 40-47
    let t3_ntp = read_ntp_timestamp(data, 40);

    // 将 NTP 时间戳和客户端 Duration 统一转换为毫秒
    let t1_ms = t1.as_millis() as i64;
    let t2_ms = ntp_to_epoch_ms(t2_ntp);
    let t3_ms = ntp_to_epoch_ms(t3_ntp);
    let t4_ms = t4.as_millis() as i64;

    // 计算偏移量: Offset = ((T2 - T1) + (T3 - T4)) / 2
    let offset_ms = ((t2_ms - t1_ms) + (t3_ms - t4_ms)) / 2;

    // 计算往返延迟: RTT = (T4 - T1) - (T3 - T2)
    let rtt_ms = (t4_ms - t1_ms) - (t3_ms - t2_ms);

    Ok(NtpResponse {
        offset_ms,
        round_trip_delay_ms: rtt_ms,
    })
}

/// 将 NTP 时间戳（1900 纪元起的毫秒）转换为 Unix 纪元毫秒。
fn ntp_to_epoch_ms(ntp_ms: u64) -> i64 {
    // NTP 纪元 (1900-01-01) 与 Unix 纪元 (1970-01-01) 相差 2208988800 秒
    const NTP_UNIX_DELTA_MS: i64 = 2_208_988_800_000;
    (ntp_ms as i64) - NTP_UNIX_DELTA_MS
}

fn read_ntp_timestamp(data: &[u8; 48], offset: usize) -> u64 {
    let seconds = u32::from_be_bytes([
        data[offset],
        data[offset + 1],
        data[offset + 2],
        data[offset + 3],
    ]) as u64;

    let fraction = u32::from_be_bytes([
        data[offset + 4],
        data[offset + 5],
        data[offset + 6],
        data[offset + 7],
    ]) as u64;

    // 转换为毫秒
    seconds * 1000 + (fraction as f64 / 4_294_967_296.0 * 1000.0) as u64
}

impl Default for NtpService {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ntp_service_creation() {
        let service = NtpService::new();
        assert!(service.last_result().is_none());
    }

    #[test]
    fn test_ntp_service_with_config() {
        let config = NtpConfig {
            servers: vec!["test.example.com".to_string()],
            timeout: Duration::from_secs(1),
            port: 123,
        };
        let service = NtpService::with_config(config);
        assert!(service.last_result().is_none());
    }

    #[test]
    fn test_set_servers() {
        let service = NtpService::new();
        service.set_servers(vec!["pool.ntp.org".to_string()]);
        let config = service.config.lock().unwrap();
        assert_eq!(config.servers.len(), 1);
        assert_eq!(config.servers[0], "pool.ntp.org");
    }

    #[test]
    fn test_ntp_sync_result_status() {
        let result = NtpSyncResult {
            offset_ms: 100,
            round_trip_delay_ms: 50,
            server: "pool.ntp.org".to_string(),
            status: NtpSyncStatus::Synced,
        };
        assert_eq!(result.status, NtpSyncStatus::Synced);
        assert_eq!(result.offset_ms, 100);
    }

    #[test]
    fn test_default_config() {
        let config = NtpConfig::default();
        assert!(!config.servers.is_empty());
        assert_eq!(config.port, 123);
    }

    #[test]
    fn test_parse_ntp_response() {
        let mut data = [0u8; 48];
        data[0] = 0x24; // LI=0, VN=4, Mode=4 (server)
        let t1 = std::time::Duration::from_secs(0);
        let t4 = std::time::Duration::from_secs(0);
        let result = parse_ntp_response(&data, t1, t4);
        assert!(result.is_ok());
    }
}
