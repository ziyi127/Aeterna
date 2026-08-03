//! Lightweight HTTP API server — zero external dependencies.
//!
//! A minimal `std::net` + `std::thread` server (no actix, no tokio).
//! Provides: health, time, config, status, WebSocket endpoints.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{BufReader, Read, Write};
use std::net::{TcpListener, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

/// Simple thread-safe rate limiter.
pub struct RateLimiter {
    requests: Mutex<HashMap<String, Vec<Instant>>>,
    max_requests: usize,
    window: Duration,
}

impl RateLimiter {
    pub fn new(max_requests: usize, window: Duration) -> Self {
        RateLimiter {
            requests: Mutex::new(HashMap::new()),
            max_requests,
            window,
        }
    }

    pub fn default_limiter() -> Self {
        Self::new(100, Duration::from_secs(60))
    }

    pub fn check(&self, ip: &str) -> bool {
        let mut requests = self.requests.lock().unwrap();
        let now = Instant::now();
        let cutoff = now - self.window;
        let entry = requests.entry(ip.to_string()).or_default();
        entry.retain(|&t| t > cutoff);
        if entry.len() >= self.max_requests {
            return false;
        }
        entry.push(now);
        true
    }

    #[allow(dead_code)]
    pub fn reset(&self, ip: &str) {
        if let Ok(mut requests) = self.requests.lock() {
            requests.remove(ip);
        }
    }
}

/// API service configuration.
#[derive(Debug, Clone)]
pub struct ApiConfig {
    pub enabled: bool,
    pub port: u16,
    pub bind_address: String,
    pub token_auth: bool,
    pub token: String,
    pub allow_cors: bool,
}

impl Default for ApiConfig {
    fn default() -> Self {
        ApiConfig {
            enabled: true,
            port: 9527,
            bind_address: "127.0.0.1".to_string(),
            token_auth: false,
            token: String::new(),
            allow_cors: false,
        }
    }
}

impl ApiConfig {
    pub fn from_settings(settings: &crate::ui::settings_window::HttpApiSettings) -> Self {
        let port = u16::try_from(settings.port).unwrap_or(9527);
        let bind_address = settings.bind_address.trim();
        let bind_address = if bind_address.is_empty() {
            "127.0.0.1"
        } else {
            bind_address
        };
        let is_loopback = matches!(bind_address, "127.0.0.1" | "::1" | "localhost");
        let token = settings.token.trim().to_string();

        ApiConfig {
            enabled: settings.enabled,
            port,
            bind_address: bind_address.to_string(),
            token_auth: settings.token_auth || (!is_loopback && !token.is_empty()),
            token,
            allow_cors: settings.allow_cors,
        }
    }
}

const MAX_CONCURRENT_CONNECTIONS: usize = 32;

static SERVICE: OnceLock<Arc<HttpApiService>> = OnceLock::new();

pub fn install(service: Arc<HttpApiService>) -> Result<(), Arc<HttpApiService>> {
    SERVICE.set(service)
}

pub fn global() -> Option<Arc<HttpApiService>> {
    SERVICE.get().cloned()
}

struct ConnectionLimiter {
    active: AtomicUsize,
    maximum: usize,
}

impl ConnectionLimiter {
    fn new(maximum: usize) -> Self {
        Self {
            active: AtomicUsize::new(0),
            maximum,
        }
    }

    fn try_acquire(self: &Arc<Self>) -> Option<ConnectionPermit> {
        let mut active = self.active.load(Ordering::Acquire);
        loop {
            if active >= self.maximum {
                return None;
            }
            match self.active.compare_exchange_weak(
                active,
                active + 1,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Some(ConnectionPermit {
                        limiter: self.clone(),
                    })
                }
                Err(current) => active = current,
            }
        }
    }
}

struct ConnectionPermit {
    limiter: Arc<ConnectionLimiter>,
}

impl Drop for ConnectionPermit {
    fn drop(&mut self) {
        self.limiter.active.fetch_sub(1, Ordering::Release);
    }
}

