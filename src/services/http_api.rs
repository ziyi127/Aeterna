//! HTTP API 服务
//!
//! 提供基于 actix-web 的 HTTP API 服务，支持：
//! - 健康检查端点
//! - 时间查询端点
//! - 配置管理端点
//! - Swagger/OpenAPI JSON 端点
//! - Token 认证中间件
//! - CORS 中间件
//! - 速率限制
//! - WebSocket 支持

use actix_cors::Cors;
use actix_web::{middleware, web, App, HttpRequest, HttpResponse, HttpServer};
use log::info;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// 速率限制器
///
/// 跟踪每个 IP 在时间窗口内的请求数量，超出限制时返回 429。
pub struct RateLimiter {
    /// IP -> 请求时间戳列表
    requests: Mutex<HashMap<String, Vec<Instant>>>,
    /// 每个 IP 每分钟允许的最大请求数
    max_requests: usize,
    /// 时间窗口长度
    window: Duration,
}

impl RateLimiter {
    /// 创建新的速率限制器
    ///
    /// # 参数
    /// - `max_requests`: 时间窗口内允许的最大请求数
    /// - `window`: 时间窗口长度
    pub fn new(max_requests: usize, window: Duration) -> Self {
        RateLimiter {
            requests: Mutex::new(HashMap::new()),
            max_requests,
            window,
        }
    }

    /// 创建默认限制器（100 请求/分钟/IP）
    pub fn default_limiter() -> Self {
        Self::new(100, Duration::from_secs(60))
    }

    /// 检查请求是否允许通过
    ///
    /// 返回 true 表示允许，false 表示超出限制。
    pub fn check(&self, ip: &str) -> bool {
        let mut requests = self.requests.lock().unwrap();
        let now = Instant::now();
        let cutoff = now - self.window;

        let entry = requests.entry(ip.to_string()).or_default();

        // 清理过期的时间戳
        entry.retain(|&t| t > cutoff);

        if entry.len() >= self.max_requests {
            return false;
        }

        entry.push(now);
        true
    }

    /// 获取指定 IP 的剩余请求数
    pub fn remaining(&self, ip: &str) -> usize {
        let mut requests = self.requests.lock().unwrap();
        let now = Instant::now();
        let cutoff = now - self.window;

        if let Some(entry) = requests.get_mut(ip) {
            entry.retain(|&t| t > cutoff);
            self.max_requests.saturating_sub(entry.len())
        } else {
            self.max_requests
        }
    }

    /// 重置指定 IP 的计数器
    #[allow(dead_code)]
    pub fn reset(&self, ip: &str) {
        if let Ok(mut requests) = self.requests.lock() {
            requests.remove(ip);
        }
    }

    /// 重置所有计数器
    #[allow(dead_code)]
    pub fn reset_all(&self) {
        if let Ok(mut requests) = self.requests.lock() {
            requests.clear();
        }
    }
}

/// API 服务配置
///
/// 控制 HTTP API 服务器的所有行为：
/// - `enabled`: 是否启用 HTTP API
/// - `port`: 监听端口
/// - `bind_address`: 绑定地址（`0.0.0.0` 监听所有网卡）
/// - `token_auth`: 是否启用 Bearer Token 认证
/// - `token`: 认证令牌
/// - `allow_cors`: 是否允许跨域请求
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
            bind_address: "0.0.0.0".to_string(),
            token_auth: false,
            token: String::new(),
            allow_cors: true,
        }
    }
}

/// API 服务状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiStatus {
    pub running: bool,
    pub port: u16,
    pub uptime_seconds: u64,
    pub version: String,
}

/// 健康检查响应
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub timestamp: String,
}

/// 时间查询响应
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeResponse {
    pub timestamp_ms: i64,
    pub datetime: String,
    pub timezone: String,
}

/// 配置管理请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigRequest {
    pub exam_name: String,
    pub message: String,
    pub exam_infos: Vec<ExamInfoRequest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExamInfoRequest {
    pub name: String,
    pub start: String,
    pub end: String,
    #[serde(rename = "alertTime")]
    pub alert_time: i32,
}

/// HTTP API 服务
pub struct HttpApiService {
    config: Mutex<ApiConfig>,
    start_time: std::time::Instant,
    rate_limiter: Arc<RateLimiter>,
}

impl HttpApiService {
    pub fn new() -> Self {
        HttpApiService {
            config: Mutex::new(ApiConfig::default()),
            start_time: std::time::Instant::now(),
            rate_limiter: Arc::new(RateLimiter::default_limiter()),
        }
    }

