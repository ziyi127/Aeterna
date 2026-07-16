use crate::core::types::ExamConfig;
use crate::core::types::ExamInfo;
use crate::core::utils::parse_date_time;
use serde::Serialize;
use std::cmp::Ordering;

/// 按考试开始时间升序的比较器。
///
/// 使用缓存的 `start_ts` 字段；未缓存的项（值为 0）会排在最前面。
fn cmp_exam_by_start(a: &ExamInfo, b: &ExamInfo) -> Ordering {
    a.start_ts.cmp(&b.start_ts)
}

/// 解析考试配置的 JSON 字符串，并返回 `ExamConfig` 对象。
///
/// 对应 TS 的 `parseExamConfig` 函数。
/// 如果解析成功且包含 `exam_infos` 字段，则返回 `ExamConfig` 对象；否则返回 `None`。
pub fn parse_exam_config(json: &str) -> Option<ExamConfig> {
    match serde_json::from_str::<serde_json::Value>(json) {
        Ok(data) => {
            data.get("examInfos")?;
            serde_json::from_value::<ExamConfig>(data).ok()
        }
        Err(_) => None,
    }
}

/// 验证考试配置是否有效。
///
/// 委托给 [`validate_exam_config_with_details`]，仅返回布尔结果。
/// 保留此便捷函数以避免强制所有调用点处理报告。
pub fn validate_exam_config(config: &ExamConfig) -> bool {
    validate_exam_config_with_details(config).errors.is_empty()
}

/// 检查考试时间是否有重叠。
///
/// 对应 TS 的 `hasExamTimeOverlap` 函数。
/// 先按 start 升序排序，然后检查相邻考试：如果前一场的 end > 后一场的 start，则有重叠。
pub fn has_exam_time_overlap(config: &ExamConfig) -> bool {
    let mut sorted: Vec<&ExamInfo> = config.exam_infos.iter().collect();
    sorted.sort_by(|a, b| cmp_exam_by_start(a, b));

    for i in 0..sorted.len().saturating_sub(1) {
        if sorted[i].end_ts > sorted[i + 1].start_ts {
            return true;
        }
    }
    false
}

/// 根据考试配置信息获取排序后的考试信息列表。
///
/// 对应 TS 的 `getSortedExamInfos` 函数。
/// 按考试开始时间升序排列。
pub fn get_sorted_exam_infos(config: &ExamConfig) -> Vec<ExamInfo> {
    let mut infos = config.exam_infos.clone();
    infos.sort_by(cmp_exam_by_start);
    infos
}

/// 返回包含排序后考试信息的完整配置对象。
///
/// 对应 TS 的 `getSortedExamConfig` 函数。
/// 考试信息按开始时间升序排列。
pub fn get_sorted_exam_config(config: ExamConfig) -> ExamConfig {
    let sorted_infos = get_sorted_exam_infos(&config);
    ExamConfig {
        exam_infos: sorted_infos,
        ..config
    }
}

/// 校验报告中的单条问题记录。
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ValidationIssue {
    /// 问题类型，"error" 或 "warning"。
    #[serde(rename = "type")]
    pub issue_type: String,
    /// 涉及的考试在 `exam_infos` 中的全局索引，全局问题为 `None`。
    #[serde(rename = "examIndex")]
    pub exam_index: Option<usize>,
    /// 相关字段名。
    pub field: String,
    /// 中文描述信息。
    pub message: String,
}

impl ValidationIssue {
    fn error(exam_index: Option<usize>, field: &str, message: &str) -> Self {
        Self {
            issue_type: "error".to_string(),
            exam_index,
            field: field.to_string(),
            message: message.to_string(),
        }
    }

    fn warning(exam_index: Option<usize>, field: &str, message: &str) -> Self {
        Self {
            issue_type: "warning".to_string(),
            exam_index,
            field: field.to_string(),
            message: message.to_string(),
        }
    }
}

/// 结构化校验报告，包含错误和警告列表。
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ValidationReport {
    pub errors: Vec<ValidationIssue>,
    pub warnings: Vec<ValidationIssue>,
}

impl ValidationReport {
    fn empty() -> Self {
        Self {
            errors: vec![],
            warnings: vec![],
        }
    }

    /// 仅包含一条错误的报告，常用于 JSON 解析或文件读取失败的场景。
    pub fn single_error(field: &str, message: String) -> Self {
        Self {
            errors: vec![ValidationIssue::error(None, field, &message)],
            warnings: vec![],
        }
    }

    /// 返回校验报告是否无错误（warnings 不影响此判断）。
    #[allow(dead_code)]
    pub fn is_valid(&self) -> bool {
        self.errors.is_empty()
    }
}

