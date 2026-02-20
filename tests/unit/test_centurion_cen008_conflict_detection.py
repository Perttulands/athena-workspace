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


def _setup_conflict_repo(repo: Path, branch: str = "feature/conflict") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    target = repo / "shared.txt"
    target.write_text("line\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    target.write_text("feature\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "feature change")

    _must_git(repo, "checkout", "main")
    target.write_text("main\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "main change")


def test_conflict_result_contains_structured_conflict_report(tmp_path: Path) -> None:
    repo = tmp_path / "repo-conflict"
    repo.mkdir()
    _setup_conflict_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    result = _run("merge", "feature/conflict", str(repo), env=env)
    assert result.returncode == 1
    assert "Merge conflict" in result.stderr

    payload = json.loads((results_dir / "feature-conflict-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "conflict"
    assert payload["quality_level"] == "standard"

    report = payload["extra"]
    assert report["conflict_count"] >= 1
    assert report["conflicts"][0]["file"] == "shared.txt"
    assert len(report["conflicts"][0]["marker_lines"]) >= 1
