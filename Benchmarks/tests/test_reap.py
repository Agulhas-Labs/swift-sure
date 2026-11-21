"""bench.py's `limited` reaps every process a run leaves standing in its directory, including ones that left
the run's process group and session, and nothing outside it. Run: python3 -m unittest discover -s Benchmarks/tests"""

import io
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import bench  # noqa: E402  (bench.py has no import-time side effects: it only names paths)

# Started from the run's directory and gone before the run ends: a shell in a session of its own (as Claude
# Code's Bash tool starts one), whose child moves to yet another session (as `swift-sure run` moves
# `swift test` to a group of its own), both left in a subdirectory and reparented to launchd.
SPAWNER = r"""
import os, subprocess, sys, time
inner_pid, outer_pid, python = sys.argv[1], sys.argv[2], sys.argv[3]
sleeper = "import os, time; os.setsid(); time.sleep(600)"
outer = subprocess.Popen(["/bin/sh", "-c", '"$0" -c "$1" & echo $! > "$2"; wait', python, sleeper, inner_pid],
                         cwd="nested", start_new_session=True)
open(outer_pid, "w").write(str(outer.pid))
deadline = time.time() + 5
while not (os.path.exists(inner_pid) and open(inner_pid).read().strip()) and time.time() < deadline:
    time.sleep(0.05)
inner = int(open(inner_pid).read())
while os.getsid(inner) != inner and time.time() < deadline:
    time.sleep(0.05)
open(outer_pid + ".sessions", "w").write("%d %d" % (os.getsid(outer.pid), os.getsid(inner)))
"""


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def gone_within(pid: int, seconds: float) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.05)
    return not alive(pid)


class ReapTests(unittest.TestCase):
    def setUp(self):
        # mkdtemp's path is under /var, which is a link to /private/var, the spelling lsof reports.
        self.base = tempfile.mkdtemp(prefix="bench-reap-")
        self.run_dir = os.path.join(self.base, "corpus")
        self.sibling = os.path.join(self.base, "corpus-2")
        os.makedirs(os.path.join(self.run_dir, "nested"))
        os.makedirs(self.sibling)
        self.pids = []
        self.env = dict(os.environ)

    def tearDown(self):
        for pid in self.pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        shutil.rmtree(self.base, ignore_errors=True)

    def read_pid(self, name: str) -> int:
        pid = int(Path(self.run_dir, name).read_text().strip())
        self.pids.append(pid)
        return pid

    def test_a_run_that_ends_normally_leaves_nothing_standing_in_its_directory(self):
        code, timed_out = bench.limited([sys.executable, "-c", SPAWNER, os.path.join(self.run_dir, "inner.pid"),
                                         os.path.join(self.run_dir, "outer.pid"), sys.executable],
                                        60, self.run_dir, self.env)
        self.assertEqual((code, timed_out), (0, False))
        outer, inner = self.read_pid("outer.pid"), self.read_pid("inner.pid")
        sessions = Path(self.run_dir, "outer.pid.sessions").read_text().split()
        self.assertEqual(sessions, [str(outer), str(inner)], "the shell and its child are not each in a session of its own")
        self.assertTrue(gone_within(outer, 3), "the shell in its own session outlived the run")
        self.assertTrue(gone_within(inner, 3), "the shell's child in a session of its own outlived the run")

    def test_a_process_in_a_sibling_whose_name_extends_the_run_directory_survives(self):
        sibling = subprocess.Popen(["/bin/sleep", "600"], cwd=self.sibling, start_new_session=True)
        self.pids.append(sibling.pid)
        code, _ = bench.limited(["/usr/bin/true"], 60, self.run_dir, self.env)
        self.assertEqual(code, 0)
        time.sleep(0.3)
        self.assertIsNone(sibling.poll(), "a process in corpus-2 was killed by the reap of corpus")
        sibling.kill()
        sibling.wait()

    def test_the_reaping_process_and_its_ancestors_are_spared(self):
        # A shell standing in the directory runs a Python that reaps that same directory: neither is killed.
        script = "import sys; sys.path.insert(0, sys.argv[1]); import bench; bench.reap_under(sys.argv[2])"
        # The trailing echo keeps the shell from exec'ing the Python, so a shell ancestor is still standing there.
        reaper = subprocess.run(["/bin/sh", "-c", '"$0" -c "$1" "$2" "$3"; echo after', sys.executable, script,
                                 str(Path(bench.__file__).parent), self.run_dir],
                                cwd=self.run_dir, capture_output=True, text=True, timeout=30)
        self.assertEqual(reaper.returncode, 0, reaper.stderr)
        self.assertEqual(reaper.stderr, "")
        self.assertEqual(reaper.stdout, "after\n", "the shell standing in the directory did not survive the reap")

    def test_a_directory_holding_the_checkout_or_home_is_refused(self):
        # The process listing is stubbed empty, so a reap the guard failed to refuse finds nothing to kill.
        with mock.patch.object(bench, "working_directories", return_value=[]):
            for directory in (bench.REPO, bench.REPO.parent, Path.home()):
                with self.assertRaises(bench.Halt):
                    bench.reap_under(directory)

    def test_an_lsof_that_fails_with_no_output_halts_rather_than_reaping_nothing(self):
        failed = subprocess.CompletedProcess(["lsof"], 1, stdout="", stderr="lsof: boom")
        with mock.patch.object(bench.subprocess, "run", return_value=failed):
            with self.assertRaises(bench.Halt):
                bench.working_directories()

    def test_a_process_still_standing_when_the_bound_runs_out_is_named(self):
        standing = [(424242, self.run_dir)]
        with mock.patch.object(bench, "working_directories", return_value=standing), \
                mock.patch.object(bench.os, "kill"), mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
            bench.reap_under(self.run_dir, bound=0.2)
        self.assertIn("still standing after 0.2 s: pid 424242 in %s" % self.run_dir, stderr.getvalue())

    def test_wall_time_ends_before_the_reap(self):
        with mock.patch.object(bench, "reap_under", side_effect=lambda _: time.sleep(0.5)):
            bench.limited(["/usr/bin/true"], 60, self.run_dir, self.env)
        self.assertLess(bench.LAST_ENDED, time.time() - 0.4, "LAST_ENDED was taken after the reap")


if __name__ == "__main__":
    unittest.main()
