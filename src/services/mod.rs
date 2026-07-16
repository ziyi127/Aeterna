//! 服务层模块
//!
//! 提供后台服务功能：
//! - `ntp`: NTP 时间同步服务
//! - `http_api`: HTTP API 服务（基于 actix-web）
//! - `cast`: mDNS 设备发现与投屏服务
pub mod cast;
pub mod http_api;
pub mod ntp;
