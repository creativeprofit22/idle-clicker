"""Window-driven G6 (Campaign Legacy and Drill) session; NOT physical human operation.

Run: python tests/windows_g6_driver.py
Creates a fresh uniquely named disposable project copy (scenes/, src/, project.godot plus
the read-only tests/g6_ui_reporter.gd autoload), seeds that copy's user-data progress.json,
and plays the README G6 procedure in the real campaign scene: every action is a click, wheel
or WM_CLOSE posted only to the HWND owned by the launched Godot PID. Decisions and checks
use visible UI text and the copy's save files; the real project user data is never touched.
Keep the game window focused and unminimized; focus loss (· Paused) fails the run.
"""

import ctypes
from ctypes import wintypes
import hashlib
import io
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
DEADLINE_SECONDS = 480.0
TROOPS = ["ShieldUpgrade", "FootUpgrade", "HorseUpgrade"]


class Failure(RuntimeError):
    pass


class Checks:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0

    def check(self, condition: bool, message: str) -> bool:
        if condition:
            self.passed += 1
            print(f"PASS g6: {message}", flush=True)
        else:
            self.failed += 1
            print(f"FAIL g6: {message}", flush=True)
        return condition


def user32() -> ctypes.WinDLL:
    lib = ctypes.WinDLL("user32", use_last_error=True)
    lib.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    lib.GetWindowThreadProcessId.restype = wintypes.DWORD
    lib.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    lib.PostMessageW.restype = wintypes.BOOL
    lib.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    lib.ClientToScreen.restype = wintypes.BOOL
    lib.IsIconic.argtypes = [wintypes.HWND]
    lib.IsIconic.restype = wintypes.BOOL
    lib.GetForegroundWindow.restype = wintypes.HWND
    return lib


