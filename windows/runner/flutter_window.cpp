#include "flutter_window.h"

#include <optional>

#include <memory>

#include <ShellScalingApi.h>
#include <Windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_security_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "aeterna/window_security",
          &flutter::StandardMethodCodec::GetInstance());
  window_security_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "isUiAccessEnabled") {
          result->Success(flutter::EncodableValue(IsUiAccessEnabled()));
          return;
        }
        if (call.method_name() == "getMonitorDpi") {
          result->Success(flutter::EncodableValue(GetMonitorDpi()));
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_security_channel_) {
    window_security_channel_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::IsUiAccessEnabled() const {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }

  DWORD ui_access = 0;
  DWORD returned_length = 0;
  const BOOL ok = GetTokenInformation(token, TokenUIAccess, &ui_access,
                                      sizeof(ui_access), &returned_length);
  CloseHandle(token);

  if (!ok) {
    return false;
  }
  return ui_access != 0;
}

double FlutterWindow::GetMonitorDpi() const {
  constexpr double kFallbackDpi = 96.0;

  HWND hwnd = const_cast<FlutterWindow*>(this)->GetHandle();
  if (hwnd != nullptr) {
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr) {
      UINT dpi_x = 0;
      UINT dpi_y = 0;
      if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_RAW_DPI, &dpi_x, &dpi_y)) &&
          dpi_x > 0) {
        return static_cast<double>(dpi_x);
      }
      if (SUCCEEDED(
              GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) &&
          dpi_x > 0) {
        return static_cast<double>(dpi_x);
      }
    }
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    return kFallbackDpi;
  }
  const int dpi = GetDeviceCaps(screen_dc, LOGPIXELSX);
  ReleaseDC(nullptr, screen_dc);
  if (dpi <= 0) {
    return kFallbackDpi;
  }
  return static_cast<double>(dpi);
}
