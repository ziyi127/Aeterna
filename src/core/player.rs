use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use crate::core::parser::{get_sorted_exam_infos, validate_exam_config};
use crate::core::types::{ExamConfig, ExamInfo};
use crate::core::utils::parse_date_time;

/// 考试状态
#[derive(Debug, Clone, PartialEq)]
pub enum ExamStatus {
    Pending,
    InProgress,
    Completed,
    Unknown,
}

/// 考试状态信息
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct ExamStatusInfo {
    pub status: ExamStatus,
    pub message: String,
    pub time_remaining_ms: Option<i64>,
    pub progress: Option<f64>,
}

/// 播放器核心状态
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PlayerState {
    pub current_exam_index: usize,
    pub loading: bool,
    pub loaded: bool,
    pub error: Option<String>,
}

/// 任务类型
///
/// 定义定时任务的触发时机：
/// - `Start`: 考试开始时触发
/// - `End`: 考试结束时触发
/// - `Alert`: 考试结束前提醒时触发
#[derive(Debug, Clone, PartialEq)]
enum TaskType {
    Start,
    End,
    Alert,
}

/// 单个任务
///
/// 表示一个待执行的定时任务，在 `execute_time_ms` 到达时触发。
#[derive(Debug, Clone)]
struct Task {
    #[allow(dead_code)]
    id: String,
    /// 任务执行时间（毫秒时间戳）
    execute_time_ms: i64,
    /// 任务类型
    task_type: TaskType,
    /// 关联的考试信息
    exam_info: ExamInfo,
    /// 提醒时间（分钟，仅 Alert 类型有效）
    alert_time: i32,
    /// 是否已执行
    executed: bool,
}

/// 播放器内部状态（线程安全）
///
/// 所有可变状态都集中在 `PlayerInner` 中，通过 `Mutex` 保护。
struct PlayerInner {
    /// 播放器状态
    state: PlayerState,
    /// 当前加载的考试配置
    config: Option<ExamConfig>,
    /// 当前时间（毫秒时间戳），由定时器线程每秒更新
    current_time_ms: i64,
    /// 待执行的任务队列
    tasks: Vec<Task>,
    /// 时间获取函数，支持 NTP 校正
    time_fn: Box<dyn Fn() -> i64 + Send + 'static>,
}

/// 考试开始回调类型
type ExamStartCallback = Arc<dyn Fn(&ExamInfo) + Send + Sync + 'static>;
/// 考试结束回调类型
type ExamEndCallback = Arc<dyn Fn(&ExamInfo) + Send + Sync + 'static>;
/// 考试提醒回调类型
type ExamAlertCallback = Arc<dyn Fn(&ExamInfo, i32) + Send + Sync + 'static>;
/// 考试切换回调类型
type ExamSwitchCallback = Arc<dyn Fn(&ExamInfo, &ExamInfo) + Send + Sync + 'static>;

/// 播放器核心状态机
///
/// 对应 TS 的 `ExamPlayerCore` 类。
/// 管理考试播放器的核心状态：当前考试、时间、计时器、任务调度等。
pub struct PlayerCore {
    inner: Arc<Mutex<PlayerInner>>,
    timer_handle: Mutex<Option<JoinHandle<()>>>,
    stop_flag: Arc<AtomicBool>,
    // 回调函数
    on_exam_start: Mutex<Option<ExamStartCallback>>,
    on_exam_end: Mutex<Option<ExamEndCallback>>,
    on_exam_alert: Mutex<Option<ExamAlertCallback>>,
    on_exam_switch: Mutex<Option<ExamSwitchCallback>>,
}

