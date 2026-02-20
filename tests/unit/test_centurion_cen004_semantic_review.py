from __future__ import annotations

import os
from pathlib import Path
import subprocess

WORKSPACE = Path("/home/chrote/athena/workspace")
PROMPT = Path("skills/centurion-review.md")


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

    (repo / "app.txt").write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", "feature/semantic")
    (repo / "app.txt").write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def _run_semantic(repo: Path, review_cmd: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["REPO_PATH"] = str(repo)
    env["CENTURION_SEMANTIC_REVIEW_CMD"] = review_cmd

    script = "\n".join(
        [
            "set -euo pipefail",
            f'WORKSPACE_ROOT="{WORKSPACE}"',
            "source scripts/lib/common.sh",
            "source scripts/lib/config.sh",
            "source scripts/lib/centurion-semantic.sh",
            "set +e",
            'run_semantic_review "$REPO_PATH" "feature/semantic" "main"',
            "rc=$?",
            "set -e",
            'printf "RC=%s\\n" "$rc"',
            'printf "VERDICT=%s\\n" "$SEMANTIC_REVIEW_LAST_VERDICT"',
            'printf "JSON=%s\\n" "$SEMANTIC_REVIEW_LAST_JSON"',
        ]
    )

    return subprocess.run(
        ["bash", "-lc", script],
        cwd=WORKSPACE,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


def test_semantic_prompt_file_exists() -> None:
    assert PROMPT.exists()
    assert "Output Contract" in PROMPT.read_text(encoding="utf-8")


def test_semantic_review_parses_pass_verdict(tmp_path: Path) -> None:
    repo = tmp_path / "repo-semantic-pass"
    repo.mkdir()
    _setup_repo(repo)

    cmd = "printf '{\"verdict\":\"pass\",\"summary\":\"looks good\",\"flags\":[\"semantic.ok\"]}'"
    result = _run_semantic(repo, cmd)

    assert result.returncode == 0, result.stderr
    assert "RC=0" in result.stdout
    assert "VERDICT=pass" in result.stdout
    assert '"verdict":"pass"' in result.stdout


def test_semantic_review_marks_invalid_output_as_review_needed(tmp_path: Path) -> None:
    repo = tmp_path / "repo-semantic-invalid"
    repo.mkdir()
    _setup_repo(repo)

    result = _run_semantic(repo, "printf 'not-json'")

    assert result.returncode == 0, result.stderr
    assert "RC=2" in result.stdout
    assert "VERDICT=review-needed" in result.stdout
    assert "semantic review output was not valid JSON" in result.stdout
