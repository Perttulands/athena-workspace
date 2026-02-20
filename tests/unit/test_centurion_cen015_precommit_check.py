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


def _setup_repo(repo: Path) -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")
    (repo / "README.md").write_text("hello\n", encoding="utf-8")
    _must_git(repo, "add", "README.md")
    _must_git(repo, "commit", "-m", "base")


def test_check_command_passes_for_quick_level(tmp_path: Path) -> None:
    repo = tmp_path / "repo-check-pass"
    repo.mkdir()
    _setup_repo(repo)

    result = _run("check", "--level", "quick", "--quiet", str(repo))
    assert result.returncode == 0, result.stderr
    assert "PASS: check passed" in result.stdout


def test_check_command_fails_when_lint_cmd_fails(tmp_path: Path) -> None:
    repo = tmp_path / "repo-check-fail"
    repo.mkdir()
    _setup_repo(repo)

    config_file = tmp_path / "agents.json"
    config_file.write_text(
        json.dumps({"repos": {str(repo): {"lint_cmd": "false", "timeout": 60}}}),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["CONFIG_FILE"] = str(config_file)

    result = _run("check", "--level", "quick", str(repo), env=env)
    assert result.returncode == 1
    assert "Quality check failed" in result.stderr