impl PlayerCore {
    /// 创建新的 PlayerCore 实例。
    ///
    /// 对应 TS 的构造函数。
    pub fn new(config: Option<ExamConfig>, time_fn: Box<dyn Fn() -> i64 + Send + 'static>) -> Self {
        let current_time = time_fn();
        let inner = PlayerInner {
            state: PlayerState::default(),
            config,
            current_time_ms: current_time,
            tasks: Vec::new(),
            time_fn,
        };

        PlayerCore {
            inner: Arc::new(Mutex::new(inner)),
            timer_handle: Mutex::new(None),
            stop_flag: Arc::new(AtomicBool::new(false)),
            on_exam_start: Mutex::new(None),
            on_exam_end: Mutex::new(None),
            on_exam_alert: Mutex::new(None),
            on_exam_switch: Mutex::new(None),
        }
    }

    /// 设置考试开始回调
    pub fn on_exam_start<F>(&self, callback: F)
    where
        F: Fn(&ExamInfo) + Send + Sync + 'static,
    {
        *self.on_exam_start.lock().unwrap() = Some(Arc::new(callback));
    }

    /// 设置考试结束回调
    pub fn on_exam_end<F>(&self, callback: F)
    where
        F: Fn(&ExamInfo) + Send + Sync + 'static,
    {
        *self.on_exam_end.lock().unwrap() = Some(Arc::new(callback));
    }

    /// 设置考试提醒回调
    pub fn on_exam_alert<F>(&self, callback: F)
    where
        F: Fn(&ExamInfo, i32) + Send + Sync + 'static,
    {
        *self.on_exam_alert.lock().unwrap() = Some(Arc::new(callback));
    }

    /// 设置考试切换回调
    #[allow(dead_code)]
    pub fn on_exam_switch<F>(&self, callback: F)
    where
        F: Fn(&ExamInfo, &ExamInfo) + Send + Sync + 'static,
    {
        *self.on_exam_switch.lock().unwrap() = Some(Arc::new(callback));
    }

    /// 启动计时器。
    ///
    /// 对应 TS 的 `start()` 方法。
    /// 每秒更新 current_time，并检查任务队列。
    /// 多次调用不会重复启动，回调可重复使用。
    pub fn start(&self) {
        {
            let handle = self.timer_handle.lock().unwrap();
            if handle.is_some() {
                return; // 已经启动
            }
        }

        self.stop_flag.store(false, Ordering::SeqCst);

        let inner = Arc::clone(&self.inner);
        let stop_flag = Arc::clone(&self.stop_flag);
        // 克隆回调引用而非消耗，支持 stop 后重新 start
        let on_start = self.on_exam_start.lock().unwrap().clone();
        let on_end = self.on_exam_end.lock().unwrap().clone();
        let on_alert = self.on_exam_alert.lock().unwrap().clone();
        let on_switch = self.on_exam_switch.lock().unwrap().clone();

        let handle = thread::spawn(move || {
            while !stop_flag.load(Ordering::SeqCst) {
                {
                    let mut inner = inner.lock().unwrap();
                    let now = (inner.time_fn)();
                    inner.current_time_ms = now;

                    // 检查任务队列
                    inner.tasks.retain(|task| {
                        if task.executed {
                            return false;
                        }
                        if now >= task.execute_time_ms {
                            match task.task_type {
                                TaskType::Start => {
                                    if let Some(ref cb) = on_start {
                                        cb(&task.exam_info);
                                    }
                                }
                                TaskType::End => {
                                    if let Some(ref cb) = on_end {
                                        cb(&task.exam_info);
                                    }
                                }
                                TaskType::Alert => {
                                    if let Some(ref cb) = on_alert {
                                        cb(&task.exam_info, task.alert_time);
                                    }
                                }
                            }
                            return false; // 移除已执行的任务
                        }
                        true
                    });

                    // 更新当前考试（每30秒检查一次，模拟 TS 中的 watch 行为）
                    if now % 30000 < 1000 {
                        Self::update_current_exam_inner(&mut inner);
                    }
                }

                thread::sleep(Duration::from_secs(1));
            }

            // 线程退出前保持回调引用存活
            let _ = (&on_start, &on_end, &on_alert, &on_switch);
        });

        {
            let mut timer_handle = self.timer_handle.lock().unwrap();
            *timer_handle = Some(handle);
        }
    }

