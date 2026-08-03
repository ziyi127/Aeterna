use qmetaobject::*;
use std::sync::Mutex;

/// QML adapter for the process-wide mDNS discovery service.
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
        QString::from(self._devices_json.lock().unwrap().clone())
    }

    fn device_count(&self) -> i32 {
        serde_json::from_str::<Vec<serde_json::Value>>(&self._devices_json.lock().unwrap())
            .map(|devices| devices.len() as i32)
            .unwrap_or(0)
    }

    fn start_scan(&self) {
        *self._scanning.lock().unwrap() = true;
        self.scanning_changed();
        self.refresh_devices();
    }

    fn stop_scan(&self) {
        *self._scanning.lock().unwrap() = false;
        self.scanning_changed();
    }

    fn refresh_devices(&self) {
        #[cfg(feature = "cast")]
        let devices = crate::services::share_runtime::global()
            .map(|runtime| runtime.cast_service().get_devices())
            .unwrap_or_default()
            .into_iter()
            .map(|device| {
                serde_json::json!({
                    "id": device.id,
                    "name": device.name,
                    "endpoint": format!("{}:{}", device.ip_address, device.port),
                    "type": device.properties.get("type").cloned().unwrap_or_else(|| "player".to_string()),
                    "share_supported": device.supports_config_share(),
                    "status": if device.supports_config_share() { "可分享" } else { "不可分享" },
                    "last_seen_seconds": device.last_seen.elapsed().as_secs(),
                })
            })
            .collect::<Vec<_>>();

        #[cfg(not(feature = "cast"))]
        let devices: Vec<serde_json::Value> = Vec::new();

        *self._devices_json.lock().unwrap() =
            serde_json::to_string(&devices).unwrap_or_else(|_| "[]".to_string());
        self.devices_json_changed();
        self.device_count_changed();
    }
}
