from __future__ import annotations

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


def _setup_repo(repo: Path, branch: str = "feature/logging") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    (repo / "notes.txt").write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "notes.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    (repo / "notes.txt").write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "notes.txt")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def test_verbose_mode_emits_debug_logs(tmp_path: Path) -> None:
    repo = tmp_path / "repo-verbose"
    repo.mkdir()
    _setup_repo(repo)

    env = os.environ.copy()
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    result = _run("merge", "--verbose", "--level", "quick", "feature/logging", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "[DEBUG] Starting merge" in result.stdout


def test_quiet_mode_suppresses_info_logs(tmp_path: Path) -> None:
    repo = tmp_path / "repo-quiet"
    repo.mkdir()
    _setup_repo(repo)

    env = os.environ.copy()
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    result = _run("merge", "--quiet", "--level", "quick", "feature/logging", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "PASS: merged feature/logging to main" in result.stdout
    assert "[INFO]" not in result.stdout
    assert "[DEBUG]" not in result.stdout