    /// 停止计时器。
    ///
    /// 对应 TS 的 `stop()` 方法。
    /// 设置停止标志后等待线程结束，确保资源安全释放。
    pub fn stop(&self) {
        self.stop_flag.store(true, Ordering::SeqCst);

        let mut handle = self.timer_handle.lock().unwrap();
        if let Some(h) = handle.take() {
            // 等待线程结束，确保资源安全释放
            let _ = h.join();
        }
    }

    /// 更新考试配置。
    ///
    /// 对应 TS 的 `updateConfig()` 方法。
    /// 返回 false 表示配置验证失败或时间重叠。
    pub fn update_config(&self, new_config: ExamConfig) -> bool {
        let mut inner = self.inner.lock().unwrap();

        // 验证配置
        if !validate_exam_config(&new_config) {
            inner.state.error = Some("配置验证失败".to_string());
            inner.state.loaded = false;
            inner.tasks.clear();
            return false;
        }

        // 检查时间重叠
        if crate::core::parser::has_exam_time_overlap(&new_config) {
            inner.state.error = Some("考试时间存在重叠".to_string());
            inner.state.loaded = false;
            inner.tasks.clear();
            return false;
        }

        inner.config = Some(new_config.clone());
        inner.state.error = None;
        inner.state.loaded = true;

        // 更新当前考试
        Self::update_current_exam_inner(&mut inner);

        // 创建任务
        Self::create_tasks_for_config(&mut inner);

        true
    }

    /// 获取当前考试信息。
    ///
    /// 对应 TS 的 `currentExam` computed。
    pub fn current_exam(&self) -> Option<ExamInfo> {
        let inner = self.inner.lock().unwrap();
        let config = inner.config.as_ref()?;
        let sorted = get_sorted_exam_infos(config);
        let idx = inner.state.current_exam_index;
        if idx < sorted.len() {
            Some(sorted[idx].clone())
        } else {
            None
        }
    }

    /// 获取当前状态。
    pub fn state(&self) -> PlayerState {
        self.inner.lock().unwrap().state.clone()
    }

    /// 获取当前时间（毫秒时间戳）。
    pub fn current_time_ms(&self) -> i64 {
        self.inner.lock().unwrap().current_time_ms
    }

    /// 设置可选的 NTP 时间源。
    ///
    /// 替换内部 time_fn，并立即用新的时间源更新 current_time_ms。
    pub fn set_time_fn(&self, time_fn: Box<dyn Fn() -> i64 + Send + 'static>) {
        let mut inner = self.inner.lock().unwrap();
        inner.current_time_ms = time_fn();
        inner.time_fn = time_fn;
    }

    /// 获取当前考试配置。
    pub fn config(&self) -> Option<ExamConfig> {
        self.inner.lock().unwrap().config.clone()
    }

    /// 切换考试到指定索引。
    ///
    /// 对应 TS 的 `switchToExam()` 方法。
    pub fn switch_to_exam(&self, index: usize) -> bool {
        let mut inner = self.inner.lock().unwrap();

        let exam_infos_len = match inner.config.as_ref() {
            Some(c) => c.exam_infos.len(),
            None => return false,
        };

        if index >= exam_infos_len {
            return false;
        }

        let old_index = inner.state.current_exam_index;
        inner.state.current_exam_index = index;

        // 触发切换回调
        if old_index != index {
            // 需要先克隆 sorted，因为接下来要借用 inner.config（不可变）和 self.on_exam_switch
            let sorted = match inner.config.as_ref() {
                Some(c) => get_sorted_exam_infos(c),
                None => return true,
            };
            drop(inner); // 释放 inner 锁

            if let Some(ref cb) = *self.on_exam_switch.lock().unwrap() {
                if old_index < sorted.len() && index < sorted.len() {
                    cb(&sorted[old_index], &sorted[index]);
                }
            }
        }

        true
    }

