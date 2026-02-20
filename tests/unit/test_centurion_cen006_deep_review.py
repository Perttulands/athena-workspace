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


def _setup_repo(repo: Path, branch: str = "feature/deep") -> None:
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")

    tests_dir = repo / "tests"
    tests_dir.mkdir()

    (repo / "app.py").write_text("def add(a, b):\n    return a + b\n", encoding="utf-8")
    (tests_dir / "test_app.py").write_text(
        "from app import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n",
        encoding="utf-8",
    )
    _must_git(repo, "add", "app.py", "tests/test_app.py")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    (repo / "app.py").write_text("def add(a, b):\n    return a + b + 1\n", encoding="utf-8")
    (tests_dir / "test_app.py").write_text(
        "from app import add\n\n\ndef test_add():\n    assert add(1, 2) == 4\n",
        encoding="utf-8",
    )
    _must_git(repo, "add", "app.py", "tests/test_app.py")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def test_deep_merge_runs_semantic_review_and_passes(tmp_path: Path) -> None:
    repo = tmp_path / "repo-deep-pass"
    repo.mkdir()
    _setup_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"
    env["CENTURION_SEMANTIC_REVIEW_CMD"] = (
        "printf '{\"verdict\":\"pass\",\"summary\":\"semantic ok\",\"flags\":[\"semantic.ok\"]}'"
    )

    result = _run("merge", "--level", "deep", "feature/deep", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "Semantic review passed" in result.stdout
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge feature/deep to main"

    payload = json.loads((results_dir / "feature-deep-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "merged"
    assert payload["quality_level"] == "deep"


def test_deep_merge_reverts_when_semantic_review_fails(tmp_path: Path) -> None:
    repo = tmp_path / "repo-deep-fail"
    repo.mkdir()
    _setup_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env = os.environ.copy()
    env["CENTURION_RESULTS_DIR"] = str(results_dir)
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"
    env["CENTURION_SEMANTIC_REVIEW_CMD"] = (
        "printf '{\"verdict\":\"fail\",\"summary\":\"semantic risk\",\"flags\":[\"semantic.risk\"]}'"
    )

    result = _run("merge", "--level", "deep", "feature/deep", str(repo), env=env)
    assert result.returncode == 1
    assert "semantic review failed" in result.stderr
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "base"

    payload = json.loads((results_dir / "feature-deep-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "semantic-failed"
    assert payload["quality_level"] == "deep"


def test_standard_merge_does_not_require_semantic_review(tmp_path: Path) -> None:
    repo = tmp_path / "repo-standard-no-semantic"
    repo.mkdir()
    _setup_repo(repo)

    env = os.environ.copy()
    env["CENTURION_SKIP_TRUTHSAYER"] = "true"
    env["CENTURION_SEMANTIC_REVIEW_CMD"] = "exit 99"

    result = _run("merge", "--level", "standard", "feature/deep", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge feature/deep to main"
