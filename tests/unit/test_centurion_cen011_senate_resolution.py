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


def _setup_unresolved_conflict_repo(repo: Path, branch: str = "feature/senate-resolve") -> None:
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


def test_conflict_can_be_resolved_via_senate_verdict(tmp_path: Path) -> None:
    repo = tmp_path / "repo-senate-resolve"
    repo.mkdir()
    _setup_unresolved_conflict_repo(repo)

    results_dir = tmp_path / "results"
    senate_inbox = tmp_path / "senate-inbox"
    senate_verdicts = tmp_path / "senate-verdicts"
    results_dir.mkdir()
    senate_inbox.mkdir()
    senate_verdicts.mkdir()

    case_id = "centurion-test-case-011"
    verdict_file = senate_verdicts / f"{case_id}.json"
    verdict_file.write_text(
        json.dumps(
            {
                "case_id": case_id,
                "resolution": {
                    "mode": "ours",
                    "files": [{"path": "shared.txt", "strategy": "ours"}],
                },
            }
        ),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SENATE_INBOX_DIR"] = str(senate_inbox)
    env["CENTURION_SENATE_VERDICTS_DIR"] = str(senate_verdicts)
    env["CENTURION_SENATE_CASE_ID"] = case_id
    env["CENTURION_SENATE_WAIT_SECONDS"] = "1"
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"

    result = _run("merge", "feature/senate-resolve", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "Resolved conflict via Senate verdict" in result.stdout

    payload = json.loads((results_dir / "feature-senate-resolve-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "merged"
    assert payload["extra"]["senate_resolution"]["status"] == "applied"

    assert (repo / "shared.txt").read_text(encoding="utf-8") == "main\n"
