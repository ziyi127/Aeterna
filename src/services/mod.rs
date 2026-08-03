//! 服务层模块
//!
//! 提供后台服务功能：
//! - `ntp`: NTP 时间同步服务
//! - `http_api`: HTTP API 服务（纯 std 实现，无任何外部依赖）
//! - `cast`: mDNS 设备发现与投屏服务（仅在 `cast` feature 启用时编译）
#[cfg(feature = "cast")]
pub mod cast;
pub mod http_api;
pub mod ntp;
pub mod share_runtime;
