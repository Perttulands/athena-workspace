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


def _make_repo_with_feature(repo: Path, bead_id: str) -> None:
    target = repo / "app.txt"
    (repo / "package.json").write_text('{"name":"test-repo","scripts":{"test":"echo unreachable"}}', encoding="utf-8")
    target.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "package.json", "app.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", f"bead-{bead_id}")
    target.write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "app.txt")
    _must_git(repo, "commit", "-m", "feature change")
    _must_git(repo, "checkout", "master")


def _write_repo_config(config_path: Path, repo_path: Path, test_cmd: str, timeout: int) -> None:
    payload = {
        "repos": {
            str(repo_path): {
                "test_cmd": test_cmd,
                "timeout": timeout,
            }
        }
    }
    config_path.write_text(json.dumps(payload), encoding="utf-8")


def _fake_npm_env(tmp_path: Path, exit_code: int) -> dict[str, str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    npm = bin_dir / "npm"
    npm.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                'if [[ "${1:-}" == "test" ]]; then',
                "  echo \"fake npm test\"",
                f"  exit {exit_code}",
                "fi",
                "echo \"unexpected npm args\" >&2",
                "exit 2",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    npm.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    return env


def test_configured_test_command_takes_priority_over_auto_detect(tmp_path: Path) -> None:
    repo = tmp_path / "repo-config-priority"
    repo.mkdir()
    _init_repo(repo)
    _make_repo_with_feature(repo, "bd-601")

    configured_runner = repo / "configured-tests.sh"
    configured_runner.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    configured_runner.chmod(0o755)

    config_file = tmp_path / "agents.json"
    _write_repo_config(config_file, repo, "./configured-tests.sh", 120)

    env = _fake_npm_env(tmp_path, exit_code=1)
    env["CONFIG_FILE"] = str(config_file)

    result = _run("merge", "bd-601", str(repo), env=env)
    assert result.returncode == 0, result.stderr
    assert "Test gate passed: ./configured-tests.sh" in result.stdout
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge bead-bd-601"


def test_configured_timeout_is_applied(tmp_path: Path) -> None:
    repo = tmp_path / "repo-config-timeout"
    repo.mkdir()
    _init_repo(repo)
    _make_repo_with_feature(repo, "bd-602")

    config_file = tmp_path / "agents.json"
    _write_repo_config(config_file, repo, "sleep 2", 1)

    env = os.environ.copy()
    env["CONFIG_FILE"] = str(config_file)

    result = _run("merge", "bd-602", str(repo), env=env)
    assert result.returncode == 1
    assert "Test gate failed: sleep 2 (exit 124)" in result.stderr
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "base"