    #[allow(dead_code)]
    pub fn with_config(config: ApiConfig) -> Self {
        HttpApiService {
            config: Mutex::new(config),
            start_time: std::time::Instant::now(),
            rate_limiter: Arc::new(RateLimiter::default_limiter()),
        }
    }

    /// 创建自定义速率限制的 API 服务
    #[allow(dead_code)]
    pub fn with_rate_limit(max_requests: usize, window_seconds: u64) -> Self {
        HttpApiService {
            config: Mutex::new(ApiConfig::default()),
            start_time: std::time::Instant::now(),
            rate_limiter: Arc::new(RateLimiter::new(
                max_requests,
                Duration::from_secs(window_seconds),
            )),
        }
    }

    /// 更新配置
    #[allow(dead_code)]
    pub fn update_config(&self, config: ApiConfig) {
        if let Ok(mut c) = self.config.lock() {
            *c = config;
        }
    }

    /// 启动 HTTP API 服务器
    ///
    /// 返回一个 tokio task handle，服务器在后台运行。
    pub async fn start(&self) -> std::io::Result<()> {
        let config = self.config.lock().unwrap().clone();

        if !config.enabled {
            info!("HTTP API is disabled");
            return Ok(());
        }

        let bind_addr = format!("{}:{}", config.bind_address, config.port);
        let token = config.token.clone();
        let token_auth = config.token_auth;
        let allow_cors = config.allow_cors;
        let start_time = self.start_time;
        let rate_limiter = self.rate_limiter.clone();

        info!("Starting HTTP API server on {}", bind_addr);

        HttpServer::new(move || {
            let cors = if allow_cors {
                Cors::default()
                    .allow_any_origin()
                    .allow_any_method()
                    .allow_any_header()
            } else {
                Cors::default()
            };

            // 所有 worker 共享同一个限制器，保证配置的额度真实生效。
            let rate_limiter = web::Data::new(rate_limiter.clone());

            App::new()
                .wrap(cors)
                .wrap(middleware::Logger::default())
                .app_data(web::Data::new(ApiState {
                    token: token.clone(),
                    token_auth,
                    start_time,
                }))
                .app_data(rate_limiter)
                // 健康检查
                .route("/health", web::get().to(health_check))
                .route("/api/health", web::get().to(health_check))
                // 时间查询
                .route("/api/time", web::get().to(get_time))
                .route("/api/time/ntp", web::get().to(get_ntp_status))
                // 配置管理
                .route("/api/config", web::get().to(get_config))
                .route("/api/config", web::post().to(update_config))
                // 状态
                .route("/api/status", web::get().to(get_status))
                // Swagger JSON
                .route("/api/swagger.json", web::get().to(swagger_json))
                // WebSocket
                .route("/api/ws", web::get().to(ws_handler))
        })
        .bind(&bind_addr)?
        .run()
        .await
    }

    /// 获取运行时间（秒）
    #[allow(dead_code)]
    pub fn uptime_seconds(&self) -> u64 {
        self.start_time.elapsed().as_secs()
    }

