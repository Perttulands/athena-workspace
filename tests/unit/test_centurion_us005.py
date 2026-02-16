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
    _must_git(repo, "init", "-b", "master")
    _must_git(repo, "config", "user.name", "Centurion Test")
    _must_git(repo, "config", "user.email", "centurion@example.com")


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


def test_merge_conflict_records_files_and_sends_wake(tmp_path: Path) -> None:
    repo = tmp_path / "repo-conflict"
    repo.mkdir()
    _init_repo(repo)

    target = repo / "shared.txt"
    target.write_text("line\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", "bead-bd-999")
    target.write_text("feature\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "feature change")

    _must_git(repo, "checkout", "master")
    target.write_text("develop\n", encoding="utf-8")
    _must_git(repo, "add", "shared.txt")
    _must_git(repo, "commit", "-m", "master change")

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env, wake_log = _fake_wake_env(tmp_path)
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    merged = _run("merge", "bd-999", str(repo), env=env)
    assert merged.returncode == 1

    wake_message = wake_log.read_text(encoding="utf-8")
    assert "Centurion: merge conflict for bead-bd-999" in wake_message
    assert "shared.txt" in wake_message

    result_file = results_dir / "bd-999-centurion.json"
    assert result_file.exists()
    payload = json.loads(result_file.read_text(encoding="utf-8"))
    assert payload["bead"] == "bd-999"
    assert payload["status"] == "conflict"
    assert payload["files"] == ["shared.txt"]
    assert payload["timestamp"]


def test_test_gate_failure_records_output_and_sends_wake(tmp_path: Path) -> None:
    repo = tmp_path / "repo-test-fail"
    repo.mkdir()
    _init_repo(repo)

    target = repo / "app.txt"
    (repo / "package.json").write_text('{"name":"test-repo","scripts":{"test":"echo unreachable"}}', encoding="utf-8")
    target.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "package.json", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", "bead-bd-777")
    target.write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature change")
    _must_git(repo, "checkout", "master")

    results_dir = tmp_path / "results"
    results_dir.mkdir()

    env, wake_log = _fake_wake_env(tmp_path)
    env["CENTURION_RESULTS_DIR"] = str(results_dir)

    npm = tmp_path / "bin" / "npm"
    npm.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'if [[ "${1:-}" == "test" ]]; then',
                "  printf 'FAILLINE-%s\\n' 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'",
                "  exit 1",
                "fi",
                "exit 2",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    npm.chmod(0o755)
    env["PATH"] = f"{tmp_path / 'bin'}:{env['PATH']}"

    merged = _run("merge", "bd-777", str(repo), env=env)
    assert merged.returncode == 1

    wake_message = wake_log.read_text(encoding="utf-8")
    assert "Centurion: test gate failed for bead-bd-777" in wake_message

    result_file = results_dir / "bd-777-centurion.json"
    assert result_file.exists()
    payload = json.loads(result_file.read_text(encoding="utf-8"))
    assert payload["bead"] == "bd-777"
    assert payload["status"] == "test-failed"
    assert payload["timestamp"]
    assert payload["last_output"].startswith("FAILLINE-")
    assert len(payload["last_output"]) <= 200
