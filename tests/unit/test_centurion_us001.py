from pathlib import Path
import re

DISPATCH = Path('scripts/dispatch.sh')


def _text() -> str:
    return DISPATCH.read_text(encoding='utf-8')


def test_dispatch_references_worktree_manager_create_and_destroy() -> None:
    text = _text()
    assert text.count('worktree-manager.sh') >= 2
    assert re.search(r'worktree-manager\.sh"\s+create\s+"\$BEAD_ID"\s+"\$REPO_PATH"', text)
    assert re.search(r'worktree-manager\.sh"\s+destroy\s+"\$BEAD_ID"\s+"\$ORIGINAL_REPO_PATH"\s+--force', text)


def test_dispatch_tracks_original_and_worktree_paths() -> None:
    text = _text()
    assert 'WORKTREE_PATH=""' in text
    assert 'ORIGINAL_REPO_PATH=""' in text


def test_tmux_uses_worktree_path() -> None:
    text = _text()
    assert re.search(r'new-session\s+-d\s+-s\s+"\$SESSION_NAME"\s+-c\s+"\$WORKTREE_PATH"', text)
