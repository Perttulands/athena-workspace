from __future__ import annotations

import json
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


def _create_repo_with_develop_and_feature(repo: Path, bead_id: str) -> None:
    app = repo / "app.txt"
    app.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "base commit")

    _must_git(repo, "checkout", "-b", "develop")
    _must_git(repo, "checkout", "master")

    _must_git(repo, "checkout", "-b", f"bead-{bead_id}")
    app.write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature commit")
    _must_git(repo, "checkout", "master")


def test_status_includes_branch_develop_unmerged_and_results(tmp_path: Path) -> None:
    repo = tmp_path / "repo-status"
    repo.mkdir()
    _init_repo(repo)
    _create_repo_with_develop_and_feature(repo, "701")

    results_dir = tmp_path / "results"
    results_dir.mkdir()
    (results_dir / "701-centurion.json").write_text(
        json.dumps(
            {
                "bead": "701",
                "status": "conflict",
                "repo_path": str(repo),
                "files": ["app.txt"],
                "timestamp": "2026-02-14T10:00:00Z",
                "last_output": None,
            }
        ),
        encoding="utf-8",
    )

    env = {"CENTURION_RESULTS_DIR": str(results_dir)}
    env.update({k: v for k, v in __import__("os").environ.items() if k not in env})

    result = _run("--status", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert f"Repo: {repo}" in result.stdout
    assert "Current branch: master" in result.stdout
    assert "Develop: " in result.stdout
    assert "Unmerged bead branches: 1" in result.stdout
    assert "Active agent worktrees:" in result.stdout
    assert "Recent centurion results:" in result.stdout
    assert "701-centurion.json" in result.stdout


def test_status_uses_configured_repos_when_repo_path_omitted(tmp_path: Path) -> None:
    repo = tmp_path / "repo-from-config"
    repo.mkdir()
    _init_repo(repo)

    readme = repo / "README.md"
    readme.write_text("hello\n", encoding="utf-8")
    _must_git(repo, "add", "README.md")
    _must_git(repo, "commit", "-m", "initial")

    config_file = tmp_path / "agents.json"
    config_file.write_text(json.dumps({"repos": {str(repo): {"test_cmd": "echo ok", "timeout": 60}}}), encoding="utf-8")

    env = {"CONFIG_FILE": str(config_file)}
    env.update({k: v for k, v in __import__("os").environ.items() if k not in env})

    result = _run("--status", env=env)
    assert result.returncode == 0, result.stderr
    assert f"Repo: {repo}" in result.stdout
    assert "Current branch: master" in result.stdout
