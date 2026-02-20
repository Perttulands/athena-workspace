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
    _must_git(repo, "init", "-b", "main")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")


def _setup_repo(repo: Path, branch: str = "feature/quality") -> None:
    _init_repo(repo)

    (repo / "package.json").write_text(
        json.dumps({"name": "quality-test", "scripts": {"test": "echo unreachable"}}),
        encoding="utf-8",
    )
    (repo / "app.txt").write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "package.json", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", branch)
    (repo / "app.txt").write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature")
    _must_git(repo, "checkout", "main")


def _fake_npm_env(tmp_path: Path, *, exit_code: int) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    npm_log = tmp_path / "npm.log"
    npm = bin_dir / "npm"
    npm.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'if [[ "${1:-}" == "test" ]]; then',
                '  echo "npm test" >> "${NPM_LOG_PATH:?}"',
                f"  exit {exit_code}",
                "fi",
                "exit 0",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    npm.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["NPM_LOG_PATH"] = str(npm_log)
    return env, npm_log


def test_merge_defaults_to_standard_quality_level(tmp_path: Path) -> None:
    repo = tmp_path / "repo-standard"
    repo.mkdir()
    _setup_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env, npm_log = _fake_npm_env(tmp_path, exit_code=1)
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    result = _run("merge", "feature/quality", str(repo), env=env)
    assert result.returncode == 1
    assert "Test gate failed: npm test" in result.stderr

    assert npm_log.read_text(encoding="utf-8").strip() == "npm test"
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "base"

    payload = json.loads((results_dir / "feature-quality-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "quality-failed"
    assert payload["quality_level"] == "standard"


def test_merge_quick_level_skips_tests(tmp_path: Path) -> None:
    repo = tmp_path / "repo-quick"
    repo.mkdir()
    _setup_repo(repo)

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env, npm_log = _fake_npm_env(tmp_path, exit_code=1)
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    result = _run("merge", "--level", "quick", "feature/quality", str(repo), env=env)
    assert result.returncode == 0, result.stderr

    assert not npm_log.exists() or npm_log.read_text(encoding="utf-8").strip() == ""
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge feature/quality to main"

    payload = json.loads((results_dir / "feature-quality-centurion.json").read_text(encoding="utf-8"))
    assert payload["status"] == "merged"
    assert payload["quality_level"] == "quick"


def test_merge_rejects_unknown_quality_level(tmp_path: Path) -> None:
    repo = tmp_path / "repo-invalid"
    repo.mkdir()
    _setup_repo(repo)

    result = _run("merge", "--level", "turbo", "feature/quality", str(repo))
    assert result.returncode == 1
    assert "invalid quality level 'turbo'" in result.stderr