    /// 获取当前考试状态。
    ///
    /// 对应 TS 的 `ExamDataProcessor.getExamStatus`。
    pub fn exam_status(&self) -> ExamStatusInfo {
        let inner = self.inner.lock().unwrap();
        let exam = match Self::get_current_exam_inner(&inner) {
            Some(e) => e,
            None => {
                return ExamStatusInfo {
                    status: ExamStatus::Unknown,
                    message: "暂无考试安排".to_string(),
                    time_remaining_ms: None,
                    progress: None,
                };
            }
        };

        let start_ms = exam.start_ts;
        let end_ms = exam.end_ts;
        let now = inner.current_time_ms;

        if now < start_ms {
            let remaining = start_ms - now;
            ExamStatusInfo {
                status: ExamStatus::Pending,
                message: format!("未开始 · 开始时间 {}", exam.start),
                time_remaining_ms: Some(remaining),
                progress: None,
            }
        } else if now >= start_ms && now < end_ms {
            let remaining = end_ms - now;
            let total = end_ms - start_ms;
            let elapsed = now - start_ms;
            let progress = if total > 0 {
                (elapsed as f64 / total as f64).min(1.0)
            } else {
                0.0
            };

            ExamStatusInfo {
                status: ExamStatus::InProgress,
                message: format!("将于 {} 结束", exam.end),
                time_remaining_ms: Some(remaining),
                progress: Some(progress),
            }
        } else {
            ExamStatusInfo {
                status: ExamStatus::Completed,
                message: "已结束".to_string(),
                time_remaining_ms: None,
                progress: None,
            }
        }
    }

    /// 获取剩余时间显示文本。
    ///
    /// 对应 TS 的 `ExamDataProcessor.getRemainingTimeText`。
    pub fn remaining_time_text(&self) -> String {
        let inner = self.inner.lock().unwrap();
        let exam = match Self::get_current_exam_inner(&inner) {
            Some(e) => e,
            None => return "00:00".to_string(),
        };

        let start_ms = exam.start_ts;
        let end_ms = exam.end_ts;
        let now = inner.current_time_ms;

        if now < start_ms {
            let diff = (start_ms - now).max(0);
            Self::format_duration(diff)
        } else if now >= start_ms && now < end_ms {
            let diff = (end_ms - now).max(0);
            Self::format_duration(diff)
        } else {
            "00:00".to_string()
        }
    }

    /// 获取当前考试剩余毫秒数（仅进行中考试有效）。
    pub fn remaining_time_ms(&self) -> Option<i64> {
        let inner = self.inner.lock().unwrap();
        let exam = Self::get_current_exam_inner(&inner)?;

        let start_ms = exam.start_ts;
        let end_ms = exam.end_ts;
        let now = inner.current_time_ms;

        if now >= start_ms && now < end_ms {
            Some((end_ms - now).max(0))
        } else {
            None
        }
    }

    /// 获取当前考试的提醒时间（分钟）。
    pub fn current_exam_alert_time(&self) -> i32 {
        let inner = self.inner.lock().unwrap();
        match Self::get_current_exam_inner(&inner) {
            Some(e) => e.alert_time,
            None => 0,
        }
    }

    /// 获取考试时间范围文本。
    ///
    /// 对应 TS 的 `ExamDataProcessor.getExamTimeRange`。
    pub fn exam_time_range(&self) -> String {
        let exam = match self.current_exam() {
            Some(e) => e,
            None => return "暂无安排".to_string(),
        };

        let start = match parse_date_time(&exam.start) {
            Some(d) => d,
            None => return "暂无安排".to_string(),
        };
        let end = match parse_date_time(&exam.end) {
            Some(d) => d,
            None => return "暂无安排".to_string(),
        };

        format!("{} - {}", start.format("%H:%M"), end.format("%H:%M"))
    }

