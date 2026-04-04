#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/method_channel.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Window security channel (UIAccess detection on Windows).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_security_channel_;

  bool presentation_input_lock_enabled_ = false;
  bool system_gesture_suppression_enabled_ = false;
  bool presentation_watchdog_enabled_ = false;
  HHOOK keyboard_hook_ = nullptr;

  static FlutterWindow* keyboard_hook_owner_;
  static LRESULT CALLBACK KeyboardHookProc(int code, WPARAM wparam,
                                           LPARAM lparam);

  bool IsUiAccessEnabled() const;
  double GetMonitorDpi() const;
  bool SetPresentationInputLock(bool enabled);
  bool InstallKeyboardHook();
  void UninstallKeyboardHook();
  void SetSystemGestureSuppression(bool enabled);
  bool StartPresentationWatchdog();
  void StopPresentationWatchdog();
  bool ShouldBlockKeyEvent(const KBDLLHOOKSTRUCT& info,
                           WPARAM message) const;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
