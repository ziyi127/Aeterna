use qmetaobject::*;
use std::sync::Mutex;

/// QML bridge for local configuration sharing and incoming approval.
#[derive(QObject, Default)]
pub struct ShareManager {
    base: qt_base_class!(trait QObject),
    active_config_json: qt_property!(QString; READ active_config_json NOTIFY active_config_json_changed),
    pending_shares_json: qt_property!(QString; READ pending_shares_json NOTIFY pending_shares_json_changed),
    last_status: qt_property!(QString; READ last_status NOTIFY last_status_changed),

    refresh: qt_method!(fn(&self)),
    set_local_config: qt_method!(fn(&self, json: QString) -> bool),
    share_current_config: qt_method!(fn(&self)),
    share_current_config_to: qt_method!(fn(&self, device_id: QString) -> bool),
    approve_share: qt_method!(fn(&self, share_id: QString) -> QString),
    reject_share: qt_method!(fn(&self, share_id: QString) -> bool),

    active_config_json_changed: qt_signal!(),
    pending_shares_json_changed: qt_signal!(),
    last_status_changed: qt_signal!(),

    _active_config_json: Mutex<String>,
    _pending_shares_json: Mutex<String>,
    _last_status: Mutex<String>,
}

impl ShareManager {
    fn active_config_json(&self) -> QString {
        QString::from(self._active_config_json.lock().unwrap().clone())
    }

    fn pending_shares_json(&self) -> QString {
        QString::from(self._pending_shares_json.lock().unwrap().clone())
    }

    fn last_status(&self) -> QString {
        QString::from(self._last_status.lock().unwrap().clone())
    }

    fn refresh(&self) {
        let Some(runtime) = crate::services::share_runtime::global() else {
            return;
        };
        let active = runtime.active_config_json().unwrap_or_default();
        let pending = runtime.pending_summary_json();
        let status = runtime.last_status();
        if *self._active_config_json.lock().unwrap() != active {
            *self._active_config_json.lock().unwrap() = active;
            self.active_config_json_changed();
        }
        if *self._pending_shares_json.lock().unwrap() != pending {
            *self._pending_shares_json.lock().unwrap() = pending;
            self.pending_shares_json_changed();
        }
        if *self._last_status.lock().unwrap() != status {
            *self._last_status.lock().unwrap() = status;
            self.last_status_changed();
        }
    }

    fn set_local_config(&self, json: QString) -> bool {
        let Some(runtime) = crate::services::share_runtime::global() else {
            return false;
        };
        let success = runtime.set_local_config(&json.to_string(), true).is_ok();
        self.refresh();
        success
    }

    fn share_current_config(&self) {
        if let Some(runtime) = crate::services::share_runtime::global() {
            runtime.share_active_config();
        }
        self.refresh();
    }

    fn share_current_config_to(&self, device_id: QString) -> bool {
        let result = crate::services::share_runtime::global()
            .map(|runtime| {
                runtime
                    .share_active_config_to(&device_id.to_string())
                    .is_ok()
            })
            .unwrap_or(false);
        self.refresh();
        result
    }

    fn approve_share(&self, share_id: QString) -> QString {
        let result = crate::services::share_runtime::global()
            .and_then(|runtime| runtime.approve(&share_id.to_string()).ok().flatten())
            .unwrap_or_default();
        self.refresh();
        QString::from(result)
    }

    fn reject_share(&self, share_id: QString) -> bool {
        let result = crate::services::share_runtime::global()
            .map(|runtime| runtime.reject(&share_id.to_string()))
            .unwrap_or(false);
        self.refresh();
        result
    }
}
