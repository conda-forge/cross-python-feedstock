/*
  Windows launcher for cross-python. The activation puts this x64 program in
  place of the target's %PREFIX%\python.exe, which cannot run on the build
  machine, so that recipe scripts calling that literal path (which is what
  ${{ PYTHON }} renders to) reach %BUILD_PREFIX%\python.exe instead. The
  command line is passed on unchanged and the child's exit code returned.
*/
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

static int fail(const wchar_t *msg) {
    fwprintf(stderr, L"cross-python shim: %ls\n", msg);
    return 1;
}

/* skip argv[0] the way the C runtime parses it: quotes toggle, no escapes */
static const wchar_t *skip_argv0(const wchar_t *cmd) {
    int quoted = 0;
    for (; *cmd; cmd++) {
        if (*cmd == L'"')
            quoted = !quoted;
        else if ((*cmd == L' ' || *cmd == L'\t') && !quoted)
            break;
    }
    return cmd;
}

static int same_file(const wchar_t *a, const wchar_t *b) {
    BY_HANDLE_FILE_INFORMATION ia, ib;
    int same = 0;
    DWORD share = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    HANDLE ha = CreateFileW(a, 0, share, NULL, OPEN_EXISTING, 0, NULL);
    HANDLE hb = CreateFileW(b, 0, share, NULL, OPEN_EXISTING, 0, NULL);
    if (ha != INVALID_HANDLE_VALUE && hb != INVALID_HANDLE_VALUE &&
        GetFileInformationByHandle(ha, &ia) && GetFileInformationByHandle(hb, &ib))
        same = ia.dwVolumeSerialNumber == ib.dwVolumeSerialNumber &&
               ia.nFileIndexHigh == ib.nFileIndexHigh &&
               ia.nFileIndexLow == ib.nFileIndexLow;
    if (ha != INVALID_HANDLE_VALUE)
        CloseHandle(ha);
    if (hb != INVALID_HANDLE_VALUE)
        CloseHandle(hb);
    return same;
}

int wmain(void) {
    wchar_t build_prefix[MAX_PATH], target[MAX_PATH], self[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"BUILD_PREFIX", build_prefix, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        return fail(L"BUILD_PREFIX is not set");
    if (swprintf(target, MAX_PATH, L"%ls\\python.exe", build_prefix) < 0)
        return fail(L"BUILD_PREFIX is too long");
    n = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        return fail(L"cannot resolve the path of the shim");
    if (same_file(self, target))
        return fail(L"%BUILD_PREFIX%\\python.exe is this shim");

    const wchar_t *tail = skip_argv0(GetCommandLineW());
    size_t len = wcslen(target) + wcslen(tail) + 3;
    wchar_t *cmd = malloc(len * sizeof(wchar_t));
    if (!cmd)
        return fail(L"out of memory");
    swprintf(cmd, len, L"\"%ls\"%ls", target, tail);

    /* kill the child along with the shim, like the py launcher does */
    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {0};
        info.BasicLimitInformation.LimitFlags =
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof(info));
    }
    /* Ctrl-C is for the child to handle */
    SetConsoleCtrlHandler(NULL, TRUE);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    GetStartupInfoW(&si);
    if (!CreateProcessW(target, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, &si, &pi)) {
        fwprintf(stderr, L"cross-python shim: cannot run %ls (error %lu)\n", target, GetLastError());
        return 1;
    }
    if (job)
        AssignProcessToJobObject(job, pi.hProcess);
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD rc = 1;
    GetExitCodeProcess(pi.hProcess, &rc);
    return (int)rc;
}
