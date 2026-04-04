#include "flutter_window.h"

#include <filesystem>
#include <fstream>
#include <optional>

#include <memory>
#include <variant>

#include <ShellScalingApi.h>
#include <Windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow* FlutterWindow::keyboard_hook_owner_ = nullptr;

namespace {

using std::filesystem::path;

constexpr wchar_t kTabletPenServiceProperty[] =
  L"MicrosoftTabletPenServiceProperty";
constexpr wchar_t kPresentationRootName[] = L"AeternaPresentation";
constexpr wchar_t kPresentationMarkerFileName[] =
    L"presentation_watchdog_state.txt";

constexpr ULONG_PTR kTabletDisablePressAndHold = 0x00000001;
constexpr ULONG_PTR kTabletDisablePenTapFeedback = 0x00000008;
constexpr ULONG_PTR kTabletDisablePenBarrelFeedback = 0x00000010;
constexpr ULONG_PTR kTabletDisableTouchUiForceOn = 0x00000100;
constexpr ULONG_PTR kTabletDisableTouchUiForceOff = 0x00000200;
constexpr ULONG_PTR kTabletDisableTouchSwitch = 0x00008000;
constexpr ULONG_PTR kTabletDisableFlicks = 0x00010000;
constexpr ULONG_PTR kTabletDisableSmoothScrolling = 0x00080000;
constexpr ULONG_PTR kTabletDisableFlickFallbackKeys = 0x00100000;

constexpr ULONG_PTR kPresentationTabletGestureMask =
  kTabletDisablePressAndHold | kTabletDisablePenTapFeedback |
  kTabletDisablePenBarrelFeedback | kTabletDisableTouchUiForceOn |
  kTabletDisableTouchUiForceOff | kTabletDisableTouchSwitch |
  kTabletDisableFlicks | kTabletDisableSmoothScrolling |
  kTabletDisableFlickFallbackKeys;

path GetPresentationRootPath() {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = ::GetTempPathW(MAX_PATH, buffer);
  if (length == 0 || length >= MAX_PATH) {
    return {};
  }
  return path(buffer) / kPresentationRootName;
}

path GetPresentationMarkerPath() {
  return GetPresentationRootPath() / kPresentationMarkerFileName;
}

bool WritePresentationMarker(const std::string& state) {
  const path marker_path = GetPresentationMarkerPath();
  std::error_code error;
  std::filesystem::create_directories(marker_path.parent_path(), error);
  std::ofstream output(marker_path, std::ios::binary | std::ios::trunc);
  if (!output.is_open()) {
    return false;
  }
  output << "state=" << state << "\n";
  output << "parentPid=" << ::GetCurrentProcessId() << "\n";
  output << "resumeRoute=/monitor\n";
  return output.good();
}

bool LaunchPresentationWatchdog() {
  wchar_t module_buffer[MAX_PATH] = {};
  const DWORD module_length = ::GetModuleFileNameW(nullptr, module_buffer, MAX_PATH);
  if (module_length == 0 || module_length >= MAX_PATH) {
    return false;
  }

  const path module_path(module_buffer);
  const std::wstring command_line =
      L"--presentation-watchdog --watch-parent-pid=" +
      std::to_wstring(::GetCurrentProcessId());

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::wstring mutable_command_line = command_line;
  const BOOL started = ::CreateProcessW(
      module_path.c_str(),
      mutable_command_line.data(),
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      module_path.parent_path().c_str(),
      &startup_info,
      &process_info);
  if (!started) {
    return false;
  }

  ::CloseHandle(process_info.hProcess);
  ::CloseHandle(process_info.hThread);
  return true;
}

}  // namespace

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
        if (call.method_name() == "setPresentationInputLock") {
          bool enabled = false;
          if (call.arguments() != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
            const auto& args =
                std::get<flutter::EncodableMap>(*call.arguments());
            const auto enabled_it =
                args.find(flutter::EncodableValue("enabled"));
            if (enabled_it != args.end() &&
                std::holds_alternative<bool>(enabled_it->second)) {
              enabled = std::get<bool>(enabled_it->second);
            }
          }
          result->Success(
              flutter::EncodableValue(SetPresentationInputLock(enabled)));
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
  SetPresentationInputLock(false);

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
#ifdef WM_TABLET_QUERYSYSTEMGESTURESTATUS
    case WM_TABLET_QUERYSYSTEMGESTURESTATUS:
      if (presentation_input_lock_enabled_) {
        return static_cast<LRESULT>(kPresentationTabletGestureMask);
      }
      break;
#endif
    case WM_TOUCH:
    case WM_GESTURE:
    case WM_GESTURENOTIFY:
    case WM_POINTERDOWN:
    case WM_POINTERUP:
    case WM_POINTERUPDATE:
      if (presentation_input_lock_enabled_) {
        return 0;
      }
      break;
    case WM_SYSCOMMAND:
      if (presentation_input_lock_enabled_) {
        const UINT command = static_cast<UINT>(wparam & 0xFFF0);
        if (command == SC_TASKLIST || command == SC_KEYMENU ||
            command == SC_HOTKEY || command == SC_SCREENSAVE ||
            command == SC_MONITORPOWER) {
          return 0;
        }
      }
      break;
    case WM_SYSKEYDOWN:
    case WM_KEYDOWN:
      if (presentation_input_lock_enabled_) {
        const bool alt_pressed = (GetKeyState(VK_MENU) & 0x8000) != 0;
        const bool ctrl_pressed = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool win_pressed = (GetKeyState(VK_LWIN) & 0x8000) != 0 ||
                                 (GetKeyState(VK_RWIN) & 0x8000) != 0;
        const UINT key = static_cast<UINT>(wparam);
        const bool blocked =
            key == VK_LWIN || key == VK_RWIN ||
            (alt_pressed &&
             (key == VK_TAB || key == VK_ESCAPE || key == VK_F4 ||
              key == VK_SPACE)) ||
            (ctrl_pressed && key == VK_ESCAPE) ||
            (win_pressed && key != VK_LWIN && key != VK_RWIN);
        if (blocked) {
          return 0;
        }
      }
      break;
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

bool FlutterWindow::SetPresentationInputLock(bool enabled) {
  if (enabled == presentation_input_lock_enabled_) {
    if (enabled && !presentation_watchdog_enabled_) {
      StartPresentationWatchdog();
    }
    return true;
  }

  if (enabled) {
    if (!InstallKeyboardHook()) {
      return false;
    }
    SetSystemGestureSuppression(true);
    StartPresentationWatchdog();
    presentation_input_lock_enabled_ = true;
    return true;
  }

  presentation_input_lock_enabled_ = false;
  StopPresentationWatchdog();
  SetSystemGestureSuppression(false);
  UninstallKeyboardHook();
  return true;
}

bool FlutterWindow::StartPresentationWatchdog() {
  if (presentation_watchdog_enabled_) {
    return true;
  }

  // Best effort: the watchdog should not block the UI from entering presentation mode.
  if (!WritePresentationMarker("active")) {
    return false;
  }

  presentation_watchdog_enabled_ = LaunchPresentationWatchdog();
  if (!presentation_watchdog_enabled_) {
    // Clear the marker so a failed launch does not leave a stale active session behind.
    WritePresentationMarker("inactive");
  }
  return presentation_watchdog_enabled_;
}

void FlutterWindow::StopPresentationWatchdog() {
  if (!presentation_watchdog_enabled_) {
    return;
  }

  // Mark the session inactive so the helper exits without relaunching the app.
  WritePresentationMarker("inactive");
  presentation_watchdog_enabled_ = false;
}

bool FlutterWindow::InstallKeyboardHook() {
  if (keyboard_hook_ != nullptr) {
    return true;
  }

  keyboard_hook_owner_ = this;
  keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardHookProc,
                                     GetModuleHandle(nullptr), 0);
  if (keyboard_hook_ == nullptr) {
    keyboard_hook_owner_ = nullptr;
    return false;
  }
  return true;
}

