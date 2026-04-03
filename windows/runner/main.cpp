#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>
#include <windows.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

using std::filesystem::path;

const wchar_t kUpdateRootName[] = L"AeternaUpdate";
const wchar_t kManifestFileName[] = L"pending_update.txt";
const wchar_t kSuccessFileName[] = L"upgrade_success.txt";
const wchar_t kHelperFileName[] = L"aeterna_updater_helper.exe";

path GetCurrentModulePath() {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return {};
  }
  return path(buffer);
}

path GetUpdateRootPath() {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = ::GetTempPathW(MAX_PATH, buffer);
  if (length == 0 || length >= MAX_PATH) {
    return {};
  }
  return path(buffer) / kUpdateRootName;
}

path GetManifestPath() {
  return GetUpdateRootPath() / kManifestFileName;
}

path GetSuccessPath() {
  return GetUpdateRootPath() / kSuccessFileName;
}

path GetHelperPath() {
  return GetUpdateRootPath() / kHelperFileName;
}

bool HasArgument(const std::vector<std::string>& args, const std::string& value) {
  for (const auto& arg : args) {
    if (arg == value) {
      return true;
    }
  }
  return false;
}

std::string ArgumentValue(
    const std::vector<std::string>& args,
    const std::string& prefix) {
  for (const auto& arg : args) {
    if (arg.rfind(prefix, 0) == 0) {
      return arg.substr(prefix.size());
    }
  }
  return std::string();
}

std::map<std::string, std::string> ParseKeyValueLines(
    const std::string& content) {
  std::map<std::string, std::string> values;
  size_t offset = 0;
  while (offset < content.size()) {
    const size_t end = content.find_first_of("\r\n", offset);
    std::string line = content.substr(offset, end == std::string::npos ? std::string::npos : end - offset);
    if (!line.empty() && line[0] != '#') {
      const size_t split = line.find('=');
      if (split != std::string::npos && split > 0) {
        values[line.substr(0, split)] = line.substr(split + 1);
      }
    }
    if (end == std::string::npos) {
      break;
    }
    offset = content.find_first_not_of("\r\n", end);
    if (offset == std::string::npos) {
      break;
    }
  }
  return values;
}

