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


def _setup_modify_delete_conflict_repo(repo: Path, branch: str = "feature/auto") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    target = repo / "shared.txt"
    target.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    _must_git(repo, "rm", "shared.txt")
    _must_git(repo, "commit", "-m", "delete file")

    _must_git(repo, "checkout", "main")
    target.write_text("main-updated\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "modify file")


def test_trivial_conflict_is_auto_resolved_with_strategy_metadata(tmp_path: Path) -> None:
    repo = tmp_path / "repo-auto-resolve"
    repo.mkdir()
    _setup_modify_delete_conflict_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    result = _run("merge", "feature/auto", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "Auto-resolved trivial conflicts" in result.stdout

    payload = json.loads((results_dir / "feature-auto-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "merged"

    extra = payload["extra"]
    assert extra["auto_resolution"]["resolved_count"] >= 1
    assert extra["auto_resolution"]["unresolved_count"] == 0
    assert extra["auto_resolution"]["resolved"][0]["strategy"] in {"ours", "theirs"}

    assert (repo / "shared.txt").read_text(encoding="utf-8") == "main-updated\n"