struct ApiState {
    service: Arc<HttpApiService>,
    version: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiStatus {
    pub running: bool,
    pub port: u16,
    pub uptime_seconds: u64,
    pub version: String,
    pub message: String,
}

struct ServerLifecycle {
    listener: Option<TcpListener>,
    port: u16,
    message: String,
}

/// HTTP API service. Its supervisor runs for the application's lifetime,
/// including while the API is disabled, so settings can enable it live.
pub struct HttpApiService {
    config: Mutex<ApiConfig>,
    lifecycle: Mutex<ServerLifecycle>,
    start_time: Instant,
    rate_limiter: Arc<RateLimiter>,
    share_runtime: Arc<crate::services::share_runtime::ShareRuntime>,
}

impl HttpApiService {
    pub fn new() -> Self {
        Self::with_config(ApiConfig::default())
    }

    pub fn with_config(config: ApiConfig) -> Self {
        let runtime =
            crate::services::share_runtime::global().unwrap_or_else(default_share_runtime);
        Self::with_config_and_runtime(config, runtime)
    }

    pub fn with_config_and_runtime(
        config: ApiConfig,
        share_runtime: Arc<crate::services::share_runtime::ShareRuntime>,
    ) -> Self {
        Self {
            config: Mutex::new(config),
            lifecycle: Mutex::new(ServerLifecycle {
                listener: None,
                port: 0,
                message: "HTTP API supervisor has not started".to_string(),
            }),
            start_time: Instant::now(),
            rate_limiter: Arc::new(RateLimiter::default_limiter()),
            share_runtime,
        }
    }

    /// Applies configuration atomically. For an enabled server, the new address
    /// is bound before the old listener is released; a bind failure leaves both
    /// the current listener and the active configuration untouched.
    pub fn reconfigure(&self, config: ApiConfig) -> std::io::Result<()> {
        let bind_addr = config
            .enabled
            .then(|| resolve_bind_address(&config))
            .transpose()?;
        {
            let lifecycle = self.lifecycle.lock().unwrap();
            if let (Some(listener), Some(bind_addr)) = (&lifecycle.listener, bind_addr) {
                if listener.local_addr()? == bind_addr {
                    *self.config.lock().unwrap() = config;
                    return Ok(());
                }
            }
        }

        let candidate = match bind_addr {
            Some(bind_addr) => {
                let listener = TcpListener::bind(bind_addr)?;
                listener.set_nonblocking(true)?;
                Some(listener)
            }
            None => None,
        };
        let candidate_port = candidate
            .as_ref()
            .map(TcpListener::local_addr)
            .transpose()?
            .map(|address| address.port())
            .unwrap_or(0);

        let mut lifecycle = self.lifecycle.lock().unwrap();
        *self.config.lock().unwrap() = config;
        lifecycle.listener = candidate;
        lifecycle.port = candidate_port;
        lifecycle.message = if candidate_port == 0 {
            "HTTP API is disabled".to_string()
        } else {
            format!("HTTP API listening on port {candidate_port}")
        };
        Ok(())
    }

    /// Runs the lifetime supervisor. It deliberately remains active when
    /// disabled so `reconfigure` can later install a listener without restart.
    pub fn start(self: Arc<Self>) -> std::io::Result<()> {
        if let Err(error) = self.reconfigure(self.config.lock().unwrap().clone()) {
            let mut lifecycle = self.lifecycle.lock().unwrap();
            lifecycle.message = format!("HTTP API unavailable: {error}");
            log::warn!("{}", lifecycle.message);
        }
        let connection_limiter = Arc::new(ConnectionLimiter::new(MAX_CONCURRENT_CONNECTIONS));
        loop {
            let listener = self
                .lifecycle
                .lock()
                .unwrap()
                .listener
                .as_ref()
                .and_then(|listener| listener.try_clone().ok());
            let Some(listener) = listener else {
                std::thread::sleep(Duration::from_millis(50));
                continue;
            };
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let Some(permit) = connection_limiter.try_acquire() else {
                        let _ = write_response(
                            &mut stream,
                            503,
                            "{\"error\":\"Service Unavailable\"}",
                            "application/json",
                            None,
                        );
                        continue;
                    };
                    let state = ApiState {
                        service: self.clone(),
                        version: env!("CARGO_PKG_VERSION"),
                    };
                    std::thread::spawn(move || {
                        let _permit = permit;
                        handle_connection(stream, &state);
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(error) => log::warn!("HTTP accept error: {error}"),
            }
        }
    }

    pub fn status(&self) -> ApiStatus {
        let lifecycle = self.lifecycle.lock().unwrap();
        ApiStatus {
            running: lifecycle.listener.is_some(),
            port: lifecycle.port,
            uptime_seconds: self.start_time.elapsed().as_secs(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            message: lifecycle.message.clone(),
        }
    }

    #[allow(dead_code)]
    pub fn uptime_seconds(&self) -> u64 {
        self.start_time.elapsed().as_secs()
    }
}

impl Default for HttpApiService {
    fn default() -> Self {
        Self::new()
    }
}

fn default_share_runtime() -> Arc<crate::services::share_runtime::ShareRuntime> {
    #[cfg(feature = "cast")]
    {
        Arc::new(crate::services::share_runtime::ShareRuntime::new(
            crate::ui::settings_window::Settings::default(),
            Arc::new(crate::services::cast::CastService::new()),
        ))
    }
    #[cfg(not(feature = "cast"))]
    {
        Arc::new(crate::services::share_runtime::ShareRuntime::new(
            crate::ui::settings_window::Settings::default(),
        ))
    }
}

fn resolve_bind_address(cfg: &ApiConfig) -> std::io::Result<std::net::SocketAddr> {
    if cfg.token_auth && cfg.token.trim().is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "HTTP token authentication requires a non-empty token",
        ));
    }

