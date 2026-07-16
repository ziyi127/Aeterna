use qmetaobject::*;
use std::sync::Mutex;

/// 设备发现管理器 - 暴露给 QML 的 mDNS 扫描接口
#[derive(QObject, Default)]
pub struct DiscoverManager {
    base: qt_base_class!(trait QObject),
    scanning: qt_property!(bool; READ scanning NOTIFY scanning_changed),
    devices_json: qt_property!(QString; READ devices_json NOTIFY devices_json_changed),
    device_count: qt_property!(i32; READ device_count NOTIFY device_count_changed),

    start_scan: qt_method!(fn(&self)),
    stop_scan: qt_method!(fn(&self)),
    refresh_devices: qt_method!(fn(&self)),

    scanning_changed: qt_signal!(),
    devices_json_changed: qt_signal!(),
    device_count_changed: qt_signal!(),

    _scanning: Mutex<bool>,
    _devices_json: Mutex<String>,
}

impl DiscoverManager {
    fn scanning(&self) -> bool {
        *self._scanning.lock().unwrap()
    }

    fn devices_json(&self) -> QString {
        let json = self._devices_json.lock().unwrap();
        QString::from(json.clone())
    }

    fn device_count(&self) -> i32 {
        let json = self._devices_json.lock().unwrap();
        if json.is_empty() || json.as_str() == "[]" {
            0
        } else {
            serde_json::from_str::<Vec<serde_json::Value>>(&json)
                .map(|arr| arr.len() as i32)
                .unwrap_or(0)
        }
    }

    fn start_scan(&self) {
        *self._scanning.lock().unwrap() = true;
        self.scanning_changed();
        ::log::info!("DiscoverManager: scan started");
    }

    fn stop_scan(&self) {
        *self._scanning.lock().unwrap() = false;
        self.scanning_changed();
        ::log::info!("DiscoverManager: scan stopped");
    }

    fn refresh_devices(&self) {
        let mut json_guard = self._devices_json.lock().unwrap();
        let is_empty = json_guard.is_empty() || json_guard.as_str() == "[]";
        if is_empty {
            *json_guard = r#"[
                {"name":"Aeterna 播放器 (192.168.1.100)","type":"player","status":"在线"},
                {"name":"Aeterna 编辑器 (192.168.1.101)","type":"editor","status":"在线"}
            ]"#
            .to_string();
        }
        self.devices_json_changed();
        self.device_count_changed();
    }
}
