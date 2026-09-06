"""Exercise installed Mix hooks with macOS Bash and isolated fake Mix projects."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
ACTIONS = ("format", "compile", "credo")
FAKE_MIX = r'''
import json
import os
from pathlib import Path
import subprocess
import sys
import time

project = Path.cwd()
action = sys.argv[1]
record = {"cwd": str(project), "args": sys.argv[1:], "pid": os.getpid()}
def log(phase):
    payload = dict(record, phase=phase)
    fd = os.open(os.environ["FAKE_MIX_LOG"], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.write(fd, (json.dumps(payload) + "\n").encode())
    os.close(fd)

log("start")
if os.environ.get("FAKE_MIX_CHILD_PID"):
    code = "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"
    child = subprocess.Popen([sys.executable, "-c", code])
    Path(os.environ["FAKE_MIX_CHILD_PID"]).write_text(str(child.pid))
time.sleep(float(os.environ.get("FAKE_MIX_DELAY", "0")))
behavior = project / ".fake-mix.json"
result = json.loads(behavior.read_text()).get(action, {}) if behavior.exists() else {}
if result.get("output"):
    print(result["output"])
log("end")
sys.exit(result.get("code", 0))
'''


class MixHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mix hooks test ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.workspace = self.base / "workspace"
        self.workspace.mkdir()
        self.shell_cwd = self.base / "unrelated shell cwd"
        self.shell_cwd.mkdir()
        self.log = self.base / "mix calls.jsonl"
        self.bin = self.base / "fake bin"
        self.bin.mkdir()
        (self.bin / "bash").symlink_to("/bin/bash")
        mix = self.bin / "mix"
        mix.write_text(f"#!{sys.executable}\n" + FAKE_MIX)
        mix.chmod(0o755)
        lsof = self.bin / "lsof"
        lsof.write_text("#!/bin/bash\nexit 1\n")
        lsof.chmod(0o755)
        self.plugins = {}
        for action in ACTIONS:
            installed = self.base / "installed plugins" / f"mix-{action}"
            shutil.copytree(ROOT / "plugins" / f"mix-{action}", installed)
            self.plugins[action] = installed
        tempdir = self.base / "temporary files"
        tempdir.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        FAKE_MIX_LOG=str(self.log), TMPDIR=str(tempdir))
        self.env.pop("BASH_ENV", None)
        self.env.pop("ENV", None)

    def project(self, name, files=()):
        project = self.workspace / name
        project.mkdir(parents=True)
        (project / "mix.exs").write_text("# fake Mix project\n")
        for name in files:
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# fake source\n")
        return project

    def event(self, tool_input, tool_name="Edit", cwd=None):
        return {"hook_event_name": "PostToolUse", "tool_name": tool_name,
                "cwd": str(cwd or self.workspace), "tool_input": tool_input}

    def payload(self, event):
        return event if isinstance(event, str) else json.dumps(event, ensure_ascii=True)

    def start(self, action, event, manifest=False, env=None):
        installed = self.plugins[action]
        environment = dict(self.env, CLAUDE_PLUGIN_ROOT=str(installed))
        environment.update(env or {})
        if manifest:
            config = json.loads((installed / "hooks/hooks.json").read_text())
            handler = config["hooks"]["PostToolUse"][0]["hooks"][0]
            command = ["/bin/bash", "-c", handler["command"]]
        else:
            command = ["/bin/bash", str(installed / "hooks/mix-hook.sh"), action]
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, cwd=self.shell_cwd,
                                   env=environment)
        process.stdin.write(self.payload(event))
        process.stdin.close()
        process.stdin = None
        return process

    def finish(self, process):
        try:
            stdout, stderr = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            self.fail("Hook did not finish within 20 seconds")
        self.assertEqual(process.returncode, 0, stderr or stdout)
        if not stdout.strip():
            return ""
        output = json.loads(stdout)
        specific = output["hookSpecificOutput"]
        self.assertEqual(specific["hookEventName"], "PostToolUse")
        self.assertIsInstance(specific["additionalContext"], str)
        return specific["additionalContext"]

    def run_hook(self, action, event, **kwargs):
        return self.finish(self.start(action, event, **kwargs))

    def records(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def calls(self):
        return [record for record in self.records() if record["phase"] == "start"]

    def clear_log(self):
        self.log.unlink(missing_ok=True)

    def checked_paths(self, calls):
        return {str((Path(call["cwd"]) / argument).resolve())
                for call in calls for argument in call["args"][1:] if argument != "--"}

    def wait_until(self, condition, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.02)
        self.assertTrue(condition(), "Timed out waiting for the expected process state")

    def process_alive(self, pid):
        status = Path(f"/proc/{pid}/status")
        if status.exists():
            try:
                state = next(line for line in status.read_text().splitlines()
                             if line.startswith("State:"))
                if state.split()[1] == "Z":
                    return False
            except FileNotFoundError:
                return False
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def kill_group(self, pid):
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def test_claude_escaped_paths_use_event_cwd_in_standalone_plugins(self):
        filename = 'lib/spaces "quote" \\backslash\ttab café 😀\nline.ex'
        project = self.project('project "quoted" café', [filename])
        path = project / filename
        for action in ACTIONS:
            for key, tool in (("file_path", "Edit"), ("filePath", "Write")):
                with self.subTest(action=action, key=key):
                    self.clear_log()
                    event = self.event({key: filename}, tool, cwd=project)
                    self.run_hook(action, event, manifest=True)
                    calls = self.calls()
                    self.assertEqual(len(calls), 1)
                    self.assertEqual(calls[0]["cwd"], str(project))
                    if action == "compile":
                        self.assertEqual(calls[0]["args"], ["compile", "--warnings-as-errors"])
                    else:
                        self.assertEqual(self.checked_paths(calls), {str(path)})

    def test_codex_patch_groups_projects_and_tracks_surviving_paths(self):
        first = self.project("first", ["lib/added.ex", "lib/update.ex"])
        second = self.project("second", ["lib/moved.ex", "test/script.exs"])
        scripts = self.project("scripts only", ["test/script.exs", "README.md"])
        patch = "\n".join([
            "*** Begin Patch", "*** Add File: first/lib/added.ex", "+# added",
            "+*** Delete File: ignored.ex", "*** Update File: first/lib/update.ex",
            "@@", "-# old", "+# updated", "*** Delete File: first/lib/deleted.ex",
            "*** Update File: first/lib/old.ex", "*** Move to: second/lib/moved.ex",
            "@@", "-# old", "+# moved", "*** Update File: second/test/script.exs",
            "@@", "+# test", "*** Update File: scripts only/test/script.exs",
            "@@", "+# test", "*** Update File: scripts only/README.md",
            "@@", "+docs", "*** End Patch",
        ])
        event = self.event({"command": patch}, "apply_patch")
        expected = {str(first / "lib/added.ex"), str(first / "lib/update.ex"),
                    str(second / "lib/moved.ex"), str(second / "test/script.exs"),
                    str(scripts / "test/script.exs")}
        for action in ACTIONS:
            with self.subTest(action=action):
                self.clear_log()
                self.run_hook(action, event)
                calls = self.calls()
                if action == "compile":
                    self.assertCountEqual([call["cwd"] for call in calls], [str(first), str(second)])
                    self.assertTrue(all(call["args"] == ["compile", "--warnings-as-errors"]
                                        for call in calls))
                else:
                    self.assertEqual(self.checked_paths(calls), expected)
                    checked = sum(len([arg for arg in call["args"][1:] if arg != "--"])
                                  for call in calls)
                    self.assertEqual(checked, len(expected))

    def test_delete_and_move_away_from_elixir_still_compile_old_projects(self):
        deleted = self.project("deleted", ["lib/keep.txt"])
        moved = self.project("moved", ["lib/renamed.txt"])
        patch = "\n".join([
            "*** Begin Patch", "*** Delete File: deleted/lib/gone.ex",
            "*** Update File: moved/lib/old.ex", "*** Move to: moved/lib/renamed.txt",
            "@@", "-# old", "+# moved", "*** End Patch",
        ])
        event = self.event({"command": patch}, "apply_patch")
        self.run_hook("compile", event)
        self.assertCountEqual([call["cwd"] for call in self.calls()], [str(deleted), str(moved)])
        for action in ("format", "credo"):
            self.clear_log()
            self.run_hook(action, event)
            self.assertEqual(self.calls(), [])

    def test_codex_crlf_patch_checks_changed_files(self):
        project = self.project("crlf", ["lib/changed.ex"])
        patch = "\r\n".join(["*** Begin Patch", "*** Update File: crlf/lib/changed.ex",
                             "@@", "-# old", "+# new", "*** End Patch", ""])
        event = self.event({"command": patch}, "apply_patch")
        for action in ACTIONS:
            with self.subTest(action=action):
                self.clear_log()
                self.run_hook(action, event)
                self.assertEqual(len(self.calls()), 1)
                if action != "compile":
                    self.assertEqual(self.checked_paths(self.calls()),
                                     {str(project / "lib/changed.ex")})

    def test_failures_reach_model_and_do_not_skip_other_projects(self):
        broken = self.project("broken", ["lib/file.ex"])
        healthy = self.project("healthy", ["lib/file.ex"])
        (broken / ".fake-mix.json").write_text(json.dumps({
            action: {"code": 1, "output": f'{action}: bad "quoted" value\nsecond line'}
            for action in ACTIONS
        }))
        patch = "\n".join(["*** Begin Patch", "*** Update File: broken/lib/file.ex",
                           "@@", "+# changed", "*** Update File: healthy/lib/file.ex",
                           "@@", "+# changed", "*** End Patch"])
        for action in ACTIONS:
            with self.subTest(action=action):
                self.clear_log()
                message = self.run_hook(action, self.event({"command": patch}, "apply_patch"))
                self.assertIn(f'{action}: bad "quoted" value\nsecond line', message)
                self.assertCountEqual([call["cwd"] for call in self.calls()],
                                      [str(broken), str(healthy)])

    def test_unrelated_or_malformed_events_do_not_run_mix(self):
        project = self.project("project", ["README.md", "lib/source.ex"])
        outside = self.workspace / "outside.ex"
        outside.write_text("# outside a Mix project\n")
        events = [
            self.event({"file_path": str(project / "README.md")}),
            self.event({"command": "echo hello"}, "Bash"),
            self.event({"file_path": str(outside)}),
            self.event({"content": json.dumps({"file_path": str(project / "lib/source.ex")})}),
            self.event({"command": "*** Begin Patch\n*** End Patch"}, "apply_patch"),
            '{"tool_input":',
        ]
        for action in ACTIONS:
            for index, event in enumerate(events):
                with self.subTest(action=action, event=index):
                    self.run_hook(action, event)
                    self.assertEqual(self.calls(), [])

    def test_compile_ignores_scripts_but_format_and_credo_check_them(self):
        project = self.project("scripts", ["test/script.exs"])
        event = self.event({"file_path": str(project / "test/script.exs")})
        self.run_hook("compile", event)
        self.assertEqual(self.calls(), [])
        for action in ("format", "credo"):
            self.clear_log()
            self.run_hook(action, event)
            self.assertEqual(self.checked_paths(self.calls()), {str(project / "test/script.exs")})

    def test_credo_absence_is_distinct_from_project_failure(self):
        project = self.project("credo", ["lib/source.ex"])
        event = self.event({"file_path": str(project / "lib/source.ex")})
        absent = '** (Mix) The task "credo" could not be found'
        behavior = project / ".fake-mix.json"
        behavior.write_text(json.dumps({"credo": {"code": 1, "output": absent}}))
        message = self.run_hook("credo", event)
        self.assertNotIn("failed", message.lower())
        self.assertEqual(len(self.calls()), 1)
        self.clear_log()
        failure = "** (Mix) Can't continue due to errors on dependencies"
        behavior.write_text(json.dumps({"credo": {"code": 1, "output": failure}}))
        message = self.run_hook("credo", event)
        self.assertIn(failure, message)
        self.assertEqual(len(self.calls()), 1)

    def test_concurrent_plugins_serialize_mix_for_one_project(self):
        project = self.project("concurrent", ["lib/source.ex"])
        event = self.event({"file_path": str(project / "lib/source.ex")})
        processes = [self.start(action, event, env={"FAKE_MIX_DELAY": "0.3"})
                     for action in ACTIONS]
        for process in processes:
            self.finish(process)
        records = self.records()
        self.assertEqual(len(records), 6)
        active = set()
        for record in records:
            if record["phase"] == "start":
                self.assertFalse(active, f"Overlapping Mix commands: {records}")
                active.add(record["pid"])
            else:
                self.assertIn(record["pid"], active)
                active.remove(record["pid"])
        self.assertFalse(active)
        self.assertCountEqual([call["args"][0] for call in self.calls()], ACTIONS)

    def test_alias_project_paths_share_a_lock(self):
        project = self.project("canonical", ["lib/source.ex"])
        alias = self.workspace / "alias"
        alias.symlink_to(project, target_is_directory=True)
        events = [self.event({"file_path": "lib/source.ex"}, cwd=directory)
                  for directory in (project, alias)]
        processes = [self.start("format", event, env={"FAKE_MIX_DELAY": "0.3"})
                     for event in events]
        for process in processes:
            self.finish(process)
        records = self.records()
        self.assertEqual([record["phase"] for record in records],
                         ["start", "end", "start", "end"])
        self.assertTrue(all(record["cwd"] == str(project) for record in records))

    def test_timeout_kills_mix_and_descendants_and_releases_lock(self):
        script = self.plugins["format"] / "hooks/mix-hook.sh"
        original = script.read_text()
        shortened = original.replace("format) budget=45 ;;", "format) budget=2 ;;")
        self.assertNotEqual(shortened, original)
        script.write_text(shortened)
        project = self.project("timeout", ["lib/source.ex"])
        event = self.event({"file_path": str(project / "lib/source.ex")})
        marker = self.base / "descendant.pid"
        process = self.start("format", event, env={"FAKE_MIX_DELAY": "60",
                                                  "FAKE_MIX_CHILD_PID": str(marker)})
        self.wait_until(marker.exists)
        parent_pid = self.calls()[0]["pid"]
        child_pid = int(marker.read_text())
        self.addCleanup(self.kill_group, parent_pid)
        message = self.finish(process)
        self.assertIn("timed out", message.lower())
        self.wait_until(lambda: not self.process_alive(parent_pid) and
                               not self.process_alive(child_pid))
        self.clear_log()
        self.run_hook("format", event)
        self.assertEqual(len(self.calls()), 1)

    def test_cancellation_kills_mix_and_descendants_and_releases_lock(self):
        project = self.project("cancelled", ["lib/source.ex"])
        event = self.event({"file_path": str(project / "lib/source.ex")})
        marker = self.base / "descendant.pid"
        process = self.start("format", event, env={"FAKE_MIX_DELAY": "60",
                                                  "FAKE_MIX_CHILD_PID": str(marker)})
        self.wait_until(marker.exists)
        parent_pid = self.calls()[0]["pid"]
        child_pid = int(marker.read_text())
        self.addCleanup(self.kill_group, parent_pid)
        process.terminate()
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, 143)
        self.wait_until(lambda: not self.process_alive(parent_pid) and
                               not self.process_alive(child_pid))
        self.clear_log()
        self.run_hook("format", event)
        self.assertEqual(len(self.calls()), 1)

    def test_beam_detection_matches_exact_project_path(self):
        project = self.project("beam project", ["lib/source.ex"])
        event = self.event({"file_path": str(project / "lib/source.ex")})
        lsof = self.bin / "lsof"
        lsof.write_text('#!/bin/bash\nprintf "%s\\n" "p123" "n$FAKE_BEAM_CWD"\n')
        message = self.run_hook("compile", event, env={"FAKE_BEAM_CWD": str(project)})
        self.assertEqual(self.calls(), [])
        self.assertIn("skipped", message.lower())
        self.run_hook("compile", event, env={"FAKE_BEAM_CWD": str(project) + "-other"})
        self.assertEqual(len(self.calls()), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