    let address = if cfg.bind_address.contains(':') && !cfg.bind_address.starts_with('[') {
        format!("[{}]:{}", cfg.bind_address, cfg.port)
    } else {
        format!("{}:{}", cfg.bind_address, cfg.port)
    };
    let bind_addr = address.to_socket_addrs()?.next().ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::InvalidInput, "invalid bind address")
    })?;
    if !bind_addr.ip().is_loopback() && cfg.token.trim().is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "non-loopback HTTP binding requires a token",
        ));
    }
    Ok(bind_addr)
}

const MAX_REQUEST_LINE_BYTES: usize = 8 * 1024;
const MAX_HEADER_LINE_BYTES: usize = 8 * 1024;
const MAX_HEADER_BYTES: usize = 32 * 1024;
const MAX_HEADERS: usize = 64;
const MAX_BODY_BYTES: usize = 1024 * 1024;

/// Parse a single bounded HTTP/1 request. One request is processed per connection.
struct HttpRequest {
    method: String,
    path: String,
    headers: HashMap<String, String>,
    body: Vec<u8>,
    peer_ip: String,
}

#[derive(Debug, Clone, Copy)]
enum RequestParseError {
    BadRequest,
    PayloadTooLarge,
    HeaderTooLarge,
    NotImplemented,
}

impl RequestParseError {
    fn status(self) -> u16 {
        match self {
            Self::BadRequest => 400,
            Self::PayloadTooLarge => 413,
            Self::HeaderTooLarge => 431,
            Self::NotImplemented => 501,
        }
    }
}

fn read_crlf_line<R: Read>(reader: &mut R, maximum: usize) -> Result<Vec<u8>, RequestParseError> {
    let mut line = Vec::with_capacity(maximum.min(256));
    let mut byte = [0_u8; 1];
    loop {
        reader
            .read_exact(&mut byte)
            .map_err(|_| RequestParseError::BadRequest)?;
        if byte[0] == b'\n' {
            if line.pop() != Some(b'\r') {
                return Err(RequestParseError::BadRequest);
            }
            return Ok(line);
        }
        if byte[0] == b'\r' {
            line.push(byte[0]);
            continue;
        }
        if line.len() >= maximum {
            return Err(RequestParseError::HeaderTooLarge);
        }
        line.push(byte[0]);
    }
}

fn is_token(value: &[u8]) -> bool {
    !value.is_empty()
        && value.iter().all(|byte| {
            matches!(
                byte,
                b'!'
                    | b'#'..=b'\''
                    | b'*'..=b'+'
                    | b'-'..=b'.'
                    | b'0'..=b'9'
                    | b'A'..=b'Z'
                    | b'^'
                    | b'_'
                    | b'`'
                    | b'a'..=b'z'
                    | b'|'
                    | b'~'
            )
        })
}

