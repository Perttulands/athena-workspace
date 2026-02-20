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


def _setup_unresolved_conflict_repo(repo: Path, branch: str = "feature/senate") -> None:
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
    _must_git(repo, "commit", "-m", "feature")

    _must_git(repo, "checkout", "main")
    target.write_text("main\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "main")


def test_unresolved_conflict_escalates_case_to_senate_inbox(tmp_path: Path) -> None:
    repo = tmp_path / "repo-senate"
    repo.mkdir()
    _setup_unresolved_conflict_repo(repo)

    results_dir = tmp_path / "results"
    senate_inbox = tmp_path / "senate-inbox"
    results_dir.mkdir()
    senate_inbox.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SENATE_INBOX_DIR"] = str(senate_inbox)

    result = _run("merge", "feature/senate", str(repo), env=env)
    assert result.returncode == 1

    payload = json.loads((results_dir / "feature-senate-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "conflict"
    escalation = payload["extra"]["senate_escalation"]
    assert escalation["status"] == "pending"

    case_file = Path(escalation["case_file"])
    assert case_file.exists()
    case_payload = json.loads(case_file.read_text(encoding="utf-8"))
    assert case_payload["source"] == "centurion"
    assert case_payload["reason"] == "merge-conflict-unresolved"
    assert case_payload["status"] == "pending"
    assert case_payload["branch"] == "feature/senate"