/// 对考试配置进行结构化校验，返回包含错误和警告的校验报告。
///
/// 校验规则：
/// - 全局 `exam_name` 非空；
/// - 每个考试的 `name` 非空；
/// - 每个考试的 `start` 非空且能被 `parse_date_time` 解析；
/// - 每个考试的 `end` 非空且能被 `parse_date_time` 解析；
/// - `end` 时间戳必须大于 `start` 时间戳；
/// - `alert_time` 必须在 0-999 范围内；
/// - 考试时间重叠会作为 warning，涉及的两个考试都会添加警告。
pub fn validate_exam_config_with_details(config: &ExamConfig) -> ValidationReport {
    let mut report = ValidationReport::empty();

    // 全局 exam_name 校验
    if config.exam_name.trim().is_empty() {
        report
            .errors
            .push(ValidationIssue::error(None, "examName", "考试名称不能为空"));
    }

    // 先收集每个考试可解析的时间区间，用于后续重叠判断
    let mut parsed_intervals: Vec<Option<(i64, i64)>> = Vec::with_capacity(config.exam_infos.len());

    for (index, info) in config.exam_infos.iter().enumerate() {
        // name 非空
        if info.name.trim().is_empty() {
            report.errors.push(ValidationIssue::error(
                Some(index),
                "name",
                "考试名称不能为空",
            ));
        }

        // start 非空且可解析
        let start_ts = if info.start.trim().is_empty() {
            report.errors.push(ValidationIssue::error(
                Some(index),
                "start",
                "开始时间不能为空",
            ));
            None
        } else {
            match parse_date_time(&info.start) {
                Some(dt) => Some(dt.timestamp_millis()),
                None => {
                    report.errors.push(ValidationIssue::error(
                        Some(index),
                        "start",
                        "开始时间格式不正确",
                    ));
                    None
                }
            }
        };

        // end 非空且可解析
        let end_ts = if info.end.trim().is_empty() {
            report.errors.push(ValidationIssue::error(
                Some(index),
                "end",
                "结束时间不能为空",
            ));
            None
        } else {
            match parse_date_time(&info.end) {
                Some(dt) => Some(dt.timestamp_millis()),
                None => {
                    report.errors.push(ValidationIssue::error(
                        Some(index),
                        "end",
                        "结束时间格式不正确",
                    ));
                    None
                }
            }
        };

        // end 必须大于 start
        if let (Some(s), Some(e)) = (start_ts, end_ts) {
            if e <= s {
                report.errors.push(ValidationIssue::error(
                    Some(index),
                    "end",
                    "结束时间必须晚于开始时间",
                ));
            }
            parsed_intervals.push(Some((s, e)));
        } else {
            parsed_intervals.push(None);
        }

        // alert_time 范围
        if info.alert_time < 0 || info.alert_time > 999 {
            report.errors.push(ValidationIssue::error(
                Some(index),
                "alertTime",
                "提醒时间必须在 0-999 分钟之间",
            ));
        }
    }

    // 考试时间重叠检测
    for i in 0..config.exam_infos.len() {
        for j in (i + 1)..config.exam_infos.len() {
            if let (Some((s1, e1)), Some((s2, e2))) = (&parsed_intervals[i], &parsed_intervals[j]) {
                if s1 < e2 && s2 < e1 {
                    let msg_i = format!(
                        "考试 '{}' 与 '{}' 的时间存在重叠",
                        config.exam_infos[i].name, config.exam_infos[j].name
                    );
                    let msg_j = format!(
                        "考试 '{}' 与 '{}' 的时间存在重叠",
                        config.exam_infos[j].name, config.exam_infos[i].name
                    );
                    report
                        .warnings
                        .push(ValidationIssue::warning(Some(i), "timeOverlap", &msg_i));
                    report
                        .warnings
                        .push(ValidationIssue::warning(Some(j), "timeOverlap", &msg_j));
                }
            }
        }
    }

    report
}

