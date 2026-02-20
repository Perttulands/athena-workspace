from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

CENTURION = Path("scripts/centurion.sh")


def _run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(CENTURION), *args],
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def _must_git(repo: Path, *args: str) -> str:
    proc = _git(repo, *args)
    assert proc.returncode == 0, proc.stderr
    return proc.stdout.strip()


def _setup_repo(repo: Path, branch: str = "feature/history") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    (repo / "file.txt").write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "file.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    (repo / "file.txt").write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "file.txt")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def test_merge_writes_history_and_history_command_reads_it(tmp_path: Path) -> None:
    repo = tmp_path / "repo-history"
    repo.mkdir()
    _setup_repo(repo)

    history_file = tmp_path / "centurion-history.jsonl"

    env = os.environ.copy()
    env["CENTURION_HISTORY_FILE"] = str(history_file)
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    merge = _run("merge", "--level", "quick", "feature/history", str(repo), env=env)
    assert merge.returncode == 0, merge.stderr

    lines = history_file.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 1
    payload = json.loads(lines[0])
    assert payload["status"] == "merged"
    assert payload["branch"] == "feature/history"
    assert payload["quality_level"] == "quick"
    assert payload["duration_ms"] >= 0

    history = _run("history", "--limit", "1", env=env)
    assert history.returncode == 0, history.stderr
    assert "status=merged" in history.stdout
    assert "branch=feature/history" in history.stdout
