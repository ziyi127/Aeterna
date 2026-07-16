//! UI Access 模块
//!
//! 参考 uiaccess-master 项目的原理实现：
//! - 进程以管理员权限启动
//! - 检测自身是否具有 UIAccess 权限
//! - 若没有，遍历进程列表获取同一 Session 下 winlogon.exe 的令牌
//! - 用该令牌创建具有 TokenUIAccess 的新令牌并重启自身
//! - 新进程获得 UIAccess 后，SetWindowPos(HWND_TOPMOST) 可高于任务管理器等系统窗口
//!
//! 仅在 Windows 平台有效，其他平台为 no-op。

#[cfg(target_os = "windows")]
mod windows_impl {
    // ── Win32 类型别名 ──
    type BOOL = i32;
    type DWORD = u32;
    type HANDLE = *mut std::ffi::c_void;
    type LPVOID = *mut std::ffi::c_void;
    type LPCWSTR = *const u16;
    type LPWSTR = *mut u16;
    type PHANDLE = *mut HANDLE;
    type PDWORD = *mut DWORD;
    type LUID = u64;

    const FALSE: BOOL = 0;
    const TRUE: BOOL = 1;
    const INVALID_HANDLE_VALUE: HANDLE = -1isize as HANDLE;

    // Token access rights
    const TOKEN_QUERY: DWORD = 0x0008;
    const TOKEN_DUPLICATE: DWORD = 0x0002;
    const TOKEN_ASSIGN_PRIMARY: DWORD = 0x0001;
    const TOKEN_ADJUST_DEFAULT: DWORD = 0x0080;
    const TOKEN_IMPERSONATE: DWORD = 0x0004;

    // Token information class
    const TokenUIAccess: u32 = 26;
    const TokenSessionId: u32 = 12;

    // Security impersonation level
    const SecurityImpersonation: u32 = 2;
    const SecurityAnonymous: u32 = 1;
    const TokenImpersonation: u32 = 2;
    const TokenPrimary: u32 = 1;

    // Process access
    const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;

    // Snapshot flags
    const TH32CS_SNAPPROCESS: DWORD = 0x00000002;

    // Error codes
    pub const ERROR_SUCCESS: DWORD = 0;
    pub const ERROR_NOT_FOUND: DWORD = 1168;

    #[repr(C)]
    struct PROCESSENTRY32W {
        dwSize: DWORD,
        cntUsage: DWORD,
        th32ProcessID: DWORD,
        th32DefaultHeapID: usize,
        th32ModuleID: DWORD,
        cntThreads: DWORD,
        th32ParentProcessID: DWORD,
        pcPriClassBase: i32,
        dwFlags: DWORD,
        szExeFile: [u16; 260],
    }

    #[repr(C)]
    struct STARTUPINFOW {
        cb: DWORD,
        lpReserved: LPWSTR,
        lpDesktop: LPWSTR,
        lpTitle: LPWSTR,
        dwX: DWORD,
        dwY: DWORD,
        dwXSize: DWORD,
        dwYSize: DWORD,
        dwXCountChars: DWORD,
        dwYCountChars: DWORD,
        dwFillAttribute: DWORD,
        dwFlags: DWORD,
        wShowWindow: u16,
        cbReserved2: u16,
        lpReserved2: *mut u8,
        hStdInput: HANDLE,
        hStdOutput: HANDLE,
        hStdError: HANDLE,
    }

    #[repr(C)]
    struct PROCESS_INFORMATION {
        hProcess: HANDLE,
        hThread: HANDLE,
        dwProcessId: DWORD,
        dwThreadId: DWORD,
    }

    #[repr(C)]
    struct LUID_AND_ATTRIBUTES {
        Luid: LUID,
        Attributes: DWORD,
    }

    #[repr(C)]
    struct PRIVILEGE_SET {
        PrivilegeCount: DWORD,
        Control: DWORD,
        Privilege: [LUID_AND_ATTRIBUTES; 1],
    }