void FlutterWindow::UninstallKeyboardHook() {
  if (keyboard_hook_ != nullptr) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  if (keyboard_hook_owner_ == this) {
    keyboard_hook_owner_ = nullptr;
  }
}

void FlutterWindow::SetSystemGestureSuppression(bool enabled) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  if (enabled) {
    SetPropW(hwnd, kTabletPenServiceProperty,
             reinterpret_cast<HANDLE>(kPresentationTabletGestureMask));
    system_gesture_suppression_enabled_ = true;
    return;
  }

  if (system_gesture_suppression_enabled_) {
    RemovePropW(hwnd, kTabletPenServiceProperty);
    system_gesture_suppression_enabled_ = false;
  }
}

bool FlutterWindow::ShouldBlockKeyEvent(const KBDLLHOOKSTRUCT& info,
                                        WPARAM message) const {
  if (!presentation_input_lock_enabled_) {
    return false;
  }
  if (message != WM_KEYDOWN && message != WM_SYSKEYDOWN) {
    return false;
  }

  const bool alt_pressed = (info.flags & LLKHF_ALTDOWN) != 0;
  const bool ctrl_pressed = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
  const bool win_pressed = (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                           (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
  const DWORD key = info.vkCode;

  if (key == VK_LWIN || key == VK_RWIN) {
    return true;
  }

  if (alt_pressed &&
      (key == VK_TAB || key == VK_ESCAPE || key == VK_F4 || key == VK_SPACE)) {
    return true;
  }

  if (ctrl_pressed && key == VK_ESCAPE) {
    return true;
  }

  if (win_pressed && key != VK_LWIN && key != VK_RWIN) {
    return true;
  }

  return false;
}

LRESULT CALLBACK FlutterWindow::KeyboardHookProc(int code, WPARAM wparam,
                                                 LPARAM lparam) {
  if (code == HC_ACTION && keyboard_hook_owner_ != nullptr &&
      lparam != 0) {
    const auto* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    if (keyboard_hook_owner_->ShouldBlockKeyEvent(*info, wparam)) {
      return 1;
    }
  }

  return CallNextHookEx(nullptr, code, wparam, lparam);
}
