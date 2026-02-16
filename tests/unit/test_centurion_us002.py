from pathlib import Path
import os
import subprocess

CENTURION = Path("scripts/centurion.sh")


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(CENTURION), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def test_centurion_script_exists_and_is_shell_valid() -> None:
    assert CENTURION.exists()
    parse = subprocess.run(
        ["bash", "-n", str(CENTURION)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert parse.returncode == 0, parse.stderr


def test_help_output() -> None:
    result = _run("--help")
    assert result.returncode == 0
    assert "Usage: centurion.sh <command> [args...]" in result.stdout


def test_merge_argument_validation_and_status_output() -> None:
    merge = _run("merge")
    assert merge.returncode == 1
    assert "Error: merge requires <bead-id> <repo-path>" in merge.stderr

    status = _run("--status")
    assert status.returncode == 0
    assert "Repo:" in status.stdout


def test_script_is_executable() -> None:
    assert os.access(CENTURION, os.X_OK)