    /// 获取排序后的考试信息列表。
    #[allow(dead_code)]
    pub fn sorted_exam_infos(&self) -> Vec<ExamInfo> {
        let inner = self.inner.lock().unwrap();
        match inner.config.as_ref() {
            Some(c) => get_sorted_exam_infos(c),
            None => Vec::new(),
        }
    }

    /// 获取当前考试名称。
    pub fn current_exam_name(&self) -> String {
        self.current_exam()
            .map(|e| e.name)
            .unwrap_or_else(|| "暂无考试".to_string())
    }

    /// 获取任务数量。
    #[allow(dead_code)]
    pub fn task_count(&self) -> usize {
        let inner = self.inner.lock().unwrap();
        inner.tasks.iter().filter(|t| !t.executed).count()
    }

    // ==================== 内部方法 ====================

    /// 从内部状态中提取当前考试信息，避免多处重复代码。
    fn get_current_exam_inner(inner: &PlayerInner) -> Option<ExamInfo> {
        let config = inner.config.as_ref()?;
        let sorted = get_sorted_exam_infos(config);
        let idx = inner.state.current_exam_index;
        if idx < sorted.len() {
            Some(sorted[idx].clone())
        } else {
            None
        }
    }

    /// 更新当前考试索引（内部方法，需要在持有锁时调用）。
    /// 使用独立的 found_in_progress 标志避免歧义，取代原来依赖 target_index == 0 的判断。
    fn update_current_exam_inner(inner: &mut PlayerInner) {
        let config = match inner.config.as_ref() {
            Some(c) => c,
            None => return,
        };

        if config.exam_infos.is_empty() {
            return;
        }

        let sorted = get_sorted_exam_infos(config);
        let now = inner.current_time_ms;

        let mut target_index = 0usize;
        let mut found_in_progress = false;

        // 第一步：寻找正在进行的考试
        for (i, exam) in sorted.iter().enumerate() {
            if now >= exam.start_ts && now < exam.end_ts {
                target_index = i;
                found_in_progress = true;
                break;
            }
        }

        if !found_in_progress {
            // 第二步：找最近的未开始考试
            for (i, exam) in sorted.iter().enumerate() {
                if now < exam.start_ts {
                    target_index = i;
                    break;
                }
            }

            // 如果所有考试都已结束，显示最后一场
            let all_completed = sorted.iter().all(|exam| now >= exam.end_ts);

            if all_completed && !sorted.is_empty() {
                target_index = sorted.len() - 1;
            }
        }

        // 检查旧考试是否已结束，如果是则跳到下一个
        let old_index = inner.state.current_exam_index;
        if old_index < sorted.len() {
            let old_exam = &sorted[old_index];
            if now >= old_exam.end_ts && old_index < sorted.len() - 1 {
                target_index = target_index.max(old_index + 1);
            }
        }

        inner.state.current_exam_index = target_index;
    }

    /// 为配置创建任务（内部方法，需要在持有锁时调用）。
    fn create_tasks_for_config(inner: &mut PlayerInner) {
        inner.tasks.clear();

        let config = match inner.config.as_ref() {
            Some(c) => c,
            None => return,
        };

        let now = inner.current_time_ms;

        for exam in &config.exam_infos {
            let start_ms = exam.start_ts;
            let end_ms = exam.end_ts;

            // 考试开始任务
            inner.tasks.push(Task {
                id: format!("exam-start-{}-{}", exam.name, start_ms),
                execute_time_ms: start_ms,
                task_type: TaskType::Start,
                exam_info: exam.clone(),
                alert_time: 0,
                executed: start_ms <= now,
            });

            // 考试结束任务
            inner.tasks.push(Task {
                id: format!("exam-end-{}-{}", exam.name, end_ms),
                execute_time_ms: end_ms,
                task_type: TaskType::End,
                exam_info: exam.clone(),
                alert_time: 0,
                executed: end_ms <= now,
            });

            // 考试提醒任务
            if exam.alert_time > 0 {
                let alert_ms = end_ms - (exam.alert_time as i64) * 60 * 1000;
                inner.tasks.push(Task {
                    id: format!("exam-alert-{}-{}", exam.name, alert_ms),
                    execute_time_ms: alert_ms,
                    task_type: TaskType::Alert,
                    exam_info: exam.clone(),
                    alert_time: exam.alert_time,
                    executed: alert_ms <= now,
                });
            }
        }
    }

