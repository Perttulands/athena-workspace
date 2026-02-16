from pathlib import Path
import re

DISPATCH = Path("scripts/dispatch.sh")


def test_dispatch_skips_centurion_merge_for_non_git_repos() -> None:
    text = DISPATCH.read_text(encoding="utf-8")
    assert re.search(
        r'if\s+\[\[\s+"\$status"\s+==\s+"done"\s+&&\s+"\$verification_overall"\s+==\s+"pass"\s+\]\];\s+then'
        r'.*?if\s+git\s+-C\s+"\$ORIGINAL_REPO_PATH"\s+rev-parse\s+--git-dir\s+>/dev/null\s+2>&1;\s+then'
        r'.*?centurion\.sh"\s+merge\s+"\$BEAD_ID"\s+"\$ORIGINAL_REPO_PATH"',
        text,
        re.S,
    )
    assert 'merge skipped (non-git repo)' in text