fn parse_request<R: Read>(
    reader: &mut R,
    peer_ip: String,
) -> Result<HttpRequest, RequestParseError> {
    let request_line = read_crlf_line(reader, MAX_REQUEST_LINE_BYTES)?;
    let request_line =
        std::str::from_utf8(&request_line).map_err(|_| RequestParseError::BadRequest)?;
    let fields: Vec<&str> = request_line.split(' ').collect();
    if fields.len() != 3
        || !is_token(fields[0].as_bytes())
        || fields[1].is_empty()
        || !matches!(fields[2], "HTTP/1.0" | "HTTP/1.1")
    {
        return Err(RequestParseError::BadRequest);
    }
    let method = fields[0].to_uppercase();
    let path = fields[1].split('?').next().unwrap_or(fields[1]).to_string();

    let mut headers = HashMap::new();
    let mut header_bytes = 0;
    loop {
        let line = read_crlf_line(reader, MAX_HEADER_LINE_BYTES)?;
        if line.is_empty() {
            break;
        }
        header_bytes += line.len();
        if header_bytes > MAX_HEADER_BYTES || headers.len() >= MAX_HEADERS {
            return Err(RequestParseError::HeaderTooLarge);
        }
        let colon = line
            .iter()
            .position(|byte| *byte == b':')
            .ok_or(RequestParseError::BadRequest)?;
        let (name, value) = line.split_at(colon);
        let value = &value[1..];
        if !is_token(name)
            || name.last() == Some(&b' ')
            || value.iter().any(|byte| *byte < 0x20 && *byte != b'\t')
        {
            return Err(RequestParseError::BadRequest);
        }
        let name = std::str::from_utf8(name)
            .map_err(|_| RequestParseError::BadRequest)?
            .to_ascii_lowercase();
        let value = std::str::from_utf8(value)
            .map_err(|_| RequestParseError::BadRequest)?
            .trim()
            .to_string();
        if headers.insert(name, value).is_some() {
            return Err(RequestParseError::BadRequest);
        }
    }

    if headers.contains_key("transfer-encoding") {
        return Err(RequestParseError::NotImplemented);
    }
    let body_len = match headers.get("content-length") {
        Some(value) if !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()) => {
            value
                .parse::<usize>()
                .map_err(|_| RequestParseError::BadRequest)?
        }
        Some(_) => return Err(RequestParseError::BadRequest),
        None => 0,
    };
    if body_len > MAX_BODY_BYTES {
        return Err(RequestParseError::PayloadTooLarge);
    }
    let mut body = vec![0; body_len];
    reader
        .read_exact(&mut body)
        .map_err(|_| RequestParseError::BadRequest)?;

    Ok(HttpRequest {
        method,
        path,
        headers,
        body,
        peer_ip,
    })
}

fn handle_connection(mut stream: TcpStream, state: &ApiState) {
    stream.set_read_timeout(Some(Duration::from_secs(10))).ok();
    stream.set_write_timeout(Some(Duration::from_secs(10))).ok();
    let peer_ip = match stream.peer_addr() {
        Ok(address) => address.ip().to_string(),
        Err(e) => {
            log::warn!("Unable to determine HTTP peer address: {e}");
            return;
        }
    };
    let req = {
        let mut reader = BufReader::new(&mut stream);
        parse_request(&mut reader, peer_ip)
    };
    let req = match req {
        Ok(request) => request,
        Err(error) => {
            let _ = write_response(
                &mut stream,
                error.status(),
                "Bad Request",
                "text/plain",
                None,
            );
            return;
        }
    };
    let config = state.service.config.lock().unwrap().clone();
    let cors = config.allow_cors.then_some(CorsPolicy);

    if req.method == "OPTIONS" && req.path.starts_with("/api/") {
        if cors.is_some() {
            let _ = write_response(&mut stream, 204, "", "text/plain", cors);
        } else {
            let _ = write_response(
                &mut stream,
                404,
                r#"{"error":"Not Found"}"#,
                "application/json",
                None,
            );
        }
        return;
    }
    if !state.service.rate_limiter.check(&req.peer_ip) {
        let _ = write_response(
            &mut stream,
            429,
            r#"{"error":"Too Many Requests","retry_after_seconds":60}"#,
            "application/json",
            cors,
        );
        return;
    }
    let protected = req.path.starts_with("/api/config");
    if protected && config.token_auth {
        let valid = req
            .headers
            .get("authorization")
            .and_then(|value| value.strip_prefix("Bearer "))
            == Some(config.token.as_str());
        if !valid {
            let _ = write_response(
                &mut stream,
                401,
                r#"{"error":"Invalid or missing token"}"#,
                "application/json",
                cors,
            );
            return;
        }
    }
    match (req.method.as_str(), req.path.as_str()) {
        ("GET", "/health") | ("GET", "/api/health") => handle_health(&mut stream, state, cors),
        ("GET", "/api/time") => handle_time(&mut stream, cors),
        ("GET", "/api/time/ntp") => handle_ntp_status(&mut stream, cors),
        ("GET", "/api/status") => handle_status(&mut stream, state, cors),
        ("GET", "/api/config") => handle_get_config(&mut stream, state, cors),
        ("POST", "/api/config") => handle_post_config(&mut stream, &req, state, cors),
        ("GET", "/api/swagger.json") => handle_swagger(&mut stream, state, cors),
        ("GET", "/api/ws") => handle_ws_unavailable(&mut stream, cors),
        _ => {
            let _ = write_response(
                &mut stream,
                404,
                r#"{"error":"Not Found"}"#,
                "application/json",
                cors,
            );
        }
    }
}