class Session:
    """One launched game process in the disposable copy, with its own reader thread."""

    def __init__(self, executable: Path, copy: Path, captures: Path, deadline: float, api) -> None:
        self.api = api
        self.deadline = deadline
        env = dict(os.environ, G6_CAPTURE_DIR=str(captures))
        self.process = subprocess.Popen(
            [str(executable), "--path", str(copy), "res://scenes/campaign_prototype.tscn"],
            cwd=copy, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._read, name="g6-output")
        self.reader.start()
        self.hwnd: int | None = None
        self.state: dict | None = None
        self.errors: list[str] = []
        print(f"DRIVER: launched child PID={self.process.pid}", flush=True)

    def _read(self) -> None:
        try:
            assert self.process.stdout is not None
            for line in self.process.stdout:
                self.lines.put(line.rstrip())
        finally:
            self.lines.put(None)

    def remaining(self) -> float:
        left = self.deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError("G6 driver deadline exceeded")
        return left

    def pump(self, timeout: float) -> bool:
        """Process output for up to timeout seconds; False once the child's output ended."""
        end = time.monotonic() + timeout
        while True:
            wait = min(end - time.monotonic(), self.remaining())
            if wait <= 0:
                return True
            try:
                line = self.lines.get(timeout=wait)
            except queue.Empty:
                return True
            if line is None:
                return False
            if line.startswith("G6UI "):
                self.state = json.loads(line[5:])
                status = self.ui["labels"]["CampaignStatus"]
                if status.endswith(" · Paused"):
                    raise Failure("game paused (focus lost or minimized); keep the window focused")
                continue
            print(line, flush=True)
            window = re.fullmatch(r"G6_WINDOW hwnd=(\d+) pid=(\d+)", line)
            if window:
                if int(window[2]) != self.process.pid:
                    raise Failure("reporter PID does not match the launched child")
                self.hwnd = int(window[1])
                self.owned()
            if "SCRIPT ERROR" in line or line.startswith("ERROR:") or "G6_CAPTURE_FAILED" in line:
                self.errors.append(line)

    @property
    def ui(self) -> dict:
        if self.state is None:
            raise Failure("no UI state reported yet")
        return self.state

    def wait(self, predicate, timeout: float, what: str) -> dict:
        end = time.monotonic() + timeout
        while True:
            if self.state is not None and self.hwnd is not None and predicate(self.state):
                return self.state
            if time.monotonic() >= end:
                raise Failure(f"timed out waiting for {what}")
            if not self.pump(min(0.2, max(0.01, end - time.monotonic()))):
                raise Failure(f"game exited while waiting for {what}")

    def owned(self) -> None:
        owner = wintypes.DWORD()
        if self.hwnd is None or self.process.poll() is not None \
                or not self.api.GetWindowThreadProcessId(self.hwnd, ctypes.byref(owner)):
            raise Failure("game process/window is no longer alive")
        if owner.value != self.process.pid:
            raise Failure("refusing to post to a window outside the launched PID")
        if self.api.IsIconic(self.hwnd):
            raise Failure("game window is minimized")

    def post(self, message: int, wparam: int, lparam: int) -> None:
        self.owned()
        if not self.api.PostMessageW(self.hwnd, message, wparam, lparam):
            raise ctypes.WinError(ctypes.get_last_error())

    def click(self, name: str) -> None:
        """Scroll the named enabled button into view with wheel messages, then click it."""
        for _ in range(40):
            button = self.ui["buttons"][name]
            if not button["visible"] or button["disabled"]:
                raise Failure(f"{name} is not clickable: {button}")
            left, top, right, bottom = self.ui["scroll"]
            if top + 4 <= button["y"] <= bottom - 4:
                point = (button["y"] & 0xFFFF) << 16 | (button["x"] & 0xFFFF)
                self.post(0x0200, 0, point)  # WM_MOUSEMOVE
                self.post(0x0201, 0x0001, point)  # WM_LBUTTONDOWN, MK_LBUTTON
                self.post(0x0202, 0, point)  # WM_LBUTTONUP
                print(f"DRIVER: clicked {name} ({button['text']})", flush=True)
                return
            screen = wintypes.POINT((left + right) // 2, (top + bottom) // 2)
            self.owned()
            self.api.ClientToScreen(self.hwnd, ctypes.byref(screen))
            delta = 120 if button["y"] < top else -120
            self.post(0x020A, (delta & 0xFFFF) << 16, (screen.y & 0xFFFF) << 16 | (screen.x & 0xFFFF))
            before = self.ui["buttons"][name]["y"]
            try:
                self.wait(lambda s: s["buttons"][name]["y"] != before, 1.0, f"{name} to scroll")
            except Failure:
                pass
        raise Failure(f"could not scroll {name} into view")

    def close(self, checks: Checks) -> None:
        self.post(0x0010, 0, 0)  # WM_CLOSE, the title-bar X message
        while self.pump(0.2):
            pass
        code = self.process.wait(timeout=max(0.001, self.remaining()))
        checks.check(code == 0, f"WM_CLOSE exited the game with code {code}")
        checks.check(not self.errors, f"no engine/script errors or capture failures this launch: {self.errors}")

    def cleanup(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        self.reader.join(timeout=5)
        if self.process.stdout is not None:
            self.process.stdout.close()
        if self.reader.is_alive():
            raise RuntimeError("game output reader did not terminate")
        print(f"DRIVER CLEANUP: child reaped (exit={self.process.returncode}); reader joined", flush=True)


def cost(button: dict) -> int | None:
    match = re.search(r"Upgrade (\d+) gold", button["text"])
    return int(match[1]) if match else None


def play_until_secured(session: Session, timeout: float) -> None:
    """Greedy play from visible text: cheapest troop upgrade, gate before defense, frontier."""
    end = time.monotonic() + timeout
    while True:
        state = session.wait(lambda s: True, 5.0, "UI state")
        labels, buttons = state["labels"], state["buttons"]
        if labels["CampaignStatus"].startswith("Campaign secured"):
            return
        if time.monotonic() >= end:
            raise Failure(f"campaign not secured within {timeout:g}s: {labels['CampaignStatus']}")
        costs = {name: cost(buttons[name]) for name in TROOPS}
        priced = {name: value for name, value in costs.items() if value is not None}
        cheapest = min(priced.items(), key=lambda item: item[1])[0] if priced else None
        checkpoint = labels["CampaignStatus"].startswith("Conquest cleared")
        gate = cost(buttons["GateUpgrade"])
        action = None
        if checkpoint and gate is not None and not buttons["GateUpgrade"]["disabled"] \
                and (cheapest is None or gate < priced[cheapest]):
            action = "GateUpgrade"
        elif cheapest is not None and not buttons[cheapest]["disabled"]:
            action = cheapest
        elif checkpoint and not buttons["StartDefense"]["disabled"]:
            action = "StartDefense"
        elif not buttons["Frontier"]["disabled"] and labels["PendingNavigation"] == "No queued navigation":
            action = "Frontier"
        if action is None:
            session.pump(0.2)
            continue
        snapshot = json.dumps(state, sort_keys=True)
        session.click(action)
        session.wait(lambda s: json.dumps(s, sort_keys=True) != snapshot, 3.0, f"{action} to take effect")


def main() -> int:
    if sys.platform != "win32":
        raise RuntimeError("This native driver requires Windows")
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    executable = Path(os.environ["LOCALAPPDATA"]) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe"
    if not executable.is_file():
        raise RuntimeError("Pinned Godot 4.7.2 Standard executable is missing")
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.strip()
    stamp = time.strftime("%H%M%S")
    name = f"Border Skirmish G6 {sha} {stamp}"
    copy = Path(tempfile.gettempdir()) / f"bs-g6-{sha}-{stamp}"
    user_dir = Path(os.environ["APPDATA"]) / "Godot/app_userdata" / name
    if copy.exists() or user_dir.exists():
        raise RuntimeError("disposable copy or its user-data folder already exists")
    copy.mkdir()
    for folder in ("scenes", "src"):
        shutil.copytree(ROOT / folder, copy / folder)
    shutil.copy2(ROOT / "tests/g6_ui_reporter.gd", copy / "g6_ui_reporter.gd")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    project = project.replace('config/name="Border Skirmish"', f'config/name="{name}"', 1)
    if name not in project:
        raise RuntimeError("could not rename the disposable project")
    (copy / "project.godot").write_text(project + '\n[autoload]\n\nG6Reporter="*res://g6_ui_reporter.gd"\n',
                                        encoding="utf-8")
    captures = copy / "captures"
    captures.mkdir()
    print(f"DRIVER: window-driven G6, NOT physical; copy={copy}; user data={user_dir}", flush=True)
    subprocess.run([str(executable), "--headless", "--path", str(copy), "--editor", "--quit"],
                   check=True, capture_output=True, timeout=180)
    user_dir.mkdir(parents=True, exist_ok=True)
    progress = user_dir / "progress.json"
    progress.write_bytes(b'{"version":1,"gold":20,"levels":[2,1,1]}')
    progress_hash = hashlib.sha256(progress.read_bytes()).hexdigest()
    campaign_file = user_dir / "campaign.json"
    checks = Checks()
    api = user32()
    deadline = time.monotonic() + DEADLINE_SECONDS

    def save() -> dict:
        return json.loads(campaign_file.read_text(encoding="utf-8"))

    def progress_same(step: str) -> None:
        checks.check(hashlib.sha256(progress.read_bytes()).hexdigest() == progress_hash,
                     f"copy's progress.json byte-identical ({step})")

    def dynasty_line(s: dict) -> str:
        return s["labels"]["DynastyStatus"]

    session = Session(executable, copy, captures, deadline, api)
    try:
        s = session.wait(lambda s: s["labels"]["SaveStatus"] == "Autosave on", 30, "first launch")
        checks.check(dynasty_line(s).startswith("Dynasty 1 · Legacy 0 · Drill rank 0 (×1 squad damage)")
                     and s["buttons"]["TrainDrill"]["disabled"], "fresh copy starts at dynasty 1 without Legacy")
        started = time.monotonic()
        play_until_secured(session, 300)
        s = session.wait(lambda s: True, 1, "secured state")
        print(f"DRIVER: dynasty 1 secured after {time.monotonic() - started:.1f}s of real play", flush=True)
        checks.check(s["labels"]["CampaignStatus"] == "Campaign secured · Counterattack defeated · +10 Legacy earned",
                     "dynasty 1 secure status shows +10 Legacy earned")
        checks.check("Legacy 10" in dynasty_line(s), "dynasty line shows Legacy 10")
        drill = s["buttons"]["TrainDrill"]
        checks.check(drill["text"] == "Train Drill rank 1 — 10 Legacy" and not drill["disabled"],
                     "Train Drill rank 1 — 10 Legacy is offered")
        progress_same("dynasty 1 secured")
        session.click("TrainDrill")
        session.wait(lambda s: "Drill rank 1" in dynasty_line(s), 3, "Train Drill")
        data: dict = {}
        for _ in range(20):
            data = save()
            if data["drill_rank"] == 1:
                break
            session.pump(0.1)
        checks.check(data["legacy"] == 0 and data["drill_rank"] == 1 and data["dynasty"] == 1,
                     f"campaign.json saved immediately: legacy={data['legacy']} drill_rank={data['drill_rank']}")
        before = campaign_file.read_bytes()
        secured_line = session.ui["labels"]["CampaignStatus"]
        drill_line = dynasty_line(session.state)
        session.click("FoundDynasty")
        s = session.wait(lambda s: s["preview_open"], 3, "dynasty preview")
        checks.check("Keep Legacy 0 and Drill rank 1" in s["labels"]["DynastyLosses"]
                     and s["buttons"]["ConfirmDynasty"]["text"] == "Confirm reset — start dynasty 2",
                     "preview discloses kept Legacy/Drill and targets dynasty 2")
        checks.check(s["labels"]["ThreatChoice"].startswith("New dynasty Threat 0 (up to 1)")
                     and "securing it earns 3 Legacy" in s["labels"]["ThreatChoice"]
                     and s["buttons"]["ThreatDown"]["disabled"] and not s["buttons"]["ThreatUp"]["disabled"],
                     "preview defaults to Threat 0 with Threat 1 unlocked")
        session.click("ThreatUp")
        s = session.wait(lambda s: "Threat 1 (up to 1)" in s["labels"]["ThreatChoice"], 3, "Raise Threat")
        checks.check("securing it earns 6 Legacy" in s["labels"]["ThreatChoice"]
                     and "Next secured campaign earns 6 Legacy" in s["labels"]["DynastyLosses"]
                     and s["buttons"]["ThreatUp"]["disabled"], "Raise Threat previews Threat 1 paying 6 Legacy")
        session.click("ThreatDown")
        session.wait(lambda s: "Threat 0 (up to 1)" in s["labels"]["ThreatChoice"], 3, "Lower Threat")
        session.click("CancelDynasty")
        s = session.wait(lambda s: not s["preview_open"], 3, "preview cancel")
        session.pump(0.5)
        checks.check(campaign_file.read_bytes() == before and session.ui["labels"]["CampaignStatus"] == secured_line
                     and dynasty_line(session.state) == drill_line, "Cancel changes nothing (save bytes identical)")
        session.click("FoundDynasty")
        session.wait(lambda s: s["preview_open"], 3, "dynasty preview reopen")
        session.click("ConfirmDynasty")
        s = session.wait(lambda s: dynasty_line(s).startswith("Dynasty 2"), 3, "Confirm")
        confirmed_at = time.monotonic()
        data = save()
        checks.check(data["dynasty"] == 2 and data["legacy"] == 0 and data["drill_rank"] == 1
                     and data["gold"] == 0 and data["levels"] == [1, 1, 1] and data["gate_level"] == 1
                     and data["cleared"] == [False, False, False] and data["current_encounter"] == 0,
                     f"Confirm starts dynasty 2 once with Legacy/Drill kept: {data}")
        checks.check(data["version"] == 9 and data["archer_platform_level"] == 0
                     and data["battle"]["snapshot_platform_level"] == 0 and data["threat"] == 0 and data["best_threat"] == 0
                     and data["legacy_earned"] == 10 and data["veteran_cadre"] is False
                     and data["last_defense_loss"] == 0
                     and data["rally_rounds"] == 0 and data["rally_cooldown"] == 0
                     and data["shield_wall_rounds"] == 0 and data["shield_wall_cooldown"] == 0
                     and s["labels"]["ThreatStatus"].startswith("Threat 0 (enemies +0% health and damage)"),
                     "dynasty 2 saved as v9 at the default Threat 0 with best 0 and 10 Legacy earned, Veteran Cadre unowned, no defense loss cause, Rally and Shield Wall ready, Archer Platform at level 0")
        army = s["labels"]["Army"]
        checks.check(all(f"Damage {d}" in army for d in (8, 16, 12)),
                     "dynasty 2 squads deal ×2 damage (8/16/12)")
        # Passive opening Border: no input until it settles.
        enemy_hp, rounds = [], set()
        while not session.ui["labels"]["LastResult"].startswith("Border Skirmish"):
            if time.monotonic() - confirmed_at > 10:
                raise Failure("dynasty 2 Border did not settle within 10s")
            labels = session.ui["labels"]
            rounds.add(labels["Round"])
            hp = re.search(r"Enemy shield \| HP (\d+) / 72", labels["Enemies"])
            if hp and (not enemy_hp or enemy_hp[-1] != int(hp[1])):
                enemy_hp.append(int(hp[1]))
            session.pump(0.05)
        took = time.monotonic() - confirmed_at
        result = session.ui["labels"]["LastResult"]
        checks.check(result == "Border Skirmish: Victory · +10 gold" and rounds <= {"Round: 0", "Round: 1"}
                     and enemy_hp == [72, 36] and 1.5 <= took <= 3.5,
                     f"dynasty 2 Border at ×2 won in 2 passive rounds (hp {enemy_hp}, {took:.2f}s, {result})")
        session.pump(1.4)
        progress_same("before close")
        dynasty_before_close = dynasty_line(session.state)
        session.close(checks)
        data = save()
        checks.check(data["dynasty"] == 2 and data["legacy"] == 0 and data["drill_rank"] == 1
                     and data["cleared"][0], "close save keeps dynasty 2, Legacy and Drill rank")
        session.cleanup()

        session = Session(executable, copy, captures, deadline, api)
        s = session.wait(lambda s: s["labels"]["SaveStatus"] == "Autosave on", 30, "relaunch")
        checks.check(s["labels"]["LastResult"] == "Resumed saved campaign"
                     and dynasty_line(s) == dynasty_before_close
                     and dynasty_line(s).startswith("Dynasty 2 · Legacy 0 · Drill rank 1 (×2 squad damage)"),
                     "relaunch keeps Legacy and Drill rank")
        started = time.monotonic()
        play_until_secured(session, 150)
        s = session.wait(lambda s: True, 1, "dynasty 2 secured")
        print(f"DRIVER: dynasty 2 secured after {time.monotonic() - started:.1f}s of real play", flush=True)
        checks.check(s["labels"]["CampaignStatus"] == "Campaign secured · Counterattack defeated · +3 Legacy earned",
                     "dynasty 2 secure status shows +3 Legacy earned")
        checks.check(not s["buttons"]["FoundDynasty"]["disabled"] and "Legacy 3" in dynasty_line(s),
                     "Found a Dynasty stays enabled with Legacy 3")
        session.click("FoundDynasty")
        s = session.wait(lambda s: s["preview_open"], 3, "second preview")
        checks.check(s["buttons"]["ConfirmDynasty"]["text"] == "Confirm reset — start dynasty 3",
                     "second preview targets dynasty 3")
        session.click("ThreatUp")
        s = session.wait(lambda s: "Threat 1 (up to 1)" in s["labels"]["ThreatChoice"], 3, "Raise Threat for dynasty 3")
        session.click("ConfirmDynasty")
        s = session.wait(lambda s: dynasty_line(s).startswith("Dynasty 3"), 3, "dynasty 3")
        data = save()
        checks.check(data["dynasty"] == 3 and data["legacy"] == 3 and data["drill_rank"] == 1,
                     f"Confirm reaches dynasty 3 keeping Legacy 3 and Drill rank 1: dynasty={data['dynasty']}")
        checks.check(data["threat"] == 1 and data["best_threat"] == 0 and data["legacy_earned"] == 13
                     and s["labels"]["ThreatStatus"].startswith("Threat 1 (enemies +25% health and damage)")
                     and "/ 90" in s["labels"]["Enemies"]
                     and dynasty_line(s).endswith("Securing this campaign earns 6 Legacy"),
                     f"dynasty 3 starts at chosen Threat 1 with scaled enemies (72 → 90 HP) and a 6-Legacy payout: {data}")
        session.pump(0.5)
        session.close(checks)
        progress_same("end")
    except Failure as error:
        checks.check(False, f"unreached remainder: {error}")
    finally:
        session.cleanup()
    print(f"CAPTURES: {captures}", flush=True)
    print(f"SUMMARY: g6: {checks.passed} checks, {checks.failed} failures", flush=True)
    return 0 if checks.failed == 0 and checks.passed > 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, TimeoutError, subprocess.SubprocessError) as error:
        print(f"DRIVER FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
