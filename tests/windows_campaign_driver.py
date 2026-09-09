"""One bounded native-Windows smoke scenario; NOT the physical manual gate.

Run: python tests/windows_campaign_driver.py [focus-only|campaign|defense]
APIs: https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-showwindowasync
Uses only stdlib; never broadcasts input, changes engine state, or touches other PIDs.
"""

import ctypes
from ctypes import wintypes
import os
import io
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time


def main() -> int:
    if sys.platform != "win32":
        raise RuntimeError("This native driver requires Windows")
    scenarios = {"focus-only": ["--focus-only"], "campaign": [], "defense": ["--defense"]}
    scenario = sys.argv[1] if len(sys.argv) == 2 else "focus-only"
    if len(sys.argv) > 2 or scenario not in scenarios:
        raise RuntimeError("Usage: windows_campaign_driver.py [focus-only|campaign|defense]")
    timeout = 12.0 if scenario == "focus-only" else 65.0
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(errors="backslashreplace")
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.ShowWindowAsync.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.ShowWindowAsync.restype = wintypes.BOOL
    user32.IsIconic.argtypes = [wintypes.HWND]
    user32.IsIconic.restype = wintypes.BOOL
    user32.GetForegroundWindow.argtypes = []
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.PostMessageW.restype = wintypes.BOOL
    # Launch the actual pinned engine, not the console forwarding executable:
    # Popen's process handle and PID must own the HWND and cleanup target directly.
    executable = Path(os.environ["LOCALAPPDATA"]) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe"
    if not executable.is_file():
        raise RuntimeError("Pinned Godot 4.7.2 Standard executable is missing")
    process = subprocess.Popen(
        [str(executable), "--path", ".", "--script", "tests/campaign_scene_smoke.gd",
         "--", "--native-window-driver", *scenarios[scenario]],
        cwd=Path(__file__).resolve().parents[1], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace",
    )
    output = queue.Queue()

    def read_output() -> None:
        try:
            if process.stdout is None:
                return
            for line in process.stdout:
                output.put(line.rstrip())
        finally:
            output.put(None)

    reader = threading.Thread(target=read_output, name="smoke-output")
    deadline = time.monotonic() + timeout
    hwnd = None
    actions = []
    summary = None
    observed_minimized = False
    observed_restored = False

    def owned_window(handle: int | None) -> None:
        if handle is None:
            raise RuntimeError("Smoke window has not been identified")
        owner = wintypes.DWORD()
        if process.poll() is not None or not user32.GetWindowThreadProcessId(handle, ctypes.byref(owner)):
            raise RuntimeError("Smoke process/window is no longer alive")
        if owner.value != process.pid:
            raise RuntimeError("Refusing to operate on a window outside the launched smoke PID")

    try:
        reader.start()
        print(f"DRIVER: automated {scenario}; child PID={process.pid}; deadline={timeout:g}s; NOT physical verification", flush=True)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Native driver deadline exceeded")
            try:
                line = output.get(timeout=remaining)
            except queue.Empty as exc:
                raise TimeoutError("Native driver received no result before deadline") from exc
            if line is None:
                break
            print(line, flush=True)
            request = re.fullmatch(r"NATIVE_DRIVER: (minimize|restore|complete) hwnd=(\d+) pid=(\d+)", line)
            if request:
                action, handle, pid = request.groups()
                handle = int(handle)
                if int(pid) != process.pid or (hwnd is not None and hwnd != handle):
                    raise RuntimeError("Driver request changed process or window identity")
                owned_window(handle)
                hwnd = handle
                if action == "complete":
                    # WM_CLOSE preserves the smoke's own recorded exit status.
                    if not user32.PostMessageW(hwnd, 0x0010, 0, 0):
                        raise ctypes.WinError(ctypes.get_last_error())
                    continue
                if actions != ([] if action == "minimize" else ["minimize"]):
                    raise RuntimeError("Unexpected or repeated native action")
                # SW_MINIMIZE=6, SW_RESTORE=9. Async return means queued, not completed.
                if not user32.ShowWindowAsync(hwnd, 6 if action == "minimize" else 9):
                    raise ctypes.WinError(ctypes.get_last_error())
                actions.append(action)
                print(f"DRIVER: queued native {action} for owned HWND={hwnd}", flush=True)
            if line.startswith("PASS campaign: native minimized interval freezes"):
                owned_window(hwnd)
                observed_minimized = bool(user32.IsIconic(hwnd)) and user32.GetForegroundWindow() != hwnd
                print(f"DRIVER: Windows confirms minimized and not foreground={observed_minimized}", flush=True)
            if line.startswith("PASS campaign: native restore retains"):
                owned_window(hwnd)
                observed_restored = not user32.IsIconic(hwnd) and user32.GetForegroundWindow() == hwnd
                print(f"DRIVER: Windows confirms restored and foreground={observed_restored}", flush=True)
            match = re.fullmatch(r"SUMMARY: campaign: (\d+) graphical checks, (\d+) failures", line)
            if match:
                summary = (int(match[1]), int(match[2]))
        code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
        complete = (summary is not None and summary[1] == 0 and actions == ["minimize", "restore"]
                    and observed_minimized and observed_restored)
        print(f"DRIVER SUMMARY: scenario={scenario}, child_exit={code}, smoke_summary={summary}, native_observations_complete={complete}")
        return 0 if code == 0 and complete else 1
    finally:
        # Every normal/error/timeout path reaps exactly our child and joins its reader.
        if process.poll() is None:
            process.kill()
        process.wait(timeout=2)
        if reader.ident is not None:
            reader.join(timeout=2)
        if process.stdout is not None:
            process.stdout.close()
        if reader.is_alive():
            raise RuntimeError("Smoke output reader did not terminate")
        print(f"DRIVER CLEANUP: child reaped (exit={process.returncode}); reader joined", flush=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
        print(f"DRIVER FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
