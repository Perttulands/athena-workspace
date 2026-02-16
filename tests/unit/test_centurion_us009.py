from pathlib import Path
import re

DISPATCH = Path("scripts/dispatch.sh")


def _text() -> str:
    return DISPATCH.read_text(encoding="utf-8")


def test_dispatch_references_centurion_merge() -> None:
    text = _text()
    assert text.count("centurion") >= 2
    assert re.search(r'centurion\.sh"\s+merge\s+"\$BEAD_ID"\s+"\$ORIGINAL_REPO_PATH"', text)


def test_dispatch_gates_centurion_merge_on_done_and_verify_pass() -> None:
    text = _text()
    assert re.search(r'\[\[\s+"\$status"\s+==\s+"done"\s+&&\s+"\$verification_overall"\s+==\s+"pass"\s+\]\]', text)


def test_dispatch_centurion_failure_is_non_blocking() -> None:
    text = _text()
    assert re.search(
        r'if\s+!\s+"\$SCRIPT_DIR/centurion\.sh"\s+merge\s+"\$BEAD_ID"\s+"\$ORIGINAL_REPO_PATH";\s+then',
        text,
    )


def test_dispatch_runs_centurion_before_worktree_destroy() -> None:
    text = _text()
    centurion_idx = text.index('"$SCRIPT_DIR/centurion.sh" merge "$BEAD_ID" "$ORIGINAL_REPO_PATH"')
    destroy_idx = text.index('"$SCRIPT_DIR/worktree-manager.sh" destroy "$BEAD_ID" "$ORIGINAL_REPO_PATH" --force')
    assert centurion_idx < destroy_idx