    /// 获取当前状态
    #[allow(dead_code)]
    pub fn status(&self) -> ApiStatus {
        let config = self.config.lock().unwrap();
        ApiStatus {
            running: config.enabled,
            port: config.port,
            uptime_seconds: self.uptime_seconds(),
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

impl Default for HttpApiService {
    fn default() -> Self {
        Self::new()
    }
}

/// API 共享状态
struct ApiState {
    token: String,
    token_auth: bool,
    start_time: std::time::Instant,
}

/// 验证 Token
fn validate_token(req: &HttpRequest, state: &ApiState) -> bool {
    if !state.token_auth || state.token.is_empty() {
        return true;
    }

    let auth_header = req
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if let Some(token) = auth_header.strip_prefix("Bearer ") {
        return token == state.token;
    }

    false
}

/// 从请求中提取客户端 IP 地址
fn extract_client_ip(req: &HttpRequest) -> String {
    // 优先从 X-Forwarded-For 头获取
    if let Some(forwarded) = req.headers().get("X-Forwarded-For") {
        if let Ok(val) = forwarded.to_str() {
            if let Some(ip) = val.split(',').next() {
                return ip.trim().to_string();
            }
        }
    }
    // 其次从 X-Real-IP 头获取
    if let Some(real_ip) = req.headers().get("X-Real-IP") {
        if let Ok(val) = real_ip.to_str() {
            return val.trim().to_string();
        }
    }
    // 最后从连接信息获取
    req.peer_addr()
        .map(|addr| addr.ip().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

/// 检查速率限制，超出限制时返回 429 响应
fn check_rate_limit(req: &HttpRequest, limiter: &web::Data<RateLimiter>) -> Option<HttpResponse> {
    let ip = extract_client_ip(req);
    if !limiter.check(&ip) {
        let remaining = limiter.remaining(&ip);
        Some(
            HttpResponse::TooManyRequests()
                .insert_header(("Retry-After", "60"))
                .insert_header(("X-RateLimit-Limit", "100"))
                .insert_header(("X-RateLimit-Remaining", remaining.to_string()))
                .json(serde_json::json!({
                    "error": "Too Many Requests",
                    "message": "请求过于频繁，请稍后再试",
                    "retry_after_seconds": 60
                })),
        )
    } else {
        None
    }
}

/// 健康检查端点
async fn health_check(req: HttpRequest, limiter: web::Data<RateLimiter>) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    let response = HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
    };
    HttpResponse::Ok().json(response)
}

/// 获取时间
async fn get_time(req: HttpRequest, limiter: web::Data<RateLimiter>) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    let now = chrono::Local::now();
    let response = TimeResponse {
        timestamp_ms: now.timestamp_millis(),
        datetime: now.format("%Y-%m-%d %H:%M:%S").to_string(),
        timezone: now.format("%:z").to_string(),
    };
    HttpResponse::Ok().json(response)
}

/// 获取 NTP 状态
async fn get_ntp_status(req: HttpRequest, limiter: web::Data<RateLimiter>) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "message": "NTP status endpoint"
    }))
}

/// 获取配置
async fn get_config(
    req: HttpRequest,
    state: web::Data<ApiState>,
    limiter: web::Data<RateLimiter>,
) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    if !validate_token(&req, &state) {
        return HttpResponse::Unauthorized().json(serde_json::json!({
            "error": "Invalid or missing token"
        }));
    }

    HttpResponse::Ok().json(serde_json::json!({
        "message": "配置端点",
        "config": null
    }))
}

/// 更新配置
async fn update_config(
    req: HttpRequest,
    body: web::Json<ConfigRequest>,
    state: web::Data<ApiState>,
    limiter: web::Data<RateLimiter>,
) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    if !validate_token(&req, &state) {
        return HttpResponse::Unauthorized().json(serde_json::json!({
            "error": "Invalid or missing token"
        }));
    }

    info!("Received config update request: {}", body.exam_name);
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "message": "配置已更新"
    }))
}

/// 获取服务状态
async fn get_status(
    req: HttpRequest,
    state: web::Data<ApiState>,
    limiter: web::Data<RateLimiter>,
) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    let uptime = state.start_time.elapsed().as_secs();
    let status = ApiStatus {
        running: true,
        port: 9527,
        uptime_seconds: uptime,
        version: env!("CARGO_PKG_VERSION").to_string(),
    };
    HttpResponse::Ok().json(status)
}

/// Swagger/OpenAPI JSON
async fn swagger_json(req: HttpRequest, limiter: web::Data<RateLimiter>) -> HttpResponse {
    if let Some(response) = check_rate_limit(&req, &limiter) {
        return response;
    }
    let swagger = serde_json::json!({
        "openapi": "3.0.0",
        "info": {
            "title": "Aeterna API",
            "version": env!("CARGO_PKG_VERSION"),
            "description": "Aeterna - HTTP API 接口文档"
        },
        "servers": [
            {
                "url": "http://localhost:9527",
                "description": "本地服务器"
            }
        ],
        "paths": {
            "/health": {
                "get": {
                    "summary": "健康检查",
                    "responses": {
                        "200": {
                            "description": "服务正常"
                        }
                    }
                }
            },
            "/api/time": {
                "get": {
                    "summary": "获取当前时间",
                    "responses": {
                        "200": {
                            "description": "当前时间信息"
                        }
                    }
                }
            },
            "/api/config": {
                "get": {
                    "summary": "获取考试配置",
                    "security": [{"bearerAuth": []}],
                    "responses": {
                        "200": {
                            "description": "考试配置"
                        }
                    }
                },
                "post": {
                    "summary": "更新考试配置",
                    "security": [{"bearerAuth": []}],
                    "requestBody": {
                        "required": true,
                        "content": {
                            "application/json": {
                                "schema": {
                                    "$ref": "#/components/schemas/ConfigRequest"
                                }
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "配置已更新"
                        }
                    }
                }
            },
            "/api/status": {
                "get": {
                    "summary": "获取服务状态",
                    "responses": {
                        "200": {
                            "description": "服务状态信息"
                        }
                    }
                }
            },
            "/api/ws": {
                "get": {
                    "summary": "WebSocket 连接",
                    "responses": {
                        "101": {
                            "description": "WebSocket 升级"
                        }
                    }
                }
            }
        },
        "components": {
            "securitySchemes": {
                "bearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "JWT"
                }
            },
            "schemas": {
                "ConfigRequest": {
                    "type": "object",
                    "properties": {
                        "examName": {"type": "string"},
                        "message": {"type": "string"},
                        "examInfos": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "name": {"type": "string"},
                                    "start": {"type": "string"},
                                    "end": {"type": "string"},
                                    "alertTime": {"type": "integer"}
                                }
                            }
                        }
                    }
                }
            }
        }
    });

    HttpResponse::Ok().json(swagger)
}