bool ReadTextFile(const path& file_path, std::string* out) {
  std::ifstream input(file_path, std::ios::binary);
  if (!input.is_open()) {
    return false;
  }
  std::string content((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  *out = content;
  return true;
}

bool WriteTextFile(const path& file_path, const std::string& content) {
  std::ofstream output(file_path, std::ios::binary | std::ios::trunc);
  if (!output.is_open()) {
    return false;
  }
  output << content;
  return output.good();
}

bool WriteKeyValueFile(
    const path& file_path,
    const std::map<std::string, std::string>& values) {
  std::string content;
  for (const auto& [key, value] : values) {
    content += key + "=" + value + "\n";
  }
  return WriteTextFile(file_path, content);
}

bool WaitForProcess(DWORD process_id) {
  if (process_id == 0) {
    return true;
  }
  HANDLE process = ::OpenProcess(SYNCHRONIZE, FALSE, process_id);
  if (process == nullptr) {
    return true;
  }
  ::WaitForSingleObject(process, 15000);
  ::CloseHandle(process);
  return true;
}

bool RunProcessAndWait(
    const std::wstring& application_name,
    const std::wstring& command_line,
    const std::wstring& working_directory) {
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::wstring mutable_command_line = command_line;
  const BOOL started = ::CreateProcessW(
      application_name.empty() ? nullptr : application_name.c_str(),
      mutable_command_line.data(),
      nullptr,
      nullptr,
      FALSE,
      0,
      nullptr,
      working_directory.empty() ? nullptr : working_directory.c_str(),
      &startup_info,
      &process_info);
  if (!started) {
    return false;
  }
  ::WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  ::GetExitCodeProcess(process_info.hProcess, &exit_code);
  ::CloseHandle(process_info.hProcess);
  ::CloseHandle(process_info.hThread);
  return exit_code == 0;
}

bool CleanDirectory(const path& directory_path) {
  if (!std::filesystem::exists(directory_path)) {
    return std::filesystem::create_directories(directory_path);
  }
  for (const auto& entry : std::filesystem::directory_iterator(directory_path)) {
    std::error_code error;
    std::filesystem::remove_all(entry.path(), error);
  }
  return true;
}

bool ExtractArchiveToTarget(const path& archive_path, const path& target_path) {
  if (!std::filesystem::exists(archive_path)) {
    return false;
  }
  if (!CleanDirectory(target_path)) {
    return false;
  }
  const std::wstring command_line =
      L"tar -xf \"" + archive_path.wstring() + L"\" -C \"" + target_path.wstring() + L"\"";
  return RunProcessAndWait(L"tar", command_line, target_path.wstring());
}

std::wstring CurrentIsoTime() {
  SYSTEMTIME time{};
  ::GetLocalTime(&time);
  wchar_t buffer[64] = {};
  swprintf_s(
      buffer,
      L"%04u-%02u-%02uT%02u:%02u:%02u",
      time.wYear,
      time.wMonth,
      time.wDay,
      time.wHour,
      time.wMinute,
      time.wSecond);
  return buffer;
}

bool WriteSuccessMarker(const std::wstring& version) {
  std::map<std::string, std::string> values;
  values["version"] = Utf8FromUtf16(version.c_str());
  values["installedAtIso"] = Utf8FromUtf16(CurrentIsoTime().c_str());
  return WriteKeyValueFile(GetSuccessPath(), values);
}

bool LaunchAppBinary(const path& executable_path) {
  const HINSTANCE result = ::ShellExecuteW(
      nullptr,
      L"open",
      executable_path.c_str(),
      nullptr,
      executable_path.parent_path().c_str(),
      SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(result) > 32;
}

bool LaunchHelperFromSelf(DWORD parent_process_id) {
  const path current_module_path = GetCurrentModulePath();
  const path helper_path = GetHelperPath();
  if (current_module_path.empty() || helper_path.empty()) {
    return false;
  }

  std::error_code error;
  std::filesystem::create_directories(helper_path.parent_path(), error);
  std::filesystem::copy_file(
      current_module_path,
      helper_path,
      std::filesystem::copy_options::overwrite_existing,
      error);
  if (error) {
    return false;
  }

  const std::wstring command_line =
      L"\"" + helper_path.wstring() + L"\" --install-update --parent-pid=" +
      std::to_wstring(parent_process_id);

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::wstring mutable_command_line = command_line;
  const BOOL started = ::CreateProcessW(
      helper_path.c_str(),
      mutable_command_line.data(),
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      helper_path.parent_path().c_str(),
      &startup_info,
      &process_info);
  if (!started) {
    return false;
  }
  ::CloseHandle(process_info.hProcess);
  ::CloseHandle(process_info.hThread);
  return true;
}

bool RunInstallerMode(const std::vector<std::string>& arguments) {
  const std::string parent_pid_text = ArgumentValue(arguments, "--parent-pid=");
  DWORD parent_pid = 0;
  if (!parent_pid_text.empty()) {
    try {
      parent_pid = static_cast<DWORD>(std::stoul(parent_pid_text));
    } catch (...) {
      parent_pid = 0;
    }
  }
  WaitForProcess(parent_pid);

  const path manifest_path = GetManifestPath();
  std::string manifest_text;
  if (!ReadTextFile(manifest_path, &manifest_text)) {
    ::MessageBoxW(
        nullptr,
        L"未找到更新清单，无法继续安装。",
        L"Aeterna 更新失败",
        MB_ICONERROR | MB_OK);
    return false;
  }

  const auto values = ParseKeyValueLines(manifest_text);
  const std::wstring version = Utf16FromUtf8(values["version"].c_str());
  const std::wstring archive_path = Utf16FromUtf8(values["archivePath"].c_str());
  const std::wstring target_dir = Utf16FromUtf8(values["targetDir"].c_str());
  const std::wstring app_executable_name =
      values.count("appExecutableName")
          ? Utf16FromUtf8(values["appExecutableName"].c_str())
          : L"aeterna.exe";

  if (version.empty() || archive_path.empty() || target_dir.empty()) {
    ::MessageBoxW(
        nullptr,
        L"更新清单内容不完整，无法继续安装。",
        L"Aeterna 更新失败",
        MB_ICONERROR | MB_OK);
    return false;
  }

  if (!ExtractArchiveToTarget(path(archive_path), path(target_dir))) {
    ::MessageBoxW(
        nullptr,
        L"更新包解压失败，请检查系统是否支持 tar/zstd。",
        L"Aeterna 更新失败",
        MB_ICONERROR | MB_OK);
    return false;
  }

  WriteSuccessMarker(version);
  std::error_code delete_error;
  std::filesystem::remove(manifest_path, delete_error);

  const path installed_app_path = path(target_dir) / app_executable_name;
  if (!LaunchAppBinary(installed_app_path)) {
    ::MessageBoxW(
        nullptr,
        L"更新已完成，但重新启动程序失败。",
        L"Aeterna 更新完成",
        MB_ICONWARNING | MB_OK);
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const std::vector<std::string> arguments = GetCommandLineArguments();
  if (HasArgument(arguments, "--install-update")) {
    const bool updated = RunInstallerMode(arguments);
    return updated ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  if (std::filesystem::exists(GetManifestPath())) {
    const DWORD current_process_id = ::GetCurrentProcessId();
    if (LaunchHelperFromSelf(current_process_id)) {
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"aeterna", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
