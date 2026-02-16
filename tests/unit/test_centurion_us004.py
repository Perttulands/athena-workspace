from pathlib import Path
import os
import subprocess

CENTURION = Path("scripts/centurion.sh")
SHARED_TEST_GATE = Path("scripts/lib/centurion-test-gate.sh")


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


def _fake_npm_env(tmp_path: Path, exit_code: int) -> dict[str, str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
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


def test_merge_runs_test_gate_and_keeps_merge_on_pass(tmp_path: Path) -> None:
    repo = tmp_path / "repo-pass"
    repo.mkdir()
    _init_repo(repo)
    _make_repo_with_feature(repo, "bd-401")

    result = _run("merge", "bd-401", str(repo), env=_fake_npm_env(tmp_path, exit_code=0))
    assert result.returncode == 0, result.stderr
    assert _must_git(repo, "rev-parse", "--abbrev-ref", "HEAD") == "develop"
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge bead-bd-401"


def test_merge_reverts_commit_when_test_gate_fails(tmp_path: Path) -> None:
    repo = tmp_path / "repo-fail"
    repo.mkdir()
    _init_repo(repo)
    _make_repo_with_feature(repo, "bd-402")

    result = _run("merge", "bd-402", str(repo), env=_fake_npm_env(tmp_path, exit_code=1))
    assert result.returncode == 1
    assert "Test gate failed" in result.stderr
    assert _must_git(repo, "rev-parse", "--abbrev-ref", "HEAD") == "develop"
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "base"


def test_script_contains_runner_detection_for_supported_stacks() -> None:
    contents = CENTURION.read_text(encoding="utf-8")
    shared_contents = SHARED_TEST_GATE.read_text(encoding="utf-8")
    assert "run_test_gate" in contents
    assert 'source "$SCRIPT_DIR/lib/centurion-test-gate.sh"' in contents
    assert "package.json" in shared_contents
    assert "go.mod" in shared_contents
    assert "Cargo.toml" in shared_contents
    assert "timeout" in shared_contents
