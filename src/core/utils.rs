use chrono::{DateTime, Duration, Local, NaiveDateTime, TimeZone};
use std::io::Write;
use std::path::{Path, PathBuf};

/// 获取 Aeterna 配置目录路径。
///
/// 优先使用 `dirs::config_dir()/Aeterna`，无法获取平台目录时回退到临时目录，
/// 避免在应用安装目录或不可预测的当前目录中写入用户数据。
pub fn aeterna_config_dir() -> PathBuf {
    dirs::config_dir()
        .or_else(|| Some(std::env::temp_dir()))
        .unwrap_or_else(std::env::temp_dir)
        .join("Aeterna")
}

/// Replace a UTF-8 file using an adjacent temporary file.
///
/// The rename is atomic on platforms that allow replacing an existing file.
/// Windows requires a remove-and-retry fallback because the standard library
/// does not expose an atomic replace primitive there.
pub fn atomic_write(path: &Path, content: &[u8]) -> std::io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "path has no parent directory",
        )
    })?;
    std::fs::create_dir_all(parent)?;

    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "path has no file name")
        })?;
    let temporary = parent.join(format!(".{}.{}.tmp", file_name, std::process::id()));
    let write_result = (|| -> std::io::Result<()> {
        let mut file = std::fs::File::create(&temporary)?;
        file.write_all(content)?;
        file.sync_all()?;
        drop(file);

        // Do not remove the old file as a replacement fallback. On Windows,
        // `rename` may reject replacing an open destination; returning that
        // error preserves the previously valid settings instead of risking a
        // missing file if a second rename fails.
        std::fs::rename(&temporary, path)
    })();

    if write_result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    write_result
}

/// Convert a QML file URL or a native path into a filesystem path.
///
/// QML file dialogs provide `file:` URLs while existing callers may pass a
/// native path. URL decoding happens exactly once at this boundary.
pub fn qml_file_input_to_path(input: &str) -> Result<PathBuf, String> {
    if !input.contains("://") && !input.starts_with("file:") {
        return Ok(PathBuf::from(input));
    }
    let rest = input
        .strip_prefix("file:")
        .ok_or_else(|| "只支持本地 file URL".to_string())?;
    if rest.contains('?') || rest.contains('#') {
        return Err("file URL 中的路径必须编码 ? 和 #".to_string());
    }

    let (authority, encoded_path) = if let Some(rest) = rest.strip_prefix("//") {
        match rest.find('/') {
            Some(index) => (&rest[..index], &rest[index..]),
            None => (rest, ""),
        }
    } else {
        ("", rest)
    };
    let decoded = percent_decode_path(encoded_path)?;

    #[cfg(windows)]
    {
        if !authority.is_empty() && !authority.eq_ignore_ascii_case("localhost") {
            return Ok(PathBuf::from(format!(
                r"\\{}{}",
                authority,
                decoded.replace('/', r"\")
            )));
        }
        let path = decoded.strip_prefix('/').unwrap_or(&decoded);
        return Ok(PathBuf::from(path));
    }
    #[cfg(not(windows))]
    {
        if !authority.is_empty() && !authority.eq_ignore_ascii_case("localhost") {
            return Err("当前平台不支持 file URL 网络主机".to_string());
        }
        Ok(PathBuf::from(decoded))
    }
}

fn percent_decode_path(value: &str) -> Result<String, String> {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            if index + 2 >= bytes.len() {
                return Err("file URL 包含不完整的百分号编码".to_string());
            }
            let high = hex_value(bytes[index + 1])
                .ok_or_else(|| "file URL 包含无效百分号编码".to_string())?;
            let low = hex_value(bytes[index + 2])
                .ok_or_else(|| "file URL 包含无效百分号编码".to_string())?;
            decoded.push(high << 4 | low);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8(decoded).map_err(|_| "file URL 不是有效 UTF-8 路径".to_string())
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

/// 将 DateTime 对象格式化为本地时间字符串。
#[allow(dead_code)]
pub fn format_local_date_time(date: DateTime<Local>) -> String {
    date.format("%Y-%m-%d %H:%M:%S").to_string()
}

/// 将 DateTime 对象格式化为显示用的时间字符串。
#[allow(dead_code)]
pub fn format_display_time(date: DateTime<Local>) -> String {
    date.format("%m/%d %H:%M").to_string()
}

/// 将时间字符串格式化为时间段显示字符串。
/// 如果任一参数无效，返回 "时间待设置"。
#[allow(dead_code)]
pub fn format_time_range(start: &str, end: &str) -> String {
    let start_dt = match parse_date_time(start) {
        Some(dt) => dt,
        None => return "时间待设置".to_string(),
    };
    let end_dt = match parse_date_time(end) {
        Some(dt) => dt,
        None => return "时间待设置".to_string(),
    };

    let start_str = format_display_time(start_dt);
    let end_str = end_dt.format("%H:%M").to_string();

    format!("{} - {}", start_str, end_str)
}

/// 解析时间字符串为 DateTime<Local> 对象。
///
/// 对应 TS 的 `parseDateTime` 函数。
/// 支持多种格式：
/// - ISO 格式（含 T 或 Z）
/// - "YYYY-MM-DD HH:mm:ss" 本地格式
/// - 其他 chrono 可识别的格式
pub fn parse_date_time(s: &str) -> Option<DateTime<Local>> {
    if s.is_empty() {
        return None;
    }

    // 如果是 ISO 格式（含 T 或 Z）
    if s.contains('T') || s.contains('Z') {
        // 尝试解析 ISO 8601
        if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(s) {
            return Some(dt.with_timezone(&Local));
        }
        // 尝试其他 ISO 变体
        if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S") {
            return Local.from_local_datetime(&dt).single();
        }
    }

    // 尝试 "YYYY-MM-DD HH:mm:ss" 格式（本地时间）
    if let Ok(naive) = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S") {
        return Local.from_local_datetime(&naive).single();
    }

    // 尝试 "YYYY-MM-DD HH:mm" 格式
    if let Ok(naive) = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M") {
        return Local.from_local_datetime(&naive).single();
    }

    // 尝试 "YYYY/MM/DD HH:mm:ss" 格式
    if let Ok(naive) = NaiveDateTime::parse_from_str(s, "%Y/%m/%d %H:%M:%S") {
        return Local.from_local_datetime(&naive).single();
    }

    // 最后尝试 RFC 2822
    if let Ok(dt) = chrono::DateTime::parse_from_rfc2822(s) {
        return Some(dt.with_timezone(&Local));
    }

    None
}