#[derive(Clone, Copy)]
struct CorsPolicy;

impl CorsPolicy {
    fn headers(self) -> &'static str {
        "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Max-Age: 600\r\n"
    }
}

fn write_response(
    stream: &mut TcpStream,
    status: u16,
    body: &str,
    content_type: &str,
    cors: Option<CorsPolicy>,
) -> std::io::Result<()> {
    let status_text = match status {
        101 => "Switching Protocols",
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        409 => "Conflict",
        413 => "Payload Too Large",
        429 => "Too Many Requests",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        503 => "Service Unavailable",
        _ => "Unknown",
    };
    let cors_headers = cors.map(CorsPolicy::headers).unwrap_or("");
    let response = format!("HTTP/1.1 {status} {status_text}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n{cors_headers}\r\n{body}", body.len());
    stream.write_all(response.as_bytes())
}

fn json_response(
    stream: &mut TcpStream,
    status: u16,
    data: &serde_json::Value,
    cors: Option<CorsPolicy>,
) {
    let body = serde_json::to_string(data).unwrap_or_else(|_| "{}".to_string());
    let _ = write_response(stream, status, &body, "application/json", cors);
}

fn handle_health(stream: &mut TcpStream, state: &ApiState, cors: Option<CorsPolicy>) {
    let now = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let data = serde_json::json!({
        "status": "ok",
        "version": state.version,
        "timestamp": now,
    });
    json_response(stream, 200, &data, cors);
}

fn handle_time(stream: &mut TcpStream, cors: Option<CorsPolicy>) {
    let now = chrono::Local::now();
    let data = serde_json::json!({
        "timestamp_ms": now.timestamp_millis(),
        "datetime": now.format("%Y-%m-%d %H:%M:%S").to_string(),
        "timezone": now.format("%:z").to_string(),
    });
    json_response(stream, 200, &data, cors);
}

fn handle_ntp_status(stream: &mut TcpStream, cors: Option<CorsPolicy>) {
    json_response(
        stream,
        200,
        &serde_json::json!({"status": "ok", "message": "NTP status endpoint"}),
        cors,
    );
}

fn handle_status(stream: &mut TcpStream, state: &ApiState, cors: Option<CorsPolicy>) {
    let status = state.service.status();
    json_response(
        stream,
        200,
        &serde_json::json!({
            "running": status.running,
            "port": status.port,
            "uptime_seconds": status.uptime_seconds,
            "version": state.version,
            "message": status.message,
        }),
        cors,
    );
}

fn handle_get_config(stream: &mut TcpStream, state: &ApiState, cors: Option<CorsPolicy>) {
    let (config, status) = (
        state.service.share_runtime.active_config_json(),
        state.service.share_runtime.last_status(),
    );
    json_response(
        stream,
        200,
        &serde_json::json!({
            "protocol_version": crate::services::share_runtime::SHARE_PROTOCOL_VERSION,
            "config": config,
            "status": status,
        }),
        cors,
    );
}

