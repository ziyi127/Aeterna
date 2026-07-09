use serde::{Deserialize, Serialize};

/// 考试材料信息
///
/// 表示考试需要准备的材料，如试卷、答题卡等。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExamMaterial {
    /// 材料名称，如"试卷"、"答题卡"、"草稿纸"等
    pub name: String,
    /// 材料数量
    pub quantity: i32,
    /// 材料单位，如"张"、"份"、"本"等
    pub unit: String,
}

/// 单场考试信息
///
/// 包含考试名称、起止时间、提醒时间及材料清单。
/// 由 JSON 反序列化生成，`start` 和 `end` 字段支持
/// `YYYY-MM-DD HH:MM:SS` 格式。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExamInfo {
    /// 考试名称，如"语文"、"数学"
    pub name: String,
    /// 考试开始时间，格式 `YYYY-MM-DD HH:MM:SS`
    pub start: String,
    /// 考试结束时间，格式 `YYYY-MM-DD HH:MM:SS`
    pub end: String,
    /// 考试结束前几分钟提醒（0 表示不提醒）
    #[serde(rename = "alertTime")]
    pub alert_time: i32,
    /// 考试材料清单，`None` 表示无材料
    pub materials: Option<Vec<ExamMaterial>>,
}

/// 完整考试配置
///
/// 对应 JSON 文件中 `examName` / `message` / `examInfos` 三层结构。
/// 是应用核心数据模型，由解析器、编辑器、播放器共享。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExamConfig {
    /// 考试名称，如"期末考试"
    #[serde(rename = "examName")]
    pub exam_name: String,
    /// 考试相关公告信息
    pub message: String,
    /// 考试信息列表，按时间排序后使用
    #[serde(rename = "examInfos")]
    pub exam_infos: Vec<ExamInfo>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deserialize_exam_config() {
        let json = r#"{
            "examName": "期末考试",
            "message": "请认真答题",
            "examInfos": [
                {
                    "name": "语文",
                    "start": "2025-06-15 08:00:00",
                    "end": "2025-06-15 10:00:00",
                    "alertTime": 5,
                    "materials": [
                        {"name": "试卷", "quantity": 1, "unit": "份"},
                        {"name": "答题卡", "quantity": 1, "unit": "张"}
                    ]
                },
                {
                    "name": "数学",
                    "start": "2025-06-15 14:00:00",
                    "end": "2025-06-15 16:00:00",
                    "alertTime": 10
                }
            ]
        }"#;

        let config: ExamConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.exam_name, "期末考试");
        assert_eq!(config.message, "请认真答题");
        assert_eq!(config.exam_infos.len(), 2);
        assert_eq!(config.exam_infos[0].name, "语文");
        assert_eq!(config.exam_infos[0].alert_time, 5);
        assert_eq!(config.exam_infos[1].name, "数学");
        assert_eq!(config.exam_infos[1].alert_time, 10);
        assert!(config.exam_infos[1].materials.is_none());

        let materials = config.exam_infos[0].materials.as_ref().unwrap();
        assert_eq!(materials.len(), 2);
        assert_eq!(materials[0].name, "试卷");
        assert_eq!(materials[0].quantity, 1);
        assert_eq!(materials[0].unit, "份");
    }

    #[test]
    fn test_serialize_exam_config() {
        let config = ExamConfig {
            exam_name: "测试".to_string(),
            message: "测试消息".to_string(),
            exam_infos: vec![ExamInfo {
                name: "测试科目".to_string(),
                start: "2025-01-01 09:00:00".to_string(),
                end: "2025-01-01 10:00:00".to_string(),
                alert_time: 5,
                materials: None,
            }],
        };

        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("\"examName\""));
        assert!(json.contains("\"examInfos\""));
        assert!(json.contains("\"alertTime\""));
    }
}