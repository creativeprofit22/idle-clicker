"""One bounded native-Windows smoke scenario; NOT the physical manual gate.

Run: python tests/windows_campaign_driver.py [focus-only|campaign|defense|dynasty] [--human-minimize]
--human-minimize: a person clicks the title-bar minimize (the driver never minimizes);
the driver pauses its deadline only while waiting for that click, confirms the window
is iconic, then performs the same native restore as unattended runs.
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
    scenarios = {"focus-only": ["--focus-only"], "campaign": [], "defense": ["--defense"], "dynasty": ["--dynasty"]}
    args = sys.argv[1:]
    human_minimize = "--human-minimize" in args
    if human_minimize:
        args.remove("--human-minimize")
    scenario = args[0] if len(args) == 1 else "focus-only"
    if len(args) > 1 or scenario not in scenarios:
        raise RuntimeError("Usage: windows_campaign_driver.py [focus-only|campaign|defense|dynasty] [--human-minimize]")
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
         "--", "--native-window-driver", *(["--human-minimize"] if human_minimize else []), *scenarios[scenario]],
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
    paused_remaining = None
    observed_human_minimize = False
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
        mode = "PHYSICAL minimize, native restore" if human_minimize else "NOT physical verification"
        print(f"DRIVER: automated {scenario}; child PID={process.pid}; deadline={timeout:g}s; {mode}", flush=True)
        while True:
            # Only the human minimize wait is excluded from the deadline, never replenished.
            remaining = None if paused_remaining is not None else deadline - time.monotonic()
            if remaining is not None and remaining <= 0:
                raise TimeoutError("Native driver deadline exceeded")
            try:
                line = output.get(timeout=remaining)
            except queue.Empty as exc:
                raise TimeoutError("Native driver received no result before deadline") from exc
            if line is None:
                break
            print(line, flush=True)
            if paused_remaining is not None and line.startswith("NATIVE_DIAG: stage=minimized-observed "):
                owned_window(hwnd)
                observed_human_minimize = bool(user32.IsIconic(hwnd))
                deadline = time.monotonic() + paused_remaining
                paused_remaining = None
                print(f"DRIVER: Windows confirms physical minimize={observed_human_minimize}; deadline resumed", flush=True)
            request = re.fullmatch(r"NATIVE_DRIVER: (minimize|await-minimize|restore|complete) hwnd=(\d+) pid=(\d+)", line)
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
                first = "human-minimize" if human_minimize else "minimize"
                if action in ("minimize", "await-minimize") and (action == "await-minimize") != human_minimize:
                    raise RuntimeError("Minimize request does not match the selected driver mode")
                if actions != ([] if action in ("minimize", "await-minimize") else [first]):
                    raise RuntimeError("Unexpected or repeated native action")
                if action == "await-minimize":
                    # The driver never minimizes here; a person must click the title bar.
                    paused_remaining = deadline - time.monotonic()
                    actions.append("human-minimize")
                    print("DRIVER: waiting for YOUR title-bar minimize click (deadline paused)", flush=True)
                    continue
                # SW_MINIMIZE=6, SW_RESTORE=9. Async return means queued, not completed.
                if not user32.ShowWindowAsync(hwnd, 6 if action == "minimize" else 9):
                    raise ctypes.WinError(ctypes.get_last_error())
                actions.append(action)
                print(f"DRIVER: queued native {action} for owned HWND={hwnd}", flush=True)
            if hwnd is not None and (line.startswith("NATIVE_DIAG:") or line.startswith("FAIL campaign: native")):
                # Read-only failure-time evidence, independent of PASS bookkeeping.
                # These samples occur on receipt, not atomically with Godot's snapshot.
                owned_window(hwnd)
                owner = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
                print(f"DRIVER DIAG: received_monotonic={time.monotonic():.6f} unix={time.time():.6f} "
                      f"hwnd={hwnd} child_pid={process.pid} owner_pid={owner.value} "
                      f"iconic={bool(user32.IsIconic(hwnd))} "
                      f"foreground_equal={user32.GetForegroundWindow() == hwnd}", flush=True)
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
        if paused_remaining is not None:
            raise RuntimeError("Smoke ended while waiting for the physical minimize")
        code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
        expected = ["human-minimize", "restore"] if human_minimize else ["minimize", "restore"]
        complete = (summary is not None and summary[1] == 0 and actions == expected
                    and observed_minimized and observed_restored
                    and (observed_human_minimize or not human_minimize))
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