fn handle_post_config(
    stream: &mut TcpStream,
    req: &HttpRequest,
    state: &ApiState,
    cors: Option<CorsPolicy>,
) {
    if !req.headers.get("content-type").is_some_and(|value| {
        value
            .split(';')
            .next()
            .is_some_and(|kind| kind.trim().eq_ignore_ascii_case("application/json"))
    }) {
        json_response(
            stream,
            400,
            &serde_json::json!({"error":"Content-Type must be application/json"}),
            cors,
        );
        return;
    }
    let runtime = &state.service.share_runtime;
    let envelope =
        match serde_json::from_slice::<crate::services::share_runtime::ShareEnvelope>(&req.body) {
            Ok(envelope) => envelope,
            Err(_) => {
                json_response(
                    stream,
                    400,
                    &serde_json::json!({"error":"Invalid share envelope"}),
                    cors,
                );
                return;
            }
        };
    match runtime.receive(envelope) {
        Ok(crate::services::share_runtime::IncomingShareResult::Pending(summary)) => {
            json_response(
                stream,
                202,
                &serde_json::json!({
                    "status":"pending_confirmation",
                    "share_id": summary.share_id,
                }),
                cors,
            );
        }
        Ok(crate::services::share_runtime::IncomingShareResult::AutoAccepted(summary)) => {
            json_response(
                stream,
                202,
                &serde_json::json!({
                    "status":"accepted",
                    "share_id": summary.share_id,
                }),
                cors,
            );
        }
        Ok(crate::services::share_runtime::IncomingShareResult::Duplicate) => {
            json_response(
                stream,
                409,
                &serde_json::json!({"error":"Duplicate share request"}),
                cors,
            );
        }
        Err(message) => {
            json_response(stream, 400, &serde_json::json!({"error":message}), cors);
        }
    }
}

fn handle_swagger(stream: &mut TcpStream, state: &ApiState, cors: Option<CorsPolicy>) {
    let swagger = serde_json::json!({
        "openapi": "3.0.0",
        "info": {
            "title": "Aeterna API",
            "version": state.version,
            "description": "Aeterna - HTTP API"
        },
        "servers": [{"url": "http://localhost:9527", "description": "本地服务器"}],
        "paths": {
            "/health": {"get": {"summary": "健康检查", "responses": {"200": {"description": "服务正常"}}}},
            "/api/time": {"get": {"summary": "获取当前时间", "responses": {"200": {"description": "当前时间信息"}}}},
            "/api/config": {
                "get": {"summary": "获取考试配置", "responses": {"200": {"description": "考试配置"}}},
                "post": {"summary": "更新考试配置", "responses": {"200": {"description": "配置已更新"}}}
            },
            "/api/status": {"get": {"summary": "获取服务状态", "responses": {"200": {"description": "服务状态信息"}}}},
            "/api/ws": {"get": {"summary": "WebSocket（尚未实现）", "responses": {"501": {"description": "尚未实现"}}}}
        }
    });
    json_response(stream, 200, &swagger, cors);
}