    /// 格式化毫秒时长为 H:MM:SS 或 MM:SS。
    ///
    /// 对应 TS 的 `ExamDataProcessor.formatDuration`。
    fn format_duration(ms: i64) -> String {
        let total_seconds = (ms / 1000).max(0);
        let hours = total_seconds / 3600;
        let minutes = (total_seconds % 3600) / 60;
        let seconds = total_seconds % 60;

        if hours > 0 {
            format!("{}:{:02}:{:02}", hours, minutes, seconds)
        } else {
            format!("{:02}:{:02}", minutes, seconds)
        }
    }
}

impl Drop for PlayerCore {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::types::ExamConfig;
    use crate::core::types::ExamInfo;
    use crate::core::utils::parse_date_time;

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

    fn make_time_fn(timestamp_ms: i64) -> Box<dyn Fn() -> i64 + Send + 'static> {
        Box::new(move || timestamp_ms)
    }

    #[test]
    fn test_player_creation() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config), make_time_fn(ts));

        let state = player.state();
        assert!(!state.loaded);
        assert!(state.error.is_none());
    }

    #[test]
    fn test_update_config() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(ts));

        let result = player.update_config(config);
        assert!(result);

        let state = player.state();
        assert!(state.loaded);
        assert!(state.error.is_none());
    }

    #[test]
    fn test_update_config_with_overlap() {
        let mut config = ExamConfig {
            exam_name: "重叠考试".to_string(),
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

        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(ts));

        let result = player.update_config(config);
        assert!(!result);

        let state = player.state();
        assert!(!state.loaded);
        assert!(state.error.is_some());
    }

    #[test]
    fn test_current_exam_before_start() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        // 在考试开始前，应该显示第一场考试
        let exam = player.current_exam();
        assert!(exam.is_some());
        assert_eq!(exam.unwrap().name, "语文");
    }

    #[test]
    fn test_current_exam_in_progress() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 09:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        // 在语文考试进行中，应该显示语文
        let exam = player.current_exam();
        assert!(exam.is_some());
        assert_eq!(exam.unwrap().name, "语文");
    }

    #[test]
    fn test_current_exam_between() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 12:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        // 在语文结束后、数学开始前，应该显示数学
        let exam = player.current_exam();
        assert!(exam.is_some());
        assert_eq!(exam.unwrap().name, "数学");
    }

    #[test]
    fn test_current_exam_all_completed() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 18:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        // 所有考试结束后，显示最后一场
        let exam = player.current_exam();
        assert!(exam.is_some());
        assert_eq!(exam.unwrap().name, "数学");
    }

    #[test]
    fn test_exam_status_pending() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let status = player.exam_status();
        assert_eq!(status.status, ExamStatus::Pending);
        assert!(status.message.contains("未开始"));
    }

    #[test]
    fn test_exam_status_in_progress() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 09:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let status = player.exam_status();
        assert_eq!(status.status, ExamStatus::InProgress);
        assert!(status.progress.is_some());
    }

    #[test]
    fn test_exam_status_completed() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 18:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let status = player.exam_status();
        assert_eq!(status.status, ExamStatus::Completed);
    }

    #[test]
    fn test_switch_to_exam() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        assert!(player.switch_to_exam(1));
        let state = player.state();
        assert_eq!(state.current_exam_index, 1);

        let exam = player.current_exam();
        assert_eq!(exam.unwrap().name, "数学");
    }

    #[test]
    fn test_switch_to_exam_invalid_index() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config), make_time_fn(ts));

        assert!(!player.switch_to_exam(99));
    }

    #[test]
    fn test_remaining_time_text() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 09:30:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let text = player.remaining_time_text();
        // 语文考试 08:00-10:00，当前 09:30，剩余约30分钟
        assert!(!text.is_empty());
        assert!(text.contains(':'));
    }

    #[test]
    fn test_exam_time_range() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let range = player.exam_time_range();
        assert!(range.contains(" - "));
    }

    #[test]
    fn test_current_exam_name() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        assert_eq!(player.current_exam_name(), "语文");
    }

    #[test]
    fn test_current_exam_name_no_config() {
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(ts));

        assert_eq!(player.current_exam_name(), "暂无考试");
    }

    #[test]
    fn test_start_stop() {
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config), make_time_fn(ts));

        player.start();
        // 短暂运行后停止
        std::thread::sleep(Duration::from_millis(100));
        player.stop();
    }

    #[test]
    fn test_format_duration() {
        // 测试 format_duration 通过 remaining_time_text
        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 09:59:30")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let text = player.remaining_time_text();
        // 剩余约30秒，应显示 "00:30"
        assert!(text.contains(':'));
    }

    #[test]
    fn test_set_time_fn_updates_current_time() {
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(ts));
        assert_eq!(player.current_time_ms(), ts);

        let new_ts = parse_date_time("2025-06-15 20:00:00")
            .unwrap()
            .timestamp_millis();
        player.set_time_fn(make_time_fn(new_ts));
        assert_eq!(player.current_time_ms(), new_ts);
    }

    #[test]
    fn test_task_queue_triggers_callbacks() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        let config = make_test_config();
        let before = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(before));
        player.update_config(config);

        // 2 场考试，每场 start/end/alert 各一个任务
        assert_eq!(player.task_count(), 6);

        let start_count = Arc::new(AtomicUsize::new(0));
        let alert_count = Arc::new(AtomicUsize::new(0));
        let end_count = Arc::new(AtomicUsize::new(0));

        let s = start_count.clone();
        let a = alert_count.clone();
        let e = end_count.clone();

        player.on_exam_start(move |_| {
            s.fetch_add(1, Ordering::SeqCst);
        });
        player.on_exam_alert(move |_, _| {
            a.fetch_add(1, Ordering::SeqCst);
        });
        player.on_exam_end(move |_| {
            e.fetch_add(1, Ordering::SeqCst);
        });

        player.start();

        // 将时间跳到所有考试结束之后
        let after = parse_date_time("2025-06-15 18:00:00")
            .unwrap()
            .timestamp_millis();
        player.set_time_fn(make_time_fn(after));

        // 轮询等待回调被触发，最多 5 秒
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while std::time::Instant::now() < deadline {
            if start_count.load(Ordering::SeqCst) == 2
                && alert_count.load(Ordering::SeqCst) == 2
                && end_count.load(Ordering::SeqCst) == 2
            {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        player.stop();

        assert_eq!(start_count.load(Ordering::SeqCst), 2);
        assert_eq!(alert_count.load(Ordering::SeqCst), 2);
        assert_eq!(end_count.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn test_manual_exam_switch_callback() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let config = make_test_config();
        let ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(Some(config.clone()), make_time_fn(ts));
        player.update_config(config);

        let switched = Arc::new(AtomicBool::new(false));
        let s = switched.clone();
        player.on_exam_switch(move |old, new| {
            assert_eq!(old.name, "语文");
            assert_eq!(new.name, "数学");
            s.store(true, Ordering::SeqCst);
        });

        assert!(player.switch_to_exam(1));
        assert!(switched.load(Ordering::SeqCst));
    }

    #[test]
    fn test_set_time_fn_with_ntp_offset() {
        let local_ts = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let offset_ms = 5 * 60 * 1000; // +5 分钟偏移
        let player = PlayerCore::new(None, make_time_fn(local_ts));
        assert_eq!(player.current_time_ms(), local_ts);

        // 模拟 NTP 校正：时间函数返回本地时间 + 偏移
        let ntp_ts = local_ts + offset_ms;
        player.set_time_fn(make_time_fn(ntp_ts));
        assert_eq!(player.current_time_ms(), ntp_ts);

        // 验证校正后加载配置能正确判断考试状态
        let config = make_test_config();
        player.update_config(config);
        // 校正后时间为 07:05，仍早于第一场考试开始时间 08:00
        let status = player.exam_status();
        assert_eq!(status.status, ExamStatus::Pending);
    }

    #[test]
    fn test_alert_task_timing() {
        let mut config = ExamConfig {
            exam_name: "提醒测试".to_string(),
            message: "".to_string(),
            exam_infos: vec![ExamInfo {
                name: "语文".to_string(),
                start: "2025-06-15 08:00:00".to_string(),
                end: "2025-06-15 10:00:00".to_string(),
                alert_time: 15,
                materials: None,
                start_ts: 0,
                end_ts: 0,
            }],
        };
        config.cache_timestamps();

        let before_alert = parse_date_time("2025-06-15 09:40:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(before_alert));
        player.update_config(config);

        // 当前时间 09:40，开始任务已执行并被移除；
        // 任务队列中应包含未执行的 alert（09:45）与 end（10:00）两个任务
        assert_eq!(player.task_count(), 2);

        // 将时间拨到提醒之后、结束之前
        let after_alert = parse_date_time("2025-06-15 09:50:00")
            .unwrap()
            .timestamp_millis();
        player.set_time_fn(make_time_fn(after_alert));

        let triggered = Arc::new(AtomicBool::new(false));
        let t = triggered.clone();
        player.on_exam_alert(move |exam, alert_time| {
            assert_eq!(exam.name, "语文");
            assert_eq!(alert_time, 15);
            t.store(true, Ordering::SeqCst);
        });

        player.start();
        let deadline = std::time::Instant::now() + Duration::from_secs(3);
        while std::time::Instant::now() < deadline {
            if triggered.load(Ordering::SeqCst) {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        player.stop();

        assert!(triggered.load(Ordering::SeqCst));
        // alert 任务执行后应被移除，仅剩 end 任务，避免重复触发
        assert_eq!(player.task_count(), 1);
    }

    #[test]
    fn test_task_removed_after_execution_prevents_duplicates() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        let mut config = ExamConfig {
            exam_name: "单场考试".to_string(),
            message: "".to_string(),
            exam_infos: vec![ExamInfo {
                name: "语文".to_string(),
                start: "2025-06-15 08:00:00".to_string(),
                end: "2025-06-15 10:00:00".to_string(),
                alert_time: 0,
                materials: None,
                start_ts: 0,
                end_ts: 0,
            }],
        };
        config.cache_timestamps();

        let before = parse_date_time("2025-06-15 07:00:00")
            .unwrap()
            .timestamp_millis();
        let player = PlayerCore::new(None, make_time_fn(before));
        player.update_config(config);

        let start_count = Arc::new(AtomicUsize::new(0));
        let s = start_count.clone();
        player.on_exam_start(move |_| {
            s.fetch_add(1, Ordering::SeqCst);
        });

        player.start();

        // 将时间拨到考试结束后
        let after = parse_date_time("2025-06-15 11:00:00")
            .unwrap()
            .timestamp_millis();
        player.set_time_fn(make_time_fn(after));

        // 等待任务执行
        let deadline = std::time::Instant::now() + Duration::from_secs(3);
        while std::time::Instant::now() < deadline {
            if player.task_count() == 0 {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        // 再次将时间拨回考试期间，任务已移除不应再次触发
        let during = parse_date_time("2025-06-15 09:00:00")
            .unwrap()
            .timestamp_millis();
        player.set_time_fn(make_time_fn(during));
        std::thread::sleep(Duration::from_millis(200));

        player.stop();

        assert_eq!(start_count.load(Ordering::SeqCst), 1);
        assert_eq!(player.task_count(), 0);
    }
}