/// 按开始时间升序排列考试信息，保留 `exam_name` 和 `message`。
pub fn sort_exam_config_by_start(config: ExamConfig) -> ExamConfig {
    get_sorted_exam_config(config)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::types::ExamConfig;
    use crate::core::types::ExamInfo;

    fn make_test_config() -> ExamConfig {
        let mut config = ExamConfig {
            exam_name: "期末考试".to_string(),
            message: "请认真答题".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 10,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        config
    }

    fn make_overlapping_config() -> ExamConfig {
        let mut config = ExamConfig {
            exam_name: "重叠考试".to_string(),
            message: "时间有重叠".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 09:00:00".to_string(),
                    end: "2025-06-15 11:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        config
    }

    #[test]
    fn test_parse_exam_config_valid() {
        let json = r#"{
            "examName": "期末考试",
            "message": "请认真答题",
            "examInfos": [
                {
                    "name": "语文",
                    "start": "2025-06-15 08:00:00",
                    "end": "2025-06-15 10:00:00",
                    "alertTime": 5
                }
            ]
        }"#;
        let config = parse_exam_config(json);
        assert!(config.is_some());
        let config = config.unwrap();
        assert_eq!(config.exam_name, "期末考试");
        assert_eq!(config.exam_infos.len(), 1);
    }

    #[test]
    fn test_parse_exam_config_invalid_json() {
        let result = parse_exam_config("not valid json");
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_exam_config_missing_exam_infos() {
        let json = r#"{"examName": "test", "message": "test"}"#;
        let result = parse_exam_config(json);
        assert!(result.is_none());
    }

    #[test]
    fn test_validate_exam_config_valid() {
        let config = make_test_config();
        assert!(validate_exam_config(&config));
    }

    #[test]
    fn test_validate_exam_config_empty_exam_infos() {
        let mut config = ExamConfig {
            exam_name: "空考试".to_string(),
            message: "无考试".to_string(),
            exam_infos: vec![],
        };
        config.cache_timestamps();
        assert!(validate_exam_config(&config));
    }

    #[test]
    fn test_validate_exam_config_empty_name() {
        let mut config = make_test_config();
        config.exam_infos[0].name = "   ".to_string();
        assert!(!validate_exam_config(&config));
    }

    #[test]
    fn test_validate_exam_config_empty_start() {
        let mut config = make_test_config();
        config.exam_infos[0].start = "".to_string();
        assert!(!validate_exam_config(&config));
    }

    #[test]
    fn test_validate_exam_config_negative_alert_time() {
        let mut config = make_test_config();
        config.exam_infos[0].alert_time = -1;
        assert!(!validate_exam_config(&config));
    }

    #[test]
    fn test_has_exam_time_overlap_no_overlap() {
        let config = make_test_config();
        assert!(!has_exam_time_overlap(&config));
    }

    #[test]
    fn test_has_exam_time_overlap_with_overlap() {
        let config = make_overlapping_config();
        assert!(has_exam_time_overlap(&config));
    }

    #[test]
    fn test_has_exam_time_overlap_adjacent() {
        let mut config = ExamConfig {
            exam_name: "相邻考试".to_string(),
            message: "".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 10:00:00".to_string(),
                    end: "2025-06-15 12:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        // 前一场结束 = 后一场开始，不应视为重叠
        assert!(!has_exam_time_overlap(&config));
    }

    #[test]
    fn test_get_sorted_exam_infos() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 10,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        let sorted = get_sorted_exam_infos(&config);
        assert_eq!(sorted[0].name, "语文");
        assert_eq!(sorted[1].name, "数学");
    }

    #[test]
    fn test_get_sorted_exam_config() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "消息".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 10,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        let sorted = get_sorted_exam_config(config);
        assert_eq!(sorted.exam_name, "测试");
        assert_eq!(sorted.message, "消息");
        assert_eq!(sorted.exam_infos[0].name, "语文");
        assert_eq!(sorted.exam_infos[1].name, "数学");
    }

    #[test]
    fn test_validate_exam_config_with_details_valid() {
        let config = make_test_config();
        let report = validate_exam_config_with_details(&config);
        assert!(report.errors.is_empty());
        assert!(report.warnings.is_empty());
    }

    #[test]
    fn test_validate_exam_config_with_details_empty_exam_name() {
        let mut config = make_test_config();
        config.exam_name = "   ".to_string();
        let report = validate_exam_config_with_details(&config);
        assert_eq!(report.errors.len(), 1);
        assert_eq!(report.errors[0].issue_type, "error");
        assert_eq!(report.errors[0].exam_index, None);
        assert_eq!(report.errors[0].field, "examName");
    }

    #[test]
    fn test_validate_exam_config_with_details_empty_exam_name_is_warning_free() {
        let mut config = make_test_config();
        config.exam_name = "".to_string();
        let report = validate_exam_config_with_details(&config);
        assert!(!report.errors.is_empty());
        assert!(report.warnings.is_empty());
    }

    #[test]
    fn test_validate_exam_config_with_details_empty_name() {
        let mut config = make_test_config();
        config.exam_infos[0].name = "".to_string();
        let report = validate_exam_config_with_details(&config);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "name"));
    }

    #[test]
    fn test_validate_exam_config_with_details_invalid_start() {
        let mut config = make_test_config();
        config.exam_infos[0].start = "not-a-date".to_string();
        let report = validate_exam_config_with_details(&config);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "start"));
    }

    #[test]
    fn test_validate_exam_config_with_details_empty_end() {
        let mut config = make_test_config();
        config.exam_infos[0].end = "".to_string();
        let report = validate_exam_config_with_details(&config);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "end"));
    }

    #[test]
    fn test_validate_exam_config_with_details_end_not_after_start() {
        let mut config = make_test_config();
        config.exam_infos[0].start = "2025-06-15 10:00:00".to_string();
        config.exam_infos[0].end = "2025-06-15 10:00:00".to_string();
        let report = validate_exam_config_with_details(&config);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "end" && e.message.contains("晚于")));
    }

    #[test]
    fn test_validate_exam_config_with_details_alert_time_out_of_range() {
        let mut config = make_test_config();
        config.exam_infos[0].alert_time = 1000;
        config.exam_infos[1].alert_time = -1;
        let report = validate_exam_config_with_details(&config);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "alertTime"));
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(1) && e.field == "alertTime"));
    }

    #[test]
    fn test_validate_exam_config_with_details_time_overlap_warning() {
        let config = make_overlapping_config();
        let report = validate_exam_config_with_details(&config);
        assert!(report.errors.is_empty());
        assert_eq!(report.warnings.len(), 2);
        assert!(report
            .warnings
            .iter()
            .all(|w| w.issue_type == "warning" && w.field == "timeOverlap"));
        assert!(report.warnings.iter().any(|w| w.exam_index == Some(0)));
        assert!(report.warnings.iter().any(|w| w.exam_index == Some(1)));
    }

    #[test]
    fn test_validate_exam_config_with_details_multiple_errors() {
        let mut config = ExamConfig {
            exam_name: "".to_string(),
            message: "msg".to_string(),
            exam_infos: vec![ExamInfo {
                name: "".to_string(),
                start: "bad".to_string(),
                end: "worse".to_string(),
                alert_time: 1234,
                materials: None,
                start_ts: 0,
                end_ts: 0,
            }],
        };
        config.cache_timestamps();
        let report = validate_exam_config_with_details(&config);
        assert_eq!(report.errors.len(), 5);
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index.is_none() && e.field == "examName"));
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "name"));
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "start"));
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "end"));
        assert!(report
            .errors
            .iter()
            .any(|e| e.exam_index == Some(0) && e.field == "alertTime"));
    }

    #[test]
    fn test_validate_exam_config_with_details_serializable() {
        let config = make_overlapping_config();
        let report = validate_exam_config_with_details(&config);
        let json = serde_json::to_string(&report).unwrap();
        assert!(json.contains("\"errors\""));
        assert!(json.contains("\"warnings\""));
        assert!(json.contains("\"type\""));
        assert!(json.contains("\"examIndex\""));
        assert!(json.contains("\"field\""));
        assert!(json.contains("\"message\""));
    }

    #[test]
    fn test_sort_exam_config_by_start() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "消息".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 10,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "语文".to_string(),
                    start: "2025-06-15 08:00:00".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "英语".to_string(),
                    start: "2025-06-15 10:00:00".to_string(),
                    end: "2025-06-15 12:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        let sorted = sort_exam_config_by_start(config);
        assert_eq!(sorted.exam_name, "测试");
        assert_eq!(sorted.message, "消息");
        assert_eq!(sorted.exam_infos[0].name, "语文");
        assert_eq!(sorted.exam_infos[1].name, "英语");
        assert_eq!(sorted.exam_infos[2].name, "数学");
    }

    #[test]
    fn test_sort_exam_config_by_start_invalid_time_fallback() {
        let mut config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "消息".to_string(),
            exam_infos: vec![
                ExamInfo {
                    name: "数学".to_string(),
                    start: "2025-06-15 14:00:00".to_string(),
                    end: "2025-06-15 16:00:00".to_string(),
                    alert_time: 10,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
                ExamInfo {
                    name: "语文".to_string(),
                    start: "invalid".to_string(),
                    end: "2025-06-15 10:00:00".to_string(),
                    alert_time: 5,
                    materials: None,
                    start_ts: 0,
                    end_ts: 0,
                },
            ],
        };
        config.cache_timestamps();
        let sorted = sort_exam_config_by_start(config);
        // 不可解析的时间会回退到 0，因此排在最前面
        assert_eq!(sorted.exam_infos[0].name, "语文");
        assert_eq!(sorted.exam_infos[1].name, "数学");
    }
}