    // ── Win32 FFI ──
    extern "system" {
        fn OpenProcessToken(hProcess: HANDLE, dwDesiredAccess: DWORD, phToken: PHANDLE) -> BOOL;
        fn GetTokenInformation(
            hToken: HANDLE,
            tokenInfoClass: u32,
            pTokenInfo: LPVOID,
            dwTokenInfoLen: DWORD,
            pdwRetLen: PDWORD,
        ) -> BOOL;
        fn SetTokenInformation(
            hToken: HANDLE,
            tokenInfoClass: u32,
            pTokenInfo: LPVOID,
            dwTokenInfoLen: DWORD,
        ) -> BOOL;
        fn DuplicateTokenEx(
            hExistingToken: HANDLE,
            dwDesiredAccess: DWORD,
            lpTokenAttributes: LPVOID,
            ImpersonationLevel: u32,
            TokenType: u32,
            phNewToken: PHANDLE,
        ) -> BOOL;
        fn SetThreadToken(hThread: PHANDLE, hToken: HANDLE) -> BOOL;
        fn RevertToSelf() -> BOOL;
        fn CreateToolhelp32Snapshot(dwFlags: DWORD, th32ProcessID: DWORD) -> HANDLE;
        fn Process32FirstW(hSnapshot: HANDLE, lppe: *mut PROCESSENTRY32W) -> BOOL;
        fn Process32NextW(hSnapshot: HANDLE, lppe: *mut PROCESSENTRY32W) -> BOOL;
        fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) -> HANDLE;
        fn LookupPrivilegeValueW(lpSystemName: LPCWSTR, lpName: LPCWSTR, lpLuid: *mut LUID)
            -> BOOL;
        fn PrivilegeCheck(
            ClientToken: HANDLE,
            RequiredPrivileges: *mut PRIVILEGE_SET,
            pfResult: *mut BOOL,
        ) -> BOOL;
        fn CreateProcessAsUserW(
            hToken: HANDLE,
            lpApplicationName: LPCWSTR,
            lpCommandLine: LPWSTR,
            lpProcessAttributes: LPVOID,
            lpThreadAttributes: LPVOID,
            bInheritHandles: BOOL,
            dwCreationFlags: DWORD,
            lpEnvironment: LPVOID,
            lpCurrentDirectory: LPCWSTR,
            lpStartupInfo: *mut STARTUPINFOW,
            lpProcessInformation: *mut PROCESS_INFORMATION,
        ) -> BOOL;
        fn GetStartupInfoW(lpStartupInfo: *mut STARTUPINFOW);
        fn GetCommandLineW() -> LPWSTR;
        fn CloseHandle(hObject: HANDLE) -> BOOL;
        fn GetLastError() -> DWORD;
        fn ExitProcess(uExitCode: u32) -> !;
    }

    /// 将宽字符串转为 Rust String
    unsafe fn wide_to_string(ptr: *const u16) -> String {
        if ptr.is_null() {
            return String::new();
        }
        let len = (0..).take_while(|&i| *ptr.add(i) != 0).count();
        let slice = std::slice::from_raw_parts(ptr, len);
        String::from_utf16_lossy(slice)
    }

    /// 将 Rust 字符串转为以 null 结尾的宽字符串
    fn to_wide(s: &str) -> Vec<u16> {
        let mut v: Vec<u16> = s.encode_utf16().collect();
        v.push(0);
        v
    }

    /// 检查当前进程是否具有 UIAccess 权限
    unsafe fn check_for_ui_access() -> (bool, DWORD) {
        let mut h_token: HANDLE = std::ptr::null_mut();

        let current_process: HANDLE = -1isize as HANDLE; // GetCurrentProcess()
        if OpenProcessToken(current_process, TOKEN_QUERY, &mut h_token) == 0 {
            return (false, GetLastError());
        }

        let mut ui_access: DWORD = 0;
        let mut ret_len: DWORD = 0;
        let result = GetTokenInformation(
            h_token,
            TokenUIAccess,
            &mut ui_access as *mut DWORD as LPVOID,
            std::mem::size_of::<DWORD>() as DWORD,
            &mut ret_len,
        );
        let err = GetLastError();
        CloseHandle(h_token);

        if result != 0 {
            (ui_access != 0, ERROR_SUCCESS)
        } else {
            (false, err)
        }
    }

    /// 复制同一 Session 下 winlogon.exe 的令牌
    unsafe fn duplicate_winlogon_token(
        dw_session_id: DWORD,
        dw_desired_access: DWORD,
        ph_token: PHANDLE,
    ) -> DWORD {
        let se_tcb_name = to_wide("SeTcbPrivilege");
        let mut luid: LUID = 0;

        if LookupPrivilegeValueW(std::ptr::null(), se_tcb_name.as_ptr(), &mut luid) == 0 {
            return GetLastError();
        }

        let mut ps = PRIVILEGE_SET {
            PrivilegeCount: 1,
            Control: 1, // PRIVILEGE_SET_ALL_NECESSARY
            Privilege: [LUID_AND_ATTRIBUTES {
                Luid: luid,
                Attributes: 0,
            }],
        };

        let h_snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if h_snapshot == INVALID_HANDLE_VALUE {
            return GetLastError();
        }

        let mut pe = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as DWORD,
            cntUsage: 0,
            th32ProcessID: 0,
            th32DefaultHeapID: 0,
            th32ModuleID: 0,
            cntThreads: 0,
            th32ParentProcessID: 0,
            pcPriClassBase: 0,
            dwFlags: 0,
            szExeFile: [0u16; 260],
        };

        let mut dw_err = ERROR_NOT_FOUND;
        let mut b_found = false;
        let winlogon_name = to_wide("winlogon.exe");

        let mut b_cont = Process32FirstW(h_snapshot, &mut pe);
        while b_cont != 0 {
            // 比较进程名
            let mut match_name = true;
            for (i, &ch) in winlogon_name.iter().enumerate() {
                if pe.szExeFile[i] != ch {
                    match_name = false;
                    break;
                }
            }
            // 确保 null 终止符匹配
            if match_name && pe.szExeFile[winlogon_name.len() - 1] != 0 {
                match_name = false;
            }

            if match_name {
                let h_process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pe.th32ProcessID);
                if !h_process.is_null() {
                    let mut h_token: HANDLE = std::ptr::null_mut();
                    if OpenProcessToken(h_process, TOKEN_QUERY | TOKEN_DUPLICATE, &mut h_token) != 0
                    {
                        let mut f_tcb: BOOL = 0;
                        if PrivilegeCheck(h_token, &mut ps, &mut f_tcb) != 0 && f_tcb != 0 {
                            let mut sid: DWORD = 0;
                            let mut ret_len: DWORD = 0;
                            if GetTokenInformation(
                                h_token,
                                TokenSessionId,
                                &mut sid as *mut DWORD as LPVOID,
                                std::mem::size_of::<DWORD>() as DWORD,
                                &mut ret_len,
                            ) != 0
                                && sid == dw_session_id
                            {
                                b_found = true;
                                if DuplicateTokenEx(
                                    h_token,
                                    dw_desired_access,
                                    std::ptr::null_mut(),
                                    SecurityImpersonation,
                                    TokenImpersonation,
                                    ph_token,
                                ) != 0
                                {
                                    dw_err = ERROR_SUCCESS;
                                } else {
                                    dw_err = GetLastError();
                                }
                            }
                        }
                        CloseHandle(h_token);
                    }
                    CloseHandle(h_process);
                }
                if b_found {
                    break;
                }
            }
            b_cont = Process32NextW(h_snapshot, &mut pe);
        }

        CloseHandle(h_snapshot);
        dw_err
    }

    /// 创建具有 UIAccess 权限的令牌
    unsafe fn create_ui_access_token(ph_token: PHANDLE) -> DWORD {
        let current_process: HANDLE = -1isize as HANDLE;
        let mut h_token_self: HANDLE = std::ptr::null_mut();

        if OpenProcessToken(
            current_process,
            TOKEN_QUERY | TOKEN_DUPLICATE,
            &mut h_token_self,
        ) == 0
        {
            return GetLastError();
        }

        let mut dw_session_id: DWORD = 0;
        let mut ret_len: DWORD = 0;

        if GetTokenInformation(
            h_token_self,
            TokenSessionId,
            &mut dw_session_id as *mut DWORD as LPVOID,
            std::mem::size_of::<DWORD>() as DWORD,
            &mut ret_len,
        ) == 0
        {
            let err = GetLastError();
            CloseHandle(h_token_self);
            return err;
        }

        let mut h_token_system: HANDLE = std::ptr::null_mut();
        let mut dw_err =
            duplicate_winlogon_token(dw_session_id, TOKEN_IMPERSONATE, &mut h_token_system);

        if dw_err == ERROR_SUCCESS {
            if SetThreadToken(std::ptr::null_mut(), h_token_system) != 0 {
                if DuplicateTokenEx(
                    h_token_self,
                    TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_DEFAULT,
                    std::ptr::null_mut(),
                    SecurityAnonymous,
                    TokenPrimary,
                    ph_token,
                ) != 0
                {
                    let b_ui_access: BOOL = 1;
                    if SetTokenInformation(
                        *ph_token,
                        TokenUIAccess,
                        &b_ui_access as *const BOOL as LPVOID,
                        std::mem::size_of::<BOOL>() as DWORD,
                    ) == 0
                    {
                        dw_err = GetLastError();
                        CloseHandle(*ph_token);
                    }
                } else {
                    dw_err = GetLastError();
                }
                RevertToSelf();
            } else {
                dw_err = GetLastError();
            }
            CloseHandle(h_token_system);
        }

        CloseHandle(h_token_self);
        dw_err
    }

    /// 准备 UIAccess 权限
    ///
    /// 对应 uiaccess-master 中的 `PrepareForUIAccess()`。
    /// 如果当前进程已具备 UIAccess 则返回 `ERROR_SUCCESS`；
    /// 否则创建 UIAccess 令牌并重启自身，旧进程退出。
    ///
    /// 注意：
    /// - 需要以管理员权限运行
    /// - 成功时当前进程会退出并由新进程替代
    pub unsafe fn prepare_for_ui_access() -> DWORD {
        let (has_ui_access, err) = check_for_ui_access();
        if has_ui_access {
            return ERROR_SUCCESS;
        }

        // 如果 check_for_ui_access 本身失败（比如无权限），也尝试获取
        let _ = err;

        let mut h_token_ui_access: HANDLE = std::ptr::null_mut();
        let dw_err = create_ui_access_token(&mut h_token_ui_access);

        if dw_err == ERROR_SUCCESS {
            let mut si: STARTUPINFOW = std::mem::zeroed();
            GetStartupInfoW(&mut si);

            let cmd_line = GetCommandLineW();

            let mut pi: PROCESS_INFORMATION = std::mem::zeroed();

            if CreateProcessAsUserW(
                h_token_ui_access,
                std::ptr::null(),
                cmd_line,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                0,
                std::ptr::null_mut(),
                std::ptr::null(),
                &mut si,
                &mut pi,
            ) != 0
            {
                CloseHandle(pi.hProcess);
                CloseHandle(pi.hThread);
                ExitProcess(0);
            } else {
                let err = GetLastError();
                CloseHandle(h_token_ui_access);
                return err;
            }
        }

        dw_err
    }
}

#[cfg(not(target_os = "windows"))]
mod windows_impl {
    pub const ERROR_SUCCESS: u32 = 0;

    /// 非 Windows 平台的桩实现
    pub unsafe fn prepare_for_ui_access() -> u32 {
        ::log::info!("UI Access is only available on Windows");
        ERROR_SUCCESS
    }
}

pub use windows_impl::*;