/// WebSocket 处理
async fn ws_handler(
    req: HttpRequest,
    stream: web::Payload,
    limiter: web::Data<RateLimiter>,
) -> Result<HttpResponse, actix_web::Error> {
    if check_rate_limit(&req, &limiter).is_some() {
        return Ok(HttpResponse::TooManyRequests().json(serde_json::json!({
            "error": "Too Many Requests"
        })));
    }
    let (response, _session, _msg_stream) = actix_ws::handle(&req, stream)?;
    info!("WebSocket connection established");
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api_service_creation() {
        let service = HttpApiService::new();
        let status = service.status();
        assert!(status.running);
        assert_eq!(status.port, 9527);
    }

    #[test]
    fn test_api_service_with_config() {
        let config = ApiConfig {
            enabled: false,
            port: 8080,
            bind_address: "127.0.0.1".to_string(),
            token_auth: true,
            token: "test-token".to_string(),
            allow_cors: false,
        };
        let service = HttpApiService::with_config(config);
        let status = service.status();
        assert!(!status.running);
        assert_eq!(status.port, 8080);
    }

    #[test]
    fn test_health_response_serialization() {
        let response = HealthResponse {
            status: "ok".to_string(),
            version: "1.0.0".to_string(),
            timestamp: "2025-01-01 00:00:00".to_string(),
        };
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"status\":\"ok\""));
    }

    #[test]
    fn test_time_response_serialization() {
        let response = TimeResponse {
            timestamp_ms: 1700000000000,
            datetime: "2025-01-01 00:00:00".to_string(),
            timezone: "+08:00".to_string(),
        };
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"timestamp_ms\""));
    }

    #[test]
    fn test_rate_limiter_default() {
        let limiter = RateLimiter::default_limiter();
        assert!(limiter.check("127.0.0.1"));
        assert_eq!(limiter.remaining("127.0.0.1"), 99);
    }

    #[test]
    fn test_rate_limiter_exceeded() {
        let limiter = RateLimiter::new(2, std::time::Duration::from_secs(60));
        assert!(limiter.check("127.0.0.1"));
        assert!(limiter.check("127.0.0.1"));
        assert!(!limiter.check("127.0.0.1")); // third request should be blocked
        assert_eq!(limiter.remaining("127.0.0.1"), 0);
    }

    #[test]
    fn test_rate_limiter_multiple_ips() {
        let limiter = RateLimiter::new(1, std::time::Duration::from_secs(60));
        assert!(limiter.check("192.168.1.1"));
        assert!(limiter.check("192.168.1.2"));
        assert!(!limiter.check("192.168.1.1"));
        assert!(limiter.check("192.168.1.3"));
    }

    #[test]
    fn test_rate_limiter_reset() {
        let limiter = RateLimiter::new(1, std::time::Duration::from_secs(60));
        assert!(limiter.check("127.0.0.1"));
        assert!(!limiter.check("127.0.0.1"));
        limiter.reset("127.0.0.1");
        assert!(limiter.check("127.0.0.1"));
    }

    #[test]
    fn test_rate_limiter_reset_all() {
        let limiter = RateLimiter::new(1, std::time::Duration::from_secs(60));
        assert!(limiter.check("127.0.0.1"));
        assert!(limiter.check("192.168.1.1"));
        limiter.reset_all();
        assert!(limiter.check("127.0.0.1"));
        assert!(limiter.check("192.168.1.1"));
    }
}