#[allow(dead_code)]
pub fn get_current_local_date_time() -> DateTime<Local> {
    Local::now()
}

/// 检查两个时间段是否重叠（半开区间：s1 < e2 && s2 < e1）。
#[allow(dead_code)]
pub fn is_time_range_overlap(start1: &str, end1: &str, start2: &str, end2: &str) -> bool {
    let s1 = match parse_date_time(start1) {
        Some(dt) => dt.timestamp_millis(),
        None => return false,
    };
    let e1 = match parse_date_time(end1) {
        Some(dt) => dt.timestamp_millis(),
        None => return false,
    };
    let s2 = match parse_date_time(start2) {
        Some(dt) => dt.timestamp_millis(),
        None => return false,
    };
    let e2 = match parse_date_time(end2) {
        Some(dt) => dt.timestamp_millis(),
        None => return false,
    };

    s1 < e2 && s2 < e1
}

/// 计算两个时间点之间的分钟差。
#[allow(dead_code)]
pub fn get_minutes_difference(start: &str, end: &str) -> Option<i64> {
    let start_time = parse_date_time(start)?.timestamp_millis();
    let end_time = parse_date_time(end)?.timestamp_millis();
    let diff_ms = end_time - start_time;
    // 四舍五入，与 TS 中 Math.round 行为一致
    let diff_sec = diff_ms as f64 / 1000.0;
    let minutes = (diff_sec / 60.0).round() as i64;
    Some(minutes)
}

/// 解析时间字符串为毫秒时间戳。
///
/// 便捷方法，等价于 `parse_date_time(s).map(|d| d.timestamp_millis()).unwrap_or(0)`。
/// 解析失败时返回 0。
pub fn parse_date_time_ms(s: &str) -> i64 {
    parse_date_time(s)
        .map(|d| d.timestamp_millis())
        .unwrap_or(0)
}

