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


def _init_repo(repo: Path) -> None:
    _must_git(repo, "init", "-b", "master")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")
    readme = repo / "README.md"
    readme.write_text("ok\n", encoding="utf-8")
    _must_git(repo, "add", "README.md")
    _must_git(repo, "commit", "-m", "initial")


def test_status_scopes_centurion_results_to_each_repo(tmp_path: Path) -> None:
    repo_one = tmp_path / "repo-one"
    repo_two = tmp_path / "repo-two"
    repo_one.mkdir()
    repo_two.mkdir()
    _init_repo(repo_one)
    _init_repo(repo_two)

    config_file = tmp_path / "agents.json"
    config_file.write_text(
        json.dumps(
            {
                "repos": {
                    str(repo_one): {"test_cmd": "echo ok", "timeout": 60},
                    str(repo_two): {"test_cmd": "echo ok", "timeout": 60},
                }
            }
        ),
        encoding="utf-8",
    )

    results_dir = tmp_path / "results"
    results_dir.mkdir()
    (results_dir / "bd-111-centurion.json").write_text(
        json.dumps(
            {
                "bead": "bd-111",
                "status": "conflict",
                "repo_path": str(repo_one),
                "files": ["README.md"],
                "timestamp": "2026-02-14T12:00:00Z",
                "last_output": None,
            }
        ),
        encoding="utf-8",
    )
    (results_dir / "bd-222-centurion.json").write_text(
        json.dumps(
            {
                "bead": "bd-222",
                "status": "test-failed",
                "repo_path": str(repo_two),
                "files": [],
                "timestamp": "2026-02-14T12:05:00Z",
                "last_output": "failed",
            }
        ),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["CONFIG_FILE"] = str(config_file)
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    status = _run("--status", env=env)
    assert status.returncode == 0, status.stderr

    first_block = status.stdout.split(f"Repo: {repo_two}")[0]
    second_block = status.stdout.split(f"Repo: {repo_two}", 1)[1]

    assert "bd-111-centurion.json" in first_block
    assert "bd-222-centurion.json" not in first_block
    assert "bd-222-centurion.json" in second_block
    assert "bd-111-centurion.json" not in second_block
