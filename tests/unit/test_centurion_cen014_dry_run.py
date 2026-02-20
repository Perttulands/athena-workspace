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


def _setup_repo(repo: Path, branch: str = "feature/dry-run") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    (repo / "app.txt").write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    (repo / "app.txt").write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def test_dry_run_executes_checks_but_leaves_main_unchanged(tmp_path: Path) -> None:
    repo = tmp_path / "repo-dry-run"
    repo.mkdir()
    _setup_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    before = _must_git(repo, "rev-parse", "HEAD")

    result = _run("merge", "--dry-run", "--level", "quick", "feature/dry-run", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "DRY RUN" in result.stdout or "dry-run" in result.stdout

    after = _must_git(repo, "rev-parse", "HEAD")
    assert after == before

    payload = json.loads((results_dir / "feature-dry-run-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "dry-run-pass"
    assert payload["quality_level"] == "quick"