/// 在给定时间字符串上增加若干分钟。
#[allow(dead_code)]
pub fn add_minutes_to_datetime(start: &str, minutes: i64) -> Option<String> {
    let dt = parse_date_time(start)?;
    let result = dt + Duration::minutes(minutes);
    Some(format_local_date_time(result))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Local;

    #[test]
    fn test_qml_file_input_to_path_decodes_file_url() {
        assert_eq!(
            qml_file_input_to_path("file:///tmp/Exam%20%E6%B5%8B%E8%AF%95.json").unwrap(),
            PathBuf::from("/tmp/Exam 测试.json")
        );
    }

    #[test]
    fn test_qml_file_input_to_path_rejects_invalid_url_encoding() {
        assert!(qml_file_input_to_path("file:///tmp/%ZZ.json").is_err());
        assert!(qml_file_input_to_path("https://example.test/config.json").is_err());
    }

    #[cfg(not(windows))]
    #[test]
    fn test_qml_file_input_to_path_rejects_remote_authority() {
        assert!(qml_file_input_to_path("file://server/share/config.json").is_err());
    }

    #[test]
    fn test_atomic_write_replaces_existing_content() {
        let path = std::env::temp_dir().join(format!(
            "aeterna-atomic-write-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        std::fs::write(&path, "old").unwrap();
        atomic_write(&path, b"new").unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "new");
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn test_format_local_date_time() {
        // 使用一个固定时间戳来测试，避免时区问题
        let dt = Local::now();
        let formatted = format_local_date_time(dt);
        // 格式应为 YYYY-MM-DD HH:mm:ss
        let parts: Vec<&str> = formatted.split(' ').collect();
        assert_eq!(parts.len(), 2);
        let date_parts: Vec<&str> = parts[0].split('-').collect();
        let time_parts: Vec<&str> = parts[1].split(':').collect();
        assert_eq!(date_parts.len(), 3);
        assert_eq!(time_parts.len(), 3);
        // 验证每个部分都是有效的数字
        for part in date_parts.iter().chain(time_parts.iter()) {
            assert!(part.parse::<u32>().is_ok());
        }
    }

    #[test]
    fn test_format_display_time() {
        let dt = Local::now();
        let formatted = format_display_time(dt);
        // 格式应为 MM/DD HH:MM
        assert!(formatted.len() >= 11);
        assert!(formatted.contains('/'));
        assert!(formatted.contains(':'));
        assert!(formatted.contains(' '));
    }

    #[test]
    fn test_format_time_range() {
        let result = format_time_range("2025-06-15 08:00:00", "2025-06-15 10:00:00");
        assert!(result.contains(" - "));
        assert!(!result.contains("时间待设置"));
    }

    #[test]
    fn test_format_time_range_invalid() {
        let result = format_time_range("invalid", "2025-06-15 10:00:00");
        assert_eq!(result, "时间待设置");
    }

    #[test]
    fn test_parse_date_time_standard_format() {
        let result = parse_date_time("2025-06-15 08:30:00");
        assert!(result.is_some());
        let dt = result.unwrap();
        assert_eq!(
            dt.format("%Y-%m-%d %H:%M:%S").to_string(),
            "2025-06-15 08:30:00"
        );
    }

    #[test]
    fn test_parse_date_time_iso_format() {
        let result = parse_date_time("2025-06-15T08:30:00+08:00");
        assert!(result.is_some());
    }

    #[test]
    fn test_parse_date_time_empty() {
        let result = parse_date_time("");
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_date_time_invalid() {
        let result = parse_date_time("not a date");
        assert!(result.is_none());
    }

    #[test]
    fn test_get_current_local_date_time() {
        let dt = get_current_local_date_time();
        let formatted = format_local_date_time(dt);
        assert!(!formatted.is_empty());
    }

    #[test]
    fn test_is_time_range_overlap_no_overlap() {
        assert!(!is_time_range_overlap(
            "2025-06-15 08:00:00",
            "2025-06-15 10:00:00",
            "2025-06-15 10:00:00",
            "2025-06-15 12:00:00"
        ));
    }

    #[test]
    fn test_is_time_range_overlap_with_overlap() {
        assert!(is_time_range_overlap(
            "2025-06-15 08:00:00",
            "2025-06-15 10:00:00",
            "2025-06-15 09:00:00",
            "2025-06-15 11:00:00"
        ));
    }

    #[test]
    fn test_is_time_range_overlap_invalid() {
        assert!(!is_time_range_overlap(
            "invalid",
            "2025-06-15 10:00:00",
            "2025-06-15 09:00:00",
            "2025-06-15 11:00:00"
        ));
    }

    #[test]
    fn test_get_minutes_difference() {
        let result = get_minutes_difference("2025-06-15 08:00:00", "2025-06-15 09:00:00");
        assert_eq!(result, Some(60));
    }

    #[test]
    fn test_get_minutes_difference_half_hour() {
        let result = get_minutes_difference("2025-06-15 08:00:00", "2025-06-15 08:30:00");
        assert_eq!(result, Some(30));
    }

    #[test]
    fn test_get_minutes_difference_invalid() {
        let result = get_minutes_difference("invalid", "2025-06-15 09:00:00");
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_date_time_with_short_format() {
        let result = parse_date_time("2025-06-15 08:30");
        assert!(result.is_some());
        let dt = result.unwrap();
        assert_eq!(dt.format("%Y-%m-%d %H:%M").to_string(), "2025-06-15 08:30");
    }

    #[test]
    fn test_add_minutes_to_datetime_add_60() {
        let result = add_minutes_to_datetime("2025-06-15 08:00:00", 60);
        assert_eq!(result, Some("2025-06-15 09:00:00".to_string()));
    }

    #[test]
    fn test_add_minutes_to_datetime_add_10() {
        let result = add_minutes_to_datetime("2025-06-15 08:50:00", 10);
        assert_eq!(result, Some("2025-06-15 09:00:00".to_string()));
    }

    #[test]
    fn test_add_minutes_to_datetime_cross_day() {
        let result = add_minutes_to_datetime("2025-06-15 23:50:00", 20);
        assert_eq!(result, Some("2025-06-16 00:10:00".to_string()));
    }

    #[test]
    fn test_add_minutes_to_datetime_invalid() {
        let result = add_minutes_to_datetime("invalid", 10);
        assert_eq!(result, None);
    }
}
