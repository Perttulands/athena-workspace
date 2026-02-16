from __future__ import annotations

import os
from pathlib import Path
import subprocess

PROMOTE = Path("scripts/centurion-promote.sh")


def _run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(PROMOTE), *args],
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


def _setup_repo(repo: Path) -> None:
    _init_repo(repo)

    app = repo / "app.txt"
    app.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", "develop")
    app.write_text("base\ndevelop\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "develop change")
    _must_git(repo, "checkout", "master")


def _fake_wake_env(tmp_path: Path) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    wake_script = bin_dir / "wake-gateway.sh"
    wake_log = tmp_path / "wake.log"

    wake_script.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'echo "${1:-}" >> "${WAKE_LOG_FILE:?}"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    wake_script.chmod(0o755)

    env = os.environ.copy()
    env["CENTURION_WAKE_BIN"] = str(wake_script)
    env["WAKE_LOG_FILE"] = str(wake_log)
    return env, wake_log


def _write_fake_npm(bin_dir: Path, test_exit_code: int) -> Path:
    npm = bin_dir / "npm"
    npm.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'if [[ "${1:-}" == "test" ]]; then',
                '  printf "%s\\n" "$(git rev-parse --abbrev-ref HEAD)" >> "${NPM_BRANCH_LOG:?}"',
                f"  exit {test_exit_code}",
                "fi",
                "exit 2",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    npm.chmod(0o755)
    return npm


def test_promote_merges_develop_into_master_after_passing_tests(tmp_path: Path) -> None:
    repo = tmp_path / "repo-pass"
    repo.mkdir()
    _setup_repo(repo)
    (repo / "package.json").write_text('{"name":"repo-pass","scripts":{"test":"echo ok"}}', encoding="utf-8")

    env, wake_log = _fake_wake_env(tmp_path)
    bin_dir = Path(env["CENTURION_WAKE_BIN"]).parent
    branch_log = tmp_path / "npm-branches.log"
    _write_fake_npm(bin_dir, test_exit_code=0)
    env["NPM_BRANCH_LOG"] = str(branch_log)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    promoted = _run(str(repo), env=env)
    assert promoted.returncode == 0, promoted.stderr

    assert _must_git(repo, "rev-parse", "--abbrev-ref", "HEAD") == "master"
    assert "develop" in (repo / "app.txt").read_text(encoding="utf-8")

    merge_subject = _must_git(repo, "log", "-1", "--pretty=%s", "master")
    assert merge_subject == "centurion: promote develop to master"

    parents = _must_git(repo, "rev-list", "--parents", "-n", "1", "HEAD").split()
    assert len(parents) == 3

    assert branch_log.read_text(encoding="utf-8").strip() == "develop"
    wake_message = wake_log.read_text(encoding="utf-8")
    assert "Centurion: promoted develop to master" in wake_message


def test_promote_fails_when_develop_tests_fail(tmp_path: Path) -> None:
    repo = tmp_path / "repo-fail"
    repo.mkdir()
    _setup_repo(repo)
    (repo / "package.json").write_text('{"name":"repo-fail","scripts":{"test":"echo fail"}}', encoding="utf-8")

    master_before = _must_git(repo, "rev-parse", "master")

    env, wake_log = _fake_wake_env(tmp_path)
    bin_dir = Path(env["CENTURION_WAKE_BIN"]).parent
    branch_log = tmp_path / "npm-branches-fail.log"
    _write_fake_npm(bin_dir, test_exit_code=1)
    env["NPM_BRANCH_LOG"] = str(branch_log)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    promoted = _run(str(repo), env=env)
    assert promoted.returncode == 1

    master_after = _must_git(repo, "rev-parse", "master")
    assert master_after == master_before
    assert branch_log.read_text(encoding="utf-8").strip() == "develop"

    wake_message = wake_log.read_text(encoding="utf-8")
    assert "Centurion: develop test gate failed" in wake_message


def test_promote_dry_run_does_not_modify_repo(tmp_path: Path) -> None:
    repo = tmp_path / "repo-dry-run"
    repo.mkdir()
    _setup_repo(repo)

    master_before = _must_git(repo, "rev-parse", "master")

    promoted = _run("--dry-run", str(repo))
    assert promoted.returncode == 0, promoted.stderr
    assert "DRY RUN" in promoted.stdout

    master_after = _must_git(repo, "rev-parse", "master")
    assert master_after == master_before
