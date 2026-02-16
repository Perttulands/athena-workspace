from pathlib import Path
import subprocess

CENTURION = Path("scripts/centurion.sh")


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(CENTURION), *args],
        text=True,
        capture_output=True,
        check=False,
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


def test_merge_creates_develop_and_merges_feature_branch(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)

    target = repo / "notes.txt"
    target.write_text("base\n", encoding="utf-8")
    _must_git(repo, "add", "notes.txt")
    _must_git(repo, "commit", "-m", "base")

    _must_git(repo, "checkout", "-b", "bead-bd-123")
    target.write_text("base\nfeature\n", encoding="utf-8")
    _must_git(repo, "add", "notes.txt")
    _must_git(repo, "commit", "-m", "feature change")
    _must_git(repo, "checkout", "master")

    assert _must_git(repo, "branch", "--list", "develop") == ""

    merged = _run("merge", "bd-123", str(repo))
    assert merged.returncode == 0, merged.stderr

    assert _must_git(repo, "branch", "--list", "develop")
    assert _must_git(repo, "rev-parse", "--abbrev-ref", "HEAD") == "develop"
    assert _must_git(repo, "show", "-s", "--format=%s", "HEAD") == "centurion: merge bead-bd-123"


def test_merge_conflict_is_aborted(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
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

    merged = _run("merge", "bd-999", str(repo))
    assert merged.returncode == 1

    merge_head = _git(repo, "rev-parse", "-q", "--verify", "MERGE_HEAD")
    assert merge_head.returncode != 0