fn handle_ws_unavailable(stream: &mut TcpStream, cors: Option<CorsPolicy>) {
    json_response(
        stream,
        501,
        &serde_json::json!({"error": "WebSocket is not implemented"}),
        cors,
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconfigure_updates_live_auth_and_cors_without_rebinding() {
        let runtime = default_share_runtime();
        let service = HttpApiService::with_config_and_runtime(
            ApiConfig {
                enabled: true,
                port: 0,
                ..ApiConfig::default()
            },
            runtime,
        );
        service
            .reconfigure(ApiConfig {
                enabled: true,
                port: 0,
                ..ApiConfig::default()
            })
            .unwrap();
        let port = service.status().port;
        service
            .reconfigure(ApiConfig {
                enabled: true,
                port,
                token_auth: true,
                token: "updated-token".to_string(),
                allow_cors: true,
                ..ApiConfig::default()
            })
            .unwrap();
        assert_eq!(service.status().port, port);
        let config = service.config.lock().unwrap().clone();
        assert!(config.token_auth && config.allow_cors);
        assert_eq!(config.token, "updated-token");
    }

    #[test]
    fn failed_reconfigure_preserves_existing_listener_and_configuration() {
        let runtime = default_share_runtime();
        let service = HttpApiService::with_config_and_runtime(
            ApiConfig {
                enabled: true,
                port: 0,
                ..ApiConfig::default()
            },
            runtime,
        );
        service
            .reconfigure(ApiConfig {
                enabled: true,
                port: 0,
                ..ApiConfig::default()
            })
            .unwrap();
        let original = service.status();
        assert!(service
            .reconfigure(ApiConfig {
                enabled: true,
                bind_address: "0.0.0.0".to_string(),
                ..ApiConfig::default()
            })
            .is_err());
        assert_eq!(service.status().port, original.port);
        assert_eq!(service.config.lock().unwrap().bind_address, "127.0.0.1");
    }

    #[test]
    fn cors_policy_is_fixed_and_complete() {
        let headers = CorsPolicy.headers();
        assert!(headers.contains("Access-Control-Allow-Origin: *"));
        assert!(headers.contains("GET, POST, OPTIONS"));
        assert!(headers.contains("Authorization, Content-Type"));
    }
    #[test]
    fn test_api_service_creation() {
        let service = HttpApiService::new();
        assert!(service.uptime_seconds() < 1);
    }

    #[test]
    fn test_parse_request_rejects_invalid_framing() {
        let mut request = std::io::Cursor::new(b"GET /\n\n".to_vec());
        assert!(matches!(
            parse_request(&mut request, "127.0.0.1".to_string()),
            Err(RequestParseError::BadRequest)
        ));
    }

    #[test]
    fn test_parse_request_rejects_oversized_body() {
        let request = format!(
            "POST /api/config HTTP/1.1\r\nContent-Length: {}\r\n\r\n",
            MAX_BODY_BYTES + 1
        );
        let mut request = std::io::Cursor::new(request.into_bytes());
        assert!(matches!(
            parse_request(&mut request, "127.0.0.1".to_string()),
            Err(RequestParseError::PayloadTooLarge)
        ));
    }

    #[test]
    fn test_parse_request_rejects_transfer_encoding() {
        let mut request = std::io::Cursor::new(
            b"POST /api/config HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".to_vec(),
        );
        assert!(matches!(
            parse_request(&mut request, "127.0.0.1".to_string()),
            Err(RequestParseError::NotImplemented)
        ));
    }

    #[test]
    fn test_parse_request_reads_exact_body() {
        let mut request = std::io::Cursor::new(
            b"POST /api/config HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".to_vec(),
        );
        let parsed = parse_request(&mut request, "127.0.0.1".to_string()).unwrap();
        assert_eq!(parsed.body, b"{}");
    }

    #[test]
    fn test_rate_limiter() {
        let limiter = RateLimiter::new(2, Duration::from_secs(60));
        assert!(limiter.check("127.0.0.1"));
        assert!(limiter.check("127.0.0.1"));
        assert!(!limiter.check("127.0.0.1"));
    }

    #[test]
    fn test_rate_limiter_multi_ip() {
        let limiter = RateLimiter::new(1, Duration::from_secs(60));
        assert!(limiter.check("a"));
        assert!(limiter.check("b"));
        assert!(!limiter.check("a"));
    }

    #[test]
    fn test_api_config_default() {
        let cfg = ApiConfig::default();
        assert!(cfg.enabled);
        assert_eq!(cfg.port, 9527);
        assert_eq!(cfg.bind_address, "127.0.0.1");
        assert!(!cfg.allow_cors);
    }

    #[test]
    fn test_resolve_bind_address_requires_token_for_lan() {
        let config = ApiConfig {
            bind_address: "0.0.0.0".to_string(),
            ..ApiConfig::default()
        };
        assert!(resolve_bind_address(&config).is_err());
    }

    #[test]
    fn test_resolve_bind_address_supports_ipv6_loopback() {
        let config = ApiConfig {
            bind_address: "::1".to_string(),
            ..ApiConfig::default()
        };
        assert!(resolve_bind_address(&config).unwrap().ip().is_loopback());
    }

    #[test]
    fn test_resolve_bind_address_rejects_empty_authenticated_token() {
        let config = ApiConfig {
            token_auth: true,
            ..ApiConfig::default()
        };
        assert!(resolve_bind_address(&config).is_err());
    }
}
